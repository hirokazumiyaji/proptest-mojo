"""Primitive strategies: integers, booleans, and constant values.

Implements the M1 rows of `docs/specs/strategies.md` (ADR-0003, ADR-0008).

All strategies are immutable values deterministic in the recorded choices
alone. Smaller choices yield simpler values; all-zero choices draw the
simplest value of each strategy.
"""

from proptest.strategy import Strategy
from proptest.testcase import TestCase

comptime _SIGN_BIT = UInt64(0x8000000000000000)


def _biased(value: Int) -> UInt64:
    # Sign-flip bias maps Int order onto UInt64 order, so range widths and
    # offsets below are exact even for ranges spanning most of Int.
    return UInt64(value) ^ _SIGN_BIT


def _unbiased(biased: UInt64) -> Int:
    return Int(biased ^ _SIGN_BIT)


def decode_integer_choice(choice: UInt64, minimum: Int, maximum: Int) -> Int:
    """Map a non-negative choice onto `[minimum, maximum]`.

    The target (the value in range nearest 0) is choice 0; larger choices
    alternate outward as `t+1, t-1, t+2, t-2, ...`, skipping the side that
    leaves the range. Distances from the target are therefore
    non-decreasing in `choice`, so shrinking only needs to lower choices.
    Choices past `maximum - minimum` are clamped so the result always
    stays in range. Precondition: `minimum <= maximum`.
    """
    var minimum_biased = _biased(minimum)
    var maximum_biased = _biased(maximum)
    var target = _biased(0)
    if target < minimum_biased:
        target = minimum_biased
    if target > maximum_biased:
        target = maximum_biased
    if choice == 0:
        return _unbiased(target)
    var width = maximum_biased - minimum_biased
    var clamped = choice
    if clamped > width:
        clamped = width
    var up = maximum_biased - target
    var down = target - minimum_biased
    var paired = up
    if down < paired:
        paired = down
    if clamped <= 2 * paired:
        var step = (clamped + 1) // 2
        if clamped % 2 == 1:
            return _unbiased(target + step)
        return _unbiased(target - step)
    var rest = clamped - 2 * paired
    if up > down:
        return _unbiased(target + paired + rest)
    return _unbiased(target - paired - rest)


@fieldwise_init
struct Integers(Strategy):
    """Integers in `[minimum, maximum]` shrinking toward the value nearest 0."""

    comptime Value = Int
    var minimum: Int
    var maximum: Int

    def draw(self, mut tc: TestCase) raises -> Int:
        var width = UInt64(self.maximum) - UInt64(self.minimum)
        var choice = tc.draw_integer(width)
        return decode_integer_choice(choice, self.minimum, self.maximum)


def integers(minimum: Int, maximum: Int) raises -> Integers:
    """Strategy drawing every `Int` in `[minimum, maximum]`.

    All-zero choices draw the value in range nearest 0. Raises when the
    range is empty.
    """
    if maximum < minimum:
        raise Error("integers: maximum must be >= minimum")
    return Integers(minimum, maximum)


def _biased_of[dtype: DType](value: Scalar[dtype]) -> UInt64:
    if dtype.is_signed():
        return UInt64(Int64(value)) ^ _SIGN_BIT
    return UInt64(value)


def _unbiased_of[dtype: DType](biased: UInt64) -> Scalar[dtype]:
    if dtype.is_signed():
        return Scalar[dtype](Int64(biased ^ _SIGN_BIT))
    return Scalar[dtype](biased)


def decode_integers_of_choice[
    dtype: DType
](choice: UInt64, minimum: Scalar[dtype], maximum: Scalar[dtype]) -> Scalar[
    dtype
]:
    """Map a non-negative choice onto `[minimum, maximum]` for `dtype`.

    Same outward-alternating encoding as `decode_integer_choice`: choice 0
    draws the value in range nearest 0, larger choices alternate outward as
    `t+1, t-1, t+2, t-2, ...`, skipping the side that leaves the range. All
    arithmetic stays in `UInt64`, so the full `Int64`/`UInt64` ranges decode
    without overflow. Choices past the biased distance between the bounds
    are clamped so the result always stays in range. Precondition:
    `minimum <= maximum`.
    """
    comptime assert (
        dtype.is_integral()
    ), "integers_of requires an integral dtype"
    var minimum_biased = _biased_of[dtype](minimum)
    var maximum_biased = _biased_of[dtype](maximum)
    var target = _biased_of[dtype](Scalar[dtype](0))
    if target < minimum_biased:
        target = minimum_biased
    if target > maximum_biased:
        target = maximum_biased
    if choice == 0:
        return _unbiased_of[dtype](target)
    var width = maximum_biased - minimum_biased
    var clamped = choice
    if clamped > width:
        clamped = width
    var up = maximum_biased - target
    var down = target - minimum_biased
    var paired = up
    if down < paired:
        paired = down
    if clamped <= 2 * paired:
        var step = (clamped + 1) // 2
        if clamped % 2 == 1:
            return _unbiased_of[dtype](target + step)
        return _unbiased_of[dtype](target - step)
    var rest = clamped - 2 * paired
    if up > down:
        return _unbiased_of[dtype](target + paired + rest)
    return _unbiased_of[dtype](target - paired - rest)


@fieldwise_init
struct IntegersOf[dtype: DType](Strategy):
    """Integers of `dtype` in `[minimum, maximum]` shrinking toward 0."""

    comptime Value = Scalar[Self.dtype]
    var minimum: Scalar[Self.dtype]
    var maximum: Scalar[Self.dtype]

    def draw(self, mut tc: TestCase) raises -> Scalar[Self.dtype]:
        var width = _biased_of[Self.dtype](self.maximum) - _biased_of[
            Self.dtype
        ](self.minimum)
        var choice = tc.draw_integer(width)
        return decode_integers_of_choice[Self.dtype](
            choice, self.minimum, self.maximum
        )


def integers_of[
    dtype: DType
](minimum: Scalar[dtype], maximum: Scalar[dtype]) raises -> IntegersOf[dtype]:
    """Strategy drawing every `Scalar[dtype]` in `[minimum, maximum]`.

    All-zero choices draw the value in range nearest 0. Raises when the
    range is empty. `dtype` must be an integral type (`Int8` to `UInt64`).
    """
    comptime assert (
        dtype.is_integral()
    ), "integers_of requires an integral dtype"
    if maximum < minimum:
        raise Error("integers_of: maximum must be >= minimum")
    return IntegersOf[dtype](minimum, maximum)


def integers_of[dtype: DType]() -> IntegersOf[dtype]:
    """Strategy drawing every `Scalar[dtype]` in the full range of `dtype`.

    All-zero choices draw 0. `dtype` must be an integral type (`Int8` to
    `UInt64`).
    """
    comptime assert (
        dtype.is_integral()
    ), "integers_of requires an integral dtype"
    return IntegersOf[dtype](Scalar[dtype].MIN, Scalar[dtype].MAX)


@fieldwise_init
struct Booleans(Strategy):
    """Coin flips shrinking toward `False`."""

    comptime Value = Bool

    def draw(self, mut tc: TestCase) raises -> Bool:
        return tc.draw_boolean()


def booleans() -> Booleans:
    """Strategy drawing `Bool`, with all-zero choices drawing `False`."""
    return Booleans()


@fieldwise_init
struct Just[T: Copyable & Writable & Deinitable](Strategy):
    """Constant strategy returning a copy of `value` without consuming choices.
    """

    comptime Value = Self.T
    var value: Self.T

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        return self.value.copy()


def just[T: Copyable & Writable & Deinitable](var value: T) -> Just[T]:
    """Strategy always drawing `value`, consuming no choices."""
    return Just[T](value^)
