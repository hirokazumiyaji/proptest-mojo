"""Choice strategies: sampling values and choosing between strategies.

Implements the `sampled_from` and `one_of` rows of `docs/specs/strategies.md`
(ADR-0003, ADR-0008, ADR-0010).

All strategies are immutable values deterministic in the recorded choices
alone. The index choice is drawn first as an integer in `0..<n` where 0 is
simplest, so shrinking drives the choice to the front.
"""

from proptest.strategy import Strategy
from proptest.testcase import TestCase


@fieldwise_init
struct SampledFrom[T: Copyable & Writable & Deinitable](Strategy):
    """Strategy drawing one element of `values`, shrinking to the front."""

    comptime Value = Self.T
    var values: List[Self.T]

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var index = tc.draw_integer(UInt64(len(self.values) - 1))
        return self.values[Int(index)].copy()


def sampled_from[
    T: Copyable & Writable & Deinitable
](var values: List[T]) raises -> SampledFrom[T]:
    """Strategy drawing one of `values`.

    All-zero choices draw the front element. Raises when `values` is empty.
    """
    if len(values) == 0:
        raise Error("sampled_from: need at least one value")
    return SampledFrom[T](values^)


@fieldwise_init
struct OneOf[S: Strategy](Strategy):
    """Strategy delegating to one of `strategies`, shrinking to the front."""

    comptime Value = Self.S.Value
    var strategies: List[Self.S]

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var index = tc.draw_integer(UInt64(len(self.strategies) - 1))
        return self.strategies[Int(index)].draw(tc)


def one_of[S: Strategy](var strategies: List[S]) raises -> OneOf[S]:
    """Strategy drawing from one of `strategies` (all the same type).

    All-zero choices draw from the front strategy. Raises when `strategies`
    is empty. Strategies of different types with the same `Value` combine
    with `one_of2` instead.
    """
    if len(strategies) == 0:
        raise Error("one_of: need at least one strategy")
    return OneOf[S](strategies^)


@fieldwise_init
struct OneOf2[A: Strategy, B: Strategy](Strategy) where A.Value == B.Value:
    """Strategy delegating to one of two different strategy types.

    The trailing `where` clause proves `A.Value` and `B.Value` identical at
    instantiation, and `rebind` carries that proof through the branch. A
    mismatched pair fails to compile instead of silently misbehaving.
    All-zero choices draw from `a`.
    """

    comptime Value = Self.A.Value
    var a: Self.A
    var b: Self.B

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var index = tc.draw_integer(UInt64(1))
        if index == 0:
            return self.a.draw(tc)
        var other = self.b.draw(tc)
        return rebind[Self.Value](other^).copy()


def one_of2[
    A: Strategy, B: Strategy
](var a: A, var b: B) -> OneOf2[A, B] where A.Value == B.Value:
    """Strategy drawing from `a` (choice 0) or `b` (choice 1).

    Only compiles when both strategies share the same `Value` type. Nest
    for more than two branches, or map branches to one strategy type and
    use `one_of`.
    """
    return OneOf2[A, B](a^, b^)
