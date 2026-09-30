"""Float strategies with lexicographic (dictionary-order) encoding.

Implements the `floats` row of `docs/specs/strategies.md` (M2) and the
`ChoiceKind.FLOAT` choice of `docs/specs/choice-sequence.md`.

Like Hypothesis, a float is drawn from two choices: a boolean sign and a
64-bit magnitude code from `TestCase.draw_float_bits`. The magnitude code
is the bit pattern of a non-negative `Float64`, so numeric order matches
code order: `0.0` is code 0, larger magnitudes have larger codes, `+inf`
is `0x7FF0000000000000`, and NaN patterns sort last (canonicalized to
`0x7FF8000000000000`). Small non-negative integers and simple fractions
therefore appear in increasing numeric order (`0.5 < 1.0 < 2.0`), and
shrinking only needs to lower choices. All-zero choices draw `+0.0`.
"""

from std.math import inf, isinf, isnan
from std.memory import bitcast

from proptest.strategy import Strategy
from proptest.testcase import TestCase

comptime SIGN_MASK = UInt64(0x8000000000000000)
comptime MAG_MASK = UInt64(0x7FFFFFFFFFFFFFFF)
comptime INF_BITS = UInt64(0x7FF0000000000000)
comptime CANON_NAN_BITS = UInt64(0x7FF8000000000000)
comptime MAX_FINITE_BITS = UInt64(0x7FEFFFFFFFFFFFFF)


def _float_to_bits(value: Float64) -> UInt64:
    return bitcast[DType.uint64](value)


def _bits_to_float(bits: UInt64) -> Float64:
    return bitcast[DType.float64](bits)


def float_to_lex(value: Float64) -> UInt64:
    """Magnitude code of `value`: absolute bit pattern, NaN canonicalized.

    The sign is dropped (`-0.0` maps to 0, negatives map to their absolute
    value) because the strategy draws the sign as a separate boolean
    choice. NaN maps to `CANON_NAN_BITS` regardless of payload or sign.
    """
    if isnan(value):
        return CANON_NAN_BITS
    return _float_to_bits(value) & MAG_MASK


def lex_to_float(code: UInt64) -> Float64:
    """Non-negative float (or canonical NaN) for a magnitude `code`.

    Total: every `UInt64` maps somewhere. The sign bit is cleared,
    `INF_BITS` maps to `+inf`, larger exponent-saturated patterns map to
    the canonical NaN, and code 0 maps to `0.0`.
    """
    var bits = code & MAG_MASK
    if bits == INF_BITS:
        return inf[DType.float64]()
    if bits > INF_BITS:
        return _bits_to_float(CANON_NAN_BITS)
    return _bits_to_float(bits)


def max_finite() -> Float64:
    """Largest finite `Float64` (`0x7FEFFFFFFFFFFFFF`)."""
    return _bits_to_float(MAX_FINITE_BITS)


@fieldwise_init
struct Floats(Strategy):
    """Floats drawn from a sign bit plus a lexicographic magnitude code.

    All-zero choices draw `+0.0`. Finite draws are clamped into
    `[min_value, max_value]`; NaN bypasses the range because it is
    unordered, and is only drawn when `allow_nan` holds.
    """

    comptime Value = Float64
    var min_value: Float64
    var max_value: Float64
    var allow_nan: Bool
    var allow_infinity: Bool

    def draw(self, mut tc: TestCase) raises -> Float64:
        var negative = tc.draw_boolean()
        var magnitude = lex_to_float(tc.draw_float_bits())
        if isnan(magnitude):
            if self.allow_nan:
                return _bits_to_float(CANON_NAN_BITS)
            magnitude = 0.0
        var value = magnitude
        if negative and magnitude != 0.0:
            value = -magnitude
        var lo = self.min_value
        var hi = self.max_value
        if not self.allow_infinity:
            var finite_max = max_finite()
            if isinf(lo) and lo < 0.0:
                lo = -finite_max
            if isinf(hi) and hi > 0.0:
                hi = finite_max
        if value < lo:
            value = lo
        if value > hi:
            value = hi
        return value


def floats(
    min_value: Optional[Float64] = None,
    max_value: Optional[Float64] = None,
    *,
    allow_nan: Optional[Bool] = None,
    allow_infinity: Optional[Bool] = None,
) raises -> Floats:
    """Strategy drawing `Float64`, shrinking toward `0.0`.

    `min_value` / `max_value` default to `-inf` / `+inf` (unbounded).
    `allow_nan` defaults to true only when both bounds are unset;
    `allow_infinity` defaults to true. An explicit flag always wins.
    NaN bounds or `max_value < min_value` raise.
    """
    var lo = -inf[DType.float64]()
    if min_value is not None:
        lo = min_value.value()
    var hi = inf[DType.float64]()
    if max_value is not None:
        hi = max_value.value()
    if isnan(lo) or isnan(hi):
        raise Error("floats: min_value and max_value must not be NaN")
    if hi < lo:
        raise Error("floats: max_value must be >= min_value")
    var nan_ok = False
    if allow_nan is not None:
        nan_ok = allow_nan.value()
    else:
        nan_ok = (min_value is None) and (max_value is None)
    var inf_ok = True
    if allow_infinity is not None:
        inf_ok = allow_infinity.value()
    return Floats(lo, hi, nan_ok, inf_ok)
