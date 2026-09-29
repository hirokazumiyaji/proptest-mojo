"""Choice sequence primitives for internal shrinking.

Implements `ChoiceKind`, `ChoiceNode`, `ChoiceSequence` (shortlex order),
and `Span` per `docs/specs/choice-sequence.md` (ADR-0002).

All choices are normalized to non-negative integers in `0..=max_value`
where 0 is simplest. Shrinking moves strictly down in shortlex order,
which is well-founded so shrinking always terminates.
"""

from std.io import Writer


@fieldwise_init
struct ChoiceKind(Equatable, TrivialRegisterPassable, Writable):
    """Kind of a single choice, used to pick kind-specific shrink moves."""

    var value: UInt8

    comptime INTEGER = ChoiceKind(0)
    comptime BOOLEAN = ChoiceKind(1)
    comptime FLOAT = ChoiceKind(2)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Self) -> Bool:
        return self.value != other.value

    def write_to(self, mut writer: Some[Writer]):
        if self == Self.INTEGER:
            writer.write("INTEGER")
        elif self == Self.BOOLEAN:
            writer.write("BOOLEAN")
        else:
            writer.write("FLOAT")


@fieldwise_init
struct ChoiceNode(Copyable, Equatable, Movable, Writable):
    """One recorded choice: normalized value plus its bound.

    `forced` choices are fixed by the generator and must be left
    untouched by all shrink passes.
    """

    var kind: ChoiceKind
    var value: UInt64
    var max_value: UInt64
    var forced: Bool

    def __eq__(self, other: Self) -> Bool:
        return (
            self.kind == other.kind
            and self.value == other.value
            and self.max_value == other.max_value
            and self.forced == other.forced
        )

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            self.kind,
            "(",
            self.value,
            "/",
            self.max_value,
            ", forced=",
            self.forced,
            ")",
        )


@fieldwise_init
struct Span(Copyable, Equatable, Movable, Writable):
    """Interval over a choice sequence marking one structural unit."""

    var start: Int
    var end: Int
    var label: UInt64
    var depth: Int
    var discarded: Bool

    def __eq__(self, other: Self) -> Bool:
        return (
            self.start == other.start
            and self.end == other.end
            and self.label == other.label
            and self.depth == other.depth
            and self.discarded == other.discarded
        )

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def length(self) -> Int:
        """Number of choices covered (`end - start`)."""
        return self.end - self.start

    def is_empty(self) -> Bool:
        """Whether the span covers no choices."""
        return self.end <= self.start

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "Span(",
            self.start,
            "..",
            self.end,
            ", label=",
            self.label,
            ", depth=",
            self.depth,
            ", discarded=",
            self.discarded,
            ")",
        )


@fieldwise_init
struct ChoiceSequence(Copyable, Equatable, Movable, Sized, Writable):
    """Ordered recorded choices. Treated as immutable after construction.

    Local mutation via `append` is allowed while building a sequence;
    all transforms below return new values.
    """

    var nodes: List[ChoiceNode]

    def __init__(out self):
        self.nodes = List[ChoiceNode]()

    def __len__(self) -> Int:
        return len(self.nodes)

    def __getitem__(self, index: Int) -> ChoiceNode:
        return self.nodes[index].copy()

    def __eq__(self, other: Self) -> Bool:
        if len(self.nodes) != len(other.nodes):
            return False
        for i in range(len(self.nodes)):
            if self.nodes[i] != other.nodes[i]:
                return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __lt__(self, other: Self) -> Bool:
        return shortlex_compare(self, other) < 0

    def __le__(self, other: Self) -> Bool:
        return shortlex_compare(self, other) <= 0

    def __gt__(self, other: Self) -> Bool:
        return shortlex_compare(self, other) > 0

    def __ge__(self, other: Self) -> Bool:
        return shortlex_compare(self, other) >= 0

    def append(mut self, node: ChoiceNode):
        """Push one recorded choice while building a sequence."""
        self.nodes.append(node.copy())

    def values(self) -> List[UInt64]:
        """Value column only, used as the cache key and for comparisons."""
        var out = List[UInt64]()
        for i in range(len(self.nodes)):
            out.append(self.nodes[i].value)
        return out^

    def truncated(self, length: Int) -> Self:
        """First `length` choices (clamped to the sequence length)."""
        var n = length
        if n < 0:
            n = 0
        if n > len(self.nodes):
            n = len(self.nodes)
        var out = List[ChoiceNode]()
        for i in range(n):
            out.append(self.nodes[i].copy())
        return Self(out^)

    def deleted(self, start: Int, end: Int) -> Self:
        """Copy without the half-open range `[start, end)` (clamped)."""
        var lo = _clamp_index(start, len(self.nodes))
        var hi = _clamp_index(end, len(self.nodes))
        var out = List[ChoiceNode]()
        for i in range(len(self.nodes)):
            if i < lo or i >= hi:
                out.append(self.nodes[i].copy())
        return Self(out^)

    def zeroed(self, start: Int, end: Int) -> Self:
        """Copy with values in `[start, end)` set to 0.

        `forced` nodes keep their value.
        """
        var lo = _clamp_index(start, len(self.nodes))
        var hi = _clamp_index(end, len(self.nodes))
        var out = List[ChoiceNode]()
        for i in range(len(self.nodes)):
            var node = self.nodes[i].copy()
            if lo <= i and i < hi and not node.forced:
                node.value = UInt64(0)
            out.append(node^)
        return Self(out^)

    def with_value_at(self, index: Int, value: UInt64) -> Self:
        """Copy with one value replaced (out-of-range index is a no-op)."""
        var out = List[ChoiceNode]()
        for i in range(len(self.nodes)):
            var node = self.nodes[i].copy()
            if i == index and not node.forced:
                node.value = value
            out.append(node^)
        return Self(out^)

    def replaced_range(
        self, start: Int, end: Int, replacement: List[ChoiceNode]
    ) -> Self:
        """Copy with `[start, end)` spliced out for `replacement`."""
        var lo = _clamp_index(start, len(self.nodes))
        var hi = _clamp_index(end, len(self.nodes))
        var out = List[ChoiceNode]()
        for i in range(lo):
            out.append(self.nodes[i].copy())
        for i in range(len(replacement)):
            out.append(replacement[i].copy())
        for i in range(hi, len(self.nodes)):
            out.append(self.nodes[i].copy())
        return Self(out^)

    def write_to(self, mut writer: Some[Writer]):
        writer.write("[")
        for i in range(len(self.nodes)):
            if i > 0:
                writer.write(", ")
            writer.write(self.nodes[i])
        writer.write("]")


def _clamp_index(index: Int, length: Int) -> Int:
    if index < 0:
        return 0
    if index > length:
        return length
    return index


def shortlex_compare(a: ChoiceSequence, b: ChoiceSequence) -> Int:
    """Compare by length, then lexicographically by value column.

    Returns -1 / 0 / 1. Only values participate so two sequences with
    identical values but different bounds compare equal here, while
    `==` still distinguishes them.
    """
    if len(a.nodes) != len(b.nodes):
        if len(a.nodes) < len(b.nodes):
            return -1
        return 1
    for i in range(len(a.nodes)):
        var av = a.nodes[i].value
        var bv = b.nodes[i].value
        if av != bv:
            if av < bv:
                return -1
            return 1
    return 0


def is_shortlex_smaller(a: ChoiceSequence, b: ChoiceSequence) -> Bool:
    """Whether `a` is strictly simpler than `b` in shortlex order."""
    return shortlex_compare(a, b) < 0
