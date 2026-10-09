"""Tuple and optional strategies with independent shrinking per element.

Implements the `tuples` / `optionals` rows of `docs/specs/strategies.md`
(ADR-0003, ADR-0008).

All strategies are immutable values deterministic in the recorded choices
alone. Smaller choices yield simpler values; all-zero choices draw the
simplest value (`(simplest, ...)` for tuples, `None` for optionals).

Each element is drawn through `TestCase.draw`, so every element gets its
own span and report entry (the locality convention). The presence flag of
`optionals` is a single boolean choice drawn before the inner value, so
shrinking it to 0 yields `None` while inner choices shrink independently.

The standard `Tuple` and `Optional` types already satisfy
`Copyable & Writable & Deinitable`, so they are used directly as
`Strategy.Value`. Their `Writable` renderings (`(0, 1)`, `None`) are the
counterexample display.
"""

from proptest.strategy import Strategy, kind_label
from proptest.testcase import TestCase


@fieldwise_init
struct Tuple2[A: Strategy, B: Strategy](Strategy):
    """Pair strategy drawing each side through its own span."""

    comptime Value = Tuple[Self.A.Value, Self.B.Value]
    var first: Self.A
    var second: Self.B

    def span_label(self) -> UInt64:
        return kind_label("tuple2")

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var a = tc.draw(self.first)
        var b = tc.draw(self.second)
        return (a^, b^)


@fieldwise_init
struct Tuple3[A: Strategy, B: Strategy, C: Strategy](Strategy):
    """Triple strategy drawing each element through its own span."""

    comptime Value = Tuple[Self.A.Value, Self.B.Value, Self.C.Value]
    var first: Self.A
    var second: Self.B
    var third: Self.C

    def span_label(self) -> UInt64:
        return kind_label("tuple3")

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        var a = tc.draw(self.first)
        var b = tc.draw(self.second)
        var c = tc.draw(self.third)
        return (a^, b^, c^)


@fieldwise_init
struct OptionalOf[S: Strategy](Strategy):
    """Optional strategy with `None` as the simplest value.

    A leading boolean choice selects presence: 0 draws `None` without
    consuming further choices, 1 draws the inner strategy. All-zero
    choices therefore draw `None`.
    """

    comptime Value = Optional[Self.S.Value]
    var inner: Self.S

    def span_label(self) -> UInt64:
        return kind_label("optional_of")

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        if not tc.draw_boolean():
            return None
        return Optional[Self.S.Value](tc.draw(self.inner))


def tuples[
    A: Strategy, B: Strategy
](var first: A, var second: B) -> Tuple2[A, B]:
    """Strategy drawing a pair, each side shrinking independently.

    All-zero choices draw `(simplest of `first`, simplest of `second`)`.
    """
    return Tuple2[A, B](first^, second^)


def tuples[
    A: Strategy, B: Strategy, C: Strategy
](var first: A, var second: B, var third: C) -> Tuple3[A, B, C]:
    """Strategy drawing a triple, each element shrinking independently.

    All-zero choices draw the triple of each side's simplest value.
    """
    return Tuple3[A, B, C](first^, second^, third^)


def optionals[S: Strategy](var inner: S) -> OptionalOf[S]:
    """Strategy drawing `Optional[S.Value]` with `None` simplest.

    Choice 0 on the leading boolean draws `None`; larger choices draw
    `Some` with the inner value shrinking independently.
    """
    return OptionalOf[S](inner^)
