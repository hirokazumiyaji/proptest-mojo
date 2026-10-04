"""One property execution: choice supply, spans, and outcome status.

Implements the `TestCase` section of `docs/specs/choice-sequence.md`
(ADR-0002, ADR-0004, ADR-0006, ADR-0008).

`TestCase` is the only mutable object on the generation path. It supplies
choices either from its PRNG (generating) or from a recorded prefix
(replaying), records every choice into a `ChoiceSequence`, tracks spans,
and carries the execution `Status` the runner classifies on.
"""

from std.io import Writer

from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence, Span
from proptest.prng import Xoshiro256StarStar
from proptest.strategy import Strategy

comptime DEFAULT_MAX_CHOICES = 8192
comptime ASSUME_INTERRUPT = "proptest: assume() failed (INVALID)"
comptime OVERRUN_INTERRUPT = "proptest: choice budget exhausted (OVERRUN)"


@fieldwise_init
struct Status(Equatable, TrivialRegisterPassable, Writable):
    """Outcome of one property execution, owned by `TestCase`.

    The runner classifies a finished execution by this value, never by an
    exception message, so user-raised messages cannot collide with control
    flow.
    """

    var value: UInt8

    comptime RUNNING = Status(0)
    comptime VALID = Status(1)
    comptime INVALID = Status(2)
    comptime OVERRUN = Status(3)
    comptime INTERESTING = Status(4)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def write_to(self, mut writer: Some[Writer]):
        if self == Self.RUNNING:
            writer.write("RUNNING")
        elif self == Self.VALID:
            writer.write("VALID")
        elif self == Self.INVALID:
            writer.write("INVALID")
        elif self == Self.OVERRUN:
            writer.write("OVERRUN")
        else:
            writer.write("INTERESTING")


@fieldwise_init
struct OpenSpan(Copyable, Movable):
    """Bookkeeping for a span opened by `start_span`, closed by `stop_span`."""

    var start: Int
    var label: UInt64
    var depth: Int


struct TestCase(Sized, Writable):
    """Mutable execution context for one property run.

    Generating mode draws from `prng`. Replaying mode replays `prefix` and
    yields 0 past its end, so shrink candidates evaluate deterministically.
    A prefix value above the current bound is clamped, keeping replay valid
    when an earlier choice moved its bound.
    """

    var prng: Xoshiro256StarStar
    var prefix: ChoiceSequence
    var cursor: Int
    var replay_mode: Bool
    var choices: ChoiceSequence
    var spans: List[Span]
    var open_spans: List[OpenSpan]
    var status: Status
    var notes: List[String]
    var draw_labels: List[String]
    var draw_values: List[String]
    var max_choices: Int

    def __init__(
        out self,
        var prng: Xoshiro256StarStar,
        max_choices: Int = DEFAULT_MAX_CHOICES,
    ):
        self.prng = prng^
        self.prefix = ChoiceSequence()
        self.cursor = 0
        self.replay_mode = False
        self.choices = ChoiceSequence()
        self.spans = List[Span]()
        self.open_spans = List[OpenSpan]()
        self.status = Status.RUNNING
        self.notes = List[String]()
        self.draw_labels = List[String]()
        self.draw_values = List[String]()
        self.max_choices = max_choices

    @staticmethod
    def generating(
        var prng: Xoshiro256StarStar,
        max_choices: Int = DEFAULT_MAX_CHOICES,
    ) -> Self:
        """Fresh execution drawing from `prng`."""
        return Self(prng^, max_choices)

    @staticmethod
    def replaying(
        var prefix: ChoiceSequence,
        max_choices: Int = DEFAULT_MAX_CHOICES,
    ) -> Self:
        """Execution replaying `prefix`, yielding 0 past its end.

        The embedded PRNG is never consumed in this mode.
        """
        var tc = Self(Xoshiro256StarStar.from_seed(UInt64(0)), max_choices)
        tc.prefix = prefix^
        tc.cursor = 0
        tc.replay_mode = True
        return tc^

    def __len__(self) -> Int:
        return len(self.choices)

    def draw_integer(mut self, max_value: UInt64) raises -> UInt64:
        """Draw an integer in `0..=max_value`, where 0 is simplest."""
        self._ensure_capacity()
        var value = self._supply_integer(max_value)
        return self._record(ChoiceKind.INTEGER, value, max_value, Bool(False))

    def draw_boolean(mut self, p_true: Float64 = 0.5) raises -> Bool:
        """Draw a biased coin flip, recorded as 0/1 with 0 simplest.

        The bias shapes generation only; replay reuses the recorded bit.
        """
        self._ensure_capacity()
        var bit: UInt64
        if self.replay_mode:
            bit = self._supply_integer(UInt64(1))
        else:
            bit = UInt64(1) if self.prng.next_float64() < p_true else UInt64(0)
        var recorded = self._record(
            ChoiceKind.BOOLEAN, bit, UInt64(1), Bool(False)
        )
        return recorded == UInt64(1)

    def forced_integer(
        mut self, value: UInt64, max_value: UInt64
    ) raises -> UInt64:
        """Record a generator-fixed choice, kept out of shrinking.

        Consumes no randomness. In replay mode the prefix cursor still
        advances so a forced choice occupies its recorded slot, keeping
        later replayed draws aligned with the original run.
        """
        self._ensure_capacity()
        var clamped = value
        if clamped > max_value:
            clamped = max_value
        if self.replay_mode:
            self.cursor += 1
        return self._record(ChoiceKind.INTEGER, clamped, max_value, Bool(True))

    def start_span(mut self, label: UInt64):
        """Open a span over subsequently recorded choices."""
        self.open_spans.append(
            OpenSpan(len(self.choices), label, len(self.open_spans))
        )

    def stop_span(mut self, discard: Bool = False):
        """Close the innermost open span; no-op when none is open."""
        if len(self.open_spans) == 0:
            return
        var frame = self.open_spans.pop()
        self.spans.append(
            Span(
                frame.start,
                len(self.choices),
                frame.label,
                frame.depth,
                discard,
            )
        )

    def assume(mut self, condition: Bool) raises:
        """Abort with `INVALID` unless `condition` holds."""
        if not condition:
            self.status = Status.INVALID
            raise Error(ASSUME_INTERRUPT)

    def draw[
        S: Strategy
    ](mut self, strategy: S, label: StringSlice = "") raises -> S.Value:
        """Draw a value through `strategy`, recording one span and report entry.

        Opens a span labeled by the strategy kind (`strategy.span_label`),
        never by `label`, so shrink passes only swap blocks that are
        structurally interchangeable; `label` is kept solely in
        `draw_labels`. The record slot is reserved *before* delegating to
        `strategy.draw`, so a composite strategy that calls `tc.draw`
        internally still reports its own entry first, matching invocation
        order. The rendered value is filled in once the draw returns. On
        raise, every span opened during this draw is closed and the
        reserved slot is dropped, so accounting stays balanced.
        """
        var depth = len(self.open_spans)
        self.start_span(strategy.span_label())
        # Reserved, not appended: a nested `tc.draw` inside `strategy`
        # would otherwise land before this record.
        var slot = len(self.draw_labels)
        self.draw_labels.append(String(label))
        self.draw_values.append(String(""))
        try:
            var value = strategy.draw(self)
            self.stop_span()
            self.draw_values[slot] = String(value)
            return value^
        except e:
            while len(self.open_spans) > depth:
                self.stop_span()
            # Drop the reserved slot, not the tail: nested `tc.draw`
            # calls in `strategy` appended records after it, and those
            # draws succeeded, so their entries must survive.
            _remove_at(self.draw_labels, slot)
            _remove_at(self.draw_values, slot)
            raise e

    def note(mut self, var message: String):
        """Attach a message shown when this example is replayed for a report."""
        self.notes.append(message^)

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "TestCase(status=",
            self.status,
            ", choices=",
            len(self.choices),
            ", spans=",
            len(self.spans),
            ", notes=",
            len(self.notes),
            ")",
        )

    def _ensure_capacity(mut self) raises:
        if len(self.choices) >= self.max_choices:
            self.status = Status.OVERRUN
            raise Error(OVERRUN_INTERRUPT)

    def _supply_integer(mut self, max_value: UInt64) raises -> UInt64:
        if self.replay_mode:
            var value = UInt64(0)
            if self.cursor < len(self.prefix):
                value = self.prefix[self.cursor].value
                if value > max_value:
                    value = max_value
            self.cursor += 1
            return value
        if max_value == UInt64(0xFFFFFFFFFFFFFFFF):
            return self.prng.next_u64()
        return self.prng.next_below(max_value + UInt64(1))

    def _record(
        mut self,
        kind: ChoiceKind,
        value: UInt64,
        max_value: UInt64,
        forced: Bool,
    ) -> UInt64:
        self.choices.append(ChoiceNode(kind, value, max_value, forced))
        return value


def _remove_at(mut items: List[String], index: Int):
    """Drop `items[index]`, shifting the tail left.

    `TestCase.draw` reserves its record slot before delegating, so a
    strategy that draws and then raises leaves successful nested records
    after the reserved one; popping would discard those instead.
    """
    var i = index
    while i + 1 < len(items):
        items[i] = items[i + 1].copy()
        i += 1
    _ = items.pop()
