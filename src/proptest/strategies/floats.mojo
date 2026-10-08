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

from proptest.strategy import Strategy, kind_label
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

    Total: every `UInt64` maps somewhere monotonically. Code 0 maps to
    `0.0`, larger codes map to larger non-negative finite floats up to
    `INF_BITS - 1`, `INF_BITS` maps to `+inf`, and all codes greater than
    `INF_BITS` (including the upper half of `UInt64`) map to canonical
    NaN.
    """
    if code == INF_BITS:
        return inf[DType.float64]()
    if code > INF_BITS:
        return _bits_to_float(CANON_NAN_BITS)
    return _bits_to_float(code)


def max_finite() -> Float64:
    """Largest finite `Float64` (`0x7FEFFFFFFFFFFFFF`)."""
    return _bits_to_float(MAX_FINITE_BITS)


@fieldwise_init
struct Floats(Strategy):
    """Floats drawn from a sign bit plus a lexicographic magnitude code.

    All-zero choices draw `+0.0`. Finite draws are clamped into
    `[min_value, max_value]`. NaN is only drawn when `allow_nan` is True,
    which requires both bounds to be unset (enforced by `floats()`), so a
    bounded strategy never returns NaN.
    """

    comptime Value = Float64
    var min_value: Float64
    var max_value: Float64
    var allow_nan: Bool
    var allow_infinity: Bool

    def span_label(self) -> UInt64:
        return kind_label("floats")

    def draw(self, mut tc: TestCase) raises -> Float64:
        if isnan(self.min_value) or isnan(self.max_value):
            raise Error("floats: min_value and max_value must not be NaN")
        if self.max_value < self.min_value:
            raise Error("floats: max_value must be >= min_value")
        var p_negative = 0.5
        if self.min_value >= 0.0:
            p_negative = 0.0
        elif self.max_value <= 0.0:
            p_negative = 1.0
        var negative = tc.draw_boolean(p_negative)
        if self.min_value >= 0.0:
            negative = False
        elif self.max_value <= 0.0:
            negative = True
        var magnitude = lex_to_float(tc.draw_float_bits())
        if isnan(magnitude):
            if self.allow_nan:
                return _bits_to_float(CANON_NAN_BITS)
            magnitude = 0.0
        if not self.allow_infinity and isinf(magnitude):
            magnitude = max_finite()
        var value = magnitude
        if negative:
            value = -magnitude
        var lo = self.min_value
        var hi = self.max_value
        if not self.allow_infinity:
            var fin_max = max_finite()
            if isinf(lo) and lo < 0.0:
                lo = -fin_max
            if isinf(hi) and hi > 0.0:
                hi = fin_max
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
    `allow_nan=True` is rejected together with explicit bounds — NaN is
    unordered, so a bounded range cannot contain it. NaN bounds,
    `max_value < min_value`, and the degenerate `allow_infinity=False`
    endpoints (`min_value=+inf` or `max_value=-inf`) raise.
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
    var inf_ok = True
    if allow_infinity is not None:
        inf_ok = allow_infinity.value()
    if not inf_ok:
        var finite_max = _bits_to_float(MAX_FINITE_BITS)
        if isinf(lo):
            if lo > 0.0:
                raise Error(
                    "floats: min_value=+inf requires allow_infinity=True"
                )
            lo = -finite_max
        if isinf(hi):
            if hi < 0.0:
                raise Error(
                    "floats: max_value=-inf requires allow_infinity=True"
                )
            hi = finite_max
    var bounded = (min_value is not None) or (max_value is not None)
    var nan_ok = False
    if allow_nan is not None:
        nan_ok = allow_nan.value()
        if nan_ok and bounded:
            raise Error(
                "floats: allow_nan=True is incompatible with explicit"
                " min_value/max_value"
            )
    else:
        nan_ok = not bounded
    return Floats(lo, hi, nan_ok, inf_ok)
