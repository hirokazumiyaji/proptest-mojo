"""Generation phase and counterexample reporting for property tests.

Implements `docs/specs/runner.md` (ADR-0004, ADR-0006, ADR-0008).

`for_all` runs a `def(mut TestCase) raises -> None` property against
derived examples, shrinks the first failure, and raises the replayed
counterexample as an `Error`. Executions are classified by `tc.status`,
never by the exception message, so user messages cannot collide with
control flow.
"""

from std.io import Writer
from std.os import getenv
from std.time import perf_counter_ns

from proptest.choice import ChoiceSequence
from proptest.encoding import decode_sequence, encode_sequence
from proptest.prng import derive
from proptest.shrink.shrinker import Evaluation, shrink_with
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase

comptime DEFAULT_MAX_EXAMPLES = 100
comptime DEFAULT_MAX_SHRINK_EVALUATIONS = 5000
comptime SEED_ENV_VAR = "PROPTEST_SEED"
comptime MAX_EXAMPLES_ENV_VAR = "PROPTEST_MAX_EXAMPLES"


@fieldwise_init
struct Verbosity(Equatable, TrivialRegisterPassable, Writable):
    """How much of the generation loop `for_all` reports.

    `QUIET` and `NORMAL` stay silent on success; the distinction is
    reserved for future replay/database notices. `VERBOSE` prints every
    example as it runs, so a passing run still shows what was tried.
    """

    var value: UInt8

    comptime QUIET = Verbosity(0)
    comptime NORMAL = Verbosity(1)
    comptime VERBOSE = Verbosity(2)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def write_to(self, mut writer: Some[Writer]):
        if self == Self.QUIET:
            writer.write("QUIET")
        elif self == Self.NORMAL:
            writer.write("NORMAL")
        else:
            writer.write("VERBOSE")


struct Settings(Copyable, Movable, Writable):
    """Immutable run parameters for `for_all`.

    A `None` seed resolves to `PROPTEST_SEED` when set, else to a
    time-derived seed. A default `max_examples` resolves to
    `PROPTEST_MAX_EXAMPLES` when set, so CI can raise the count without
    code changes; any explicitly different value wins over the
    environment.
    """

    var max_examples: Int
    var seed: Optional[UInt64]
    var max_choices: Int
    var max_shrink_evaluations: Int
    var replay: Optional[String]
    var verbosity: Verbosity
    # Tracked separately from `max_examples`: an explicit
    # `Settings(max_examples=100)` must still beat `PROPTEST_MAX_EXAMPLES`,
    # so equality with the default cannot stand in for "supplied".
    var max_examples_set: Bool

    def __init__(
        out self,
        max_examples: Optional[Int] = None,
        seed: Optional[UInt64] = None,
        max_choices: Int = DEFAULT_MAX_CHOICES,
        max_shrink_evaluations: Int = DEFAULT_MAX_SHRINK_EVALUATIONS,
        replay: Optional[String] = None,
        verbosity: Verbosity = Verbosity.NORMAL,
    ):
        self.max_examples_set = max_examples is not None
        self.max_examples = (
            max_examples.value() if max_examples
            is not None else DEFAULT_MAX_EXAMPLES
        )
        self.seed = seed.copy()
        self.max_choices = max_choices
        self.max_shrink_evaluations = max_shrink_evaluations
        self.replay = replay.copy()
        self.verbosity = verbosity

    def effective_seed(self) raises -> UInt64:
        """Explicit seed, else `PROPTEST_SEED`, else time-derived."""
        if self.seed is not None:
            return self.seed.value()
        var from_env = getenv(SEED_ENV_VAR)
        if from_env.byte_length() > 0:
            # Parsed digit by digit: routing through signed `Int`
            # rejects valid seeds above `Int.MAX`, which is half the
            # domain `Settings.seed` and the reports accept.
            var ok = False
            var parsed = UInt64(0)
            ok, parsed = _parse_u64(from_env)
            if not ok:
                raise Error(
                    "PROPTEST_SEED is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
            return parsed
        return UInt64(abs(perf_counter_ns()))

    def effective_max_examples(self) raises -> Int:
        """Explicit count, else `PROPTEST_MAX_EXAMPLES` over the default."""
        if self.max_examples_set:
            if self.max_examples <= 0:
                raise Error("Settings: max_examples must be positive")
            return self.max_examples
        var from_env = getenv(MAX_EXAMPLES_ENV_VAR)
        if from_env.byte_length() > 0:
            var parsed = 0
            try:
                parsed = Int(from_env)
            except:
                raise Error(
                    "PROPTEST_MAX_EXAMPLES is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
            if parsed <= 0:
                raise Error(
                    "PROPTEST_MAX_EXAMPLES must be positive: '"
                    + String(from_env)
                    + "'"
                )
            return parsed
        return self.max_examples

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Settings(max_examples=", self.max_examples, ", seed=")
        if self.seed is None:
            writer.write("None")
        else:
            writer.write(self.seed.value())
        writer.write(
            ", max_choices=",
            self.max_choices,
            ", max_shrink_evaluations=",
            self.max_shrink_evaluations,
            ", verbosity=",
            self.verbosity,
        )
        if self.replay is not None:
            writer.write(', replay="', self.replay.value(), '"')
        writer.write(")")


comptime U64_MAX = UInt64(0xFFFFFFFFFFFFFFFF)


def _parse_u64(text: String) -> Tuple[Bool, UInt64]:
    """Parse a decimal string into a `UInt64`.

    Returns `(False, 0)` for a non-numeric or out-of-range value.
    Accumulating in `UInt64` keeps the whole `0..=UInt64.MAX` domain
    reachable; a signed `Int` accumulator would reject the upper half of
    it before the seed could be reported or replayed.
    """
    var digits = text.as_bytes()
    if len(digits) == 0:
        return (False, UInt64(0))
    var acc = UInt64(0)
    for b in digits:
        if b < 48 or b > 57:
            return (False, UInt64(0))
        var digit = UInt64(b - 48)
        if acc > (U64_MAX - digit) // UInt64(10):
            return (False, UInt64(0))
        acc = acc * UInt64(10) + digit
    return (True, acc)


def for_all[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings = Settings()) raises:
    """Run `prop` against generated examples, raising the counterexample.

    Attempt zero replays the empty prefix, so every draw sees the
    simplest choice; attempt `i >= 1` draws from `derive(seed, i)`. A
    run with no failure raises nothing. The first `INTERESTING`
    execution is shrunk with `shrink_with`, replayed to collect draw
    records, and reported as an `Error` carrying the records, notes,
    the failure message, the seed, and the replay string. When
    `settings.replay` is set, only those choices run once: a reproduced
    failure is reported as-is with no generation or shrinking, while a
    run that no longer fails raises instead of searching for a new
    counterexample. Executions rejected by `assume` (or an unsatisfiable
    `filter`, which rejects the same way) are skipped; too many
    rejections or overruns fail the run with a health-check `Error`
    naming the rejection rate. `VERBOSE` settings print every example
    as it runs.
    """
    if settings.replay is not None:
        _replay_only(prop, settings, String(settings.replay.value()))
        return
    var seed = settings.effective_seed()
    var max_examples = settings.effective_max_examples()
    var verbose = settings.verbosity == Verbosity.VERBOSE

    def evaluate(
        candidate: ChoiceSequence,
    ) raises {imm prop, imm settings} -> Evaluation:
        var tc = TestCase.replaying(candidate.copy(), settings.max_choices)
        var raised = False
        try:
            prop(tc)
        except:
            raised = True
        return Evaluation(
            raised and tc.status == Status.RUNNING, tc.choices.copy()
        )

    var valid_count = 0
    var examples_run = 0
    var invalid_count = 0
    var overrun_count = 0
    var attempt = UInt64(0)
    while valid_count < max_examples:
        var tc = _fresh_test_case(settings.max_choices, seed, attempt)
        var raised = False
        var message = String("")
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        examples_run += 1
        attempt += 1
        if tc.status == Status.RUNNING:
            tc.status = Status.INTERESTING if raised else Status.VALID
        if verbose:
            print(
                _format_example_line(
                    examples_run,
                    tc.status,
                    tc.draw_labels.copy(),
                    tc.draw_values.copy(),
                )
            )
        if tc.status == Status.INVALID:
            invalid_count += 1
            if invalid_count > 10 * max_examples:
                raise Error(
                    _too_many_rejects_message(
                        examples_run, invalid_count, valid_count
                    )
                )
            continue
        if tc.status == Status.OVERRUN:
            overrun_count += 1
            if overrun_count * 5 > examples_run:
                raise Error(
                    _too_many_overruns_message(
                        examples_run,
                        overrun_count,
                        valid_count,
                        settings.max_choices,
                    )
                )
            continue
        # Rechecked after a VALID attempt too: overruns that happened
        # while `examples_run < 10` would otherwise escape the ratio
        # check entirely when the last required valid example completes
        # the loop, silently passing a run that mostly overran.
        if (
            examples_run >= 10
            and overrun_count > 0
            and overrun_count * 5 > examples_run
        ):
            raise Error(
                _too_many_overruns_message(
                    examples_run,
                    overrun_count,
                    valid_count,
                    settings.max_choices,
                )
            )
        if not raised:
            valid_count += 1
            continue
        var shrink_result = shrink_with(
            evaluate, tc.choices.copy(), settings.max_shrink_evaluations
        )
        var report_tc = TestCase.replaying(
            shrink_result.best.copy(), settings.max_choices
        )
        try:
            prop(report_tc)
        except e:
            message = String(e)
        raise Error(
            _format_report(
                examples_run,
                shrink_result.evaluations,
                report_tc.draw_labels.copy(),
                report_tc.draw_values.copy(),
                report_tc.notes.copy(),
                message,
                Optional[UInt64](seed),
                shrink_result.hit_budget,
                encode_sequence(report_tc.choices),
            )
        )


def _replay_only[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings, replay_token: String) raises:
    """Run recorded choices once, reporting a reproduced failure as-is.

    Generation and shrinking are skipped. A run that no longer fails
    raises instead of searching for a new counterexample.
    """
    var prefix: ChoiceSequence
    try:
        prefix = decode_sequence(replay_token)
    except e:
        raise Error("invalid replay string: " + String(e))
    var tc = TestCase.replaying(prefix^, settings.max_choices)
    var raised = False
    var message = String("")
    try:
        prop(tc)
    except e:
        raised = True
        message = String(e)
    if not raised or tc.status != Status.RUNNING:
        raise Error(
            "replay did not reproduce a failure (status="
            + String(tc.status)
            + ")"
        )
    raise Error(
        _format_report(
            1,
            0,
            tc.draw_labels.copy(),
            tc.draw_values.copy(),
            tc.notes.copy(),
            message,
            None,
            False,
            replay_token,
        )
    )


def _fresh_test_case(
    max_choices: Int, seed: UInt64, attempt: UInt64
) -> TestCase:
    """Attempt zero replays the empty prefix (all-zero choices)."""
    if attempt == UInt64(0):
        return TestCase.replaying(ChoiceSequence(), max_choices)
    return TestCase.generating(derive(seed, attempt), max_choices)


def _draw_label(labels: List[String], i: Int) -> String:
    """`labels[i]` with the `draw #i+1` fallback for an empty entry."""
    var label = String(labels[i])
    if label.byte_length() == 0:
        label = "draw #" + String(i + 1)
    return label^


def _format_example_line(
    index: Int,
    status: Status,
    labels: List[String],
    values: List[String],
) -> String:
    """Render one generation-loop execution for `VERBOSE` output."""
    var out = String("example ") + String(index) + ": " + String(status)
    if len(labels) > 0:
        out += " ("
        for i in range(len(labels)):
            if i > 0:
                out += ", "
            out += _draw_label(labels, i)
            out += " = "
            out += values[i]
        out += ")"
    return out^


def _health_check_message(
    examples_run: Int,
    bad_count: Int,
    valid_count: Int,
    reason: String,
    rate_label: String,
    strict_diagnosis: String,
) -> String:
    """Shared skeleton for health-check failure messages.

    With no valid execution at all, the diagnosis is the inability to
    generate a satisfying input rather than mere strictness.
    """
    var rate = 0
    if examples_run > 0:
        rate = bad_count * 100 // examples_run
    var out = String("gave up after ") + String(examples_run) + " examples"
    if valid_count == 0:
        out += " without a single valid execution"
    out += " (" + String(bad_count) + " " + reason + ", "
    out += String(rate) + "% " + rate_label + " rate)"
    if valid_count == 0:
        out += ": unable to generate input satisfying the condition"
    else:
        out += ": " + strict_diagnosis
    return out^


def _too_many_rejects_message(
    examples_run: Int, invalid_count: Int, valid_count: Int
) -> String:
    """Health-check failure naming the rejection rate."""
    return _health_check_message(
        examples_run,
        invalid_count,
        valid_count,
        "rejected by assume/filter",
        "rejection",
        "assume/filter condition too strict",
    )


def _too_many_overruns_message(
    examples_run: Int, overrun_count: Int, valid_count: Int, max_choices: Int
) -> String:
    """Health-check failure for runs exceeding the choice budget."""
    return _health_check_message(
        examples_run,
        overrun_count,
        valid_count,
        "overran max_choices=" + String(max_choices),
        "overrun",
        "generated data too large",
    )


def _format_report(
    examples_run: Int,
    shrink_evaluations: Int,
    labels: List[String],
    values: List[String],
    notes: List[String],
    message: String,
    seed: Optional[UInt64],
    hit_budget: Bool,
    replay_token: String,
) -> String:
    """Render the replayed counterexample as the raised `Error` text."""
    var out = String("Falsifying example (after ")
    out += String(examples_run)
    out += " examples, "
    out += String(shrink_evaluations)
    out += " shrink evaluations):\n"
    for i in range(len(labels)):
        out += "  "
        out += _draw_label(labels, i)
        out += " = "
        out += values[i]
        out += "\n"
    for i in range(len(notes)):
        out += "  note: "
        out += notes[i]
        out += "\n"
    out += "Error: "
    out += message
    if seed is not None:
        out += "\nSeed: "
        out += String(seed.value())
    if hit_budget:
        out += "\nShrink budget exhausted; counterexample may not be minimal"
    out += '\nReproduce with: Settings(replay="'
    out += replay_token
    out += '")'
    return out^
