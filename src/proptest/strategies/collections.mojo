"""Variable-length list strategies with continue-flag encoding.

Implements the collection rows of `docs/specs/strategies.md`
(ADR-0003, ADR-0005, ADR-0008).

Each element draws a continue flag inside its own span, so span deletion
removes one element. Bounds use `forced_integer`, keeping them out of
shrinking. Smaller choices yield shorter lists of simpler elements;
all-zero choices draw `min_size` minimal elements.
"""

from proptest.strategy import Strategy
from proptest.testcase import TestCase

comptime _LIST_ELEMENT_LABEL = UInt64(0x6C697374456C656D)


def _default_average_size(min_size: Int, max_size: Int) -> Float64:
    # min(max(min_size * 2, min_size + 5), (min_size + max_size) / 2).
    var lo = min_size * 2
    var shifted = min_size + 5
    if shifted > lo:
        lo = shifted
    var mid = Float64(min_size + max_size) / 2.0
    var lof = Float64(lo)
    if lof < mid:
        return lof
    return mid


@fieldwise_init
struct ListOf[E: Strategy](Strategy):
    """Lists of `elements` with length in `[min_size, max_size]`."""

    comptime Value = List[Self.E.Value]
    var elements: Self.E
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def draw(self, mut tc: TestCase) raises -> List[Self.E.Value]:
        var out = List[Self.E.Value]()
        var p_continue: Float64 = 0.0
        if self.average_size > 0.0:
            p_continue = self.average_size / (1.0 + self.average_size)
        while True:
            tc.start_span(_LIST_ELEMENT_LABEL)
            try:
                var cont: Bool
                if len(out) >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif len(out) < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
                if not cont:
                    tc.stop_span(discard=True)
                    break
                var element = self.elements.draw(tc)
                tc.stop_span()
                out.append(element^)
            except e:
                tc.stop_span()
                raise e
        return out^


def lists[
    E: Strategy
](
    var elements: E,
    min_size: Int = 0,
    max_size: Int = 32,
    average_size: Float64 = -1.0,
) raises -> ListOf[E]:
    """Strategy drawing `List[E.Value]` with length in `[min_size, max_size]`.

    Each element draws a continue flag inside its own span; the flag is
    forced to 1 below `min_size` and to 0 at `max_size`. The continue
    probability is `average_size / (1 + average_size)`; a negative
    `average_size` selects the spec default
    `min(max(min_size * 2, min_size + 5), (min_size + max_size) / 2)`.
    All-zero choices draw `min_size` minimal elements. Raises when the
    bounds are empty.
    """
    if min_size < 0:
        raise Error("lists: min_size must be >= 0")
    if max_size < min_size:
        raise Error("lists: max_size must be >= min_size")
    var avg = average_size
    if avg < 0.0:
        avg = _default_average_size(min_size, max_size)
    if avg < 0.0:
        raise Error("lists: average_size must be >= 0")
    return ListOf[E](elements^, min_size, max_size, avg)
