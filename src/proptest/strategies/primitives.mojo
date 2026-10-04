"""Primitive strategies: integers, booleans, and constant values.

Implements the M1 rows of `docs/specs/strategies.md` (ADR-0003, ADR-0008).

All strategies are immutable values deterministic in the recorded choices
alone. Smaller choices yield simpler values; all-zero choices draw the
simplest value of each strategy.
"""

from proptest.strategy import Strategy, kind_label
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


struct Integers(Strategy):
    """Integers in `[minimum, maximum]` shrinking toward the value nearest 0."""

    comptime Value = Int
    var minimum: Int
    var maximum: Int

    def __init__(out self, minimum: Int, maximum: Int) raises:
        if maximum < minimum:
            raise Error("integers: maximum must be >= minimum")
        self.minimum = minimum
        self.maximum = maximum

    def span_label(self) -> UInt64:
        return kind_label("integers")

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


@fieldwise_init
struct Booleans(Strategy):
    """Coin flips shrinking toward `False`."""

    comptime Value = Bool

    def span_label(self) -> UInt64:
        return kind_label("booleans")

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

    def span_label(self) -> UInt64:
        return kind_label("just")

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        return self.value.copy()


def just[T: Copyable & Writable & Deinitable](var value: T) -> Just[T]:
    """Strategy always drawing `value`, consuming no choices."""
    return Just[T](value^)
