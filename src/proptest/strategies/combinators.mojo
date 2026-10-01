"""Derived strategies: map, filter, and flat_map.

Implements the combinators section of `docs/specs/strategies.md`
(ADR-0003, ADR-0005, ADR-0008).

All combinators take capture-free (thin) functions as comptime
parameters, so generation stays inlineable and deterministic in the
recorded choices alone. Capturing transforms belong in composite
Strategy structs holding their parameters as fields.
"""

from proptest.strategy import Strategy
from proptest.testcase import TestCase

comptime MAX_FILTER_ATTEMPTS = 3
comptime FILTER_SPAN_LABEL = UInt64(0x46494C544552)


@fieldwise_init
struct Map[
    S: Strategy, U: Copyable & Writable & Deinitable, f: def(S.Value) thin -> U
](Strategy):
    """Transformed draws shrinking through the base strategy."""

    comptime Value = Self.U
    var base: Self.S

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var value = self.base.draw(tc)
        return Self.f(value^)


def map[
    S: Strategy,
    U: Copyable & Writable & Deinitable,
    //,
    f: def(S.Value) thin -> U,
](var s: S) -> Map[S, U, f]:
    """Strategy applying the pure function `f` to each draw of `s`."""
    return Map[S, U, f](s^)


@fieldwise_init
struct Filter[S: Strategy, p: def(S.Value) thin -> Bool](Strategy):
    """Draws of `base` satisfying `p`, retrying rejected attempts."""

    comptime Value = Self.S.Value
    var base: Self.S

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        for _ in range(MAX_FILTER_ATTEMPTS):
            tc.start_span(FILTER_SPAN_LABEL)
            try:
                var value = self.base.draw(tc)
                if Self.p(value.copy()):
                    tc.stop_span()
                    return value^
            except e:
                tc.stop_span(discard=True)
                raise e
            tc.stop_span(discard=True)
        tc.assume(False)
        raise Error("unreachable")


def filter[
    S: Strategy, //, p: def(S.Value) thin -> Bool
](var s: S,) -> Filter[S, p]:
    """Strategy drawing `s` until `p` holds, then `INVALID` after retries.

    Each rejected attempt is recorded as a `discarded` span. After
    `MAX_FILTER_ATTEMPTS` rejections the draw aborts as `INVALID`,
    so the runner skips the example instead of reporting it.
    """
    return Filter[S, p](s^)


@fieldwise_init
struct FlatMap[S: Strategy, T: Strategy, f: def(S.Value) thin -> T](Strategy):
    """Outer draw selecting the inner strategy, then an inner draw."""

    comptime Value = Self.T.Value
    var base: Self.S

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var outer = self.base.draw(tc)
        var inner = Self.f(outer^)
        return inner.draw(tc)


def flat_map[
    S: Strategy, T: Strategy, //, f: def(S.Value) thin -> T
](var s: S,) -> FlatMap[S, T, f]:
    """Strategy drawing `s`, building the inner strategy with `f`, drawing it.

    The inner strategy type is fixed at compile time; only its value
    parameters may depend on the outer draw.
    """
    return FlatMap[S, T, f](s^)
