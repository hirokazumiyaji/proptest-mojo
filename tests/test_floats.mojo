from proptest import TestCase
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.runner import Settings, for_all
from proptest.strategies.floats import (
    Floats,
    float_to_lex,
    floats,
    lex_to_float,
    max_finite,
)
from proptest.strategies.primitives import integers
from std.math import inf, isinf, isnan
from std.testing import TestSuite, assert_equal, assert_true

comptime FLOAT_MAX = UInt64(0xFFFFFFFFFFFFFFFF)


def _float_prefix(sign: UInt64, code: UInt64) -> ChoiceSequence:
    var prefix = ChoiceSequence()
    prefix.append(ChoiceNode(ChoiceKind.BOOLEAN, sign, UInt64(1), Bool(False)))
    prefix.append(ChoiceNode(ChoiceKind.FLOAT, code, FLOAT_MAX, Bool(False)))
    return prefix^


def test_all_zero_draws_zero() raises:
    var tc = TestCase.replaying(ChoiceSequence())
    assert_equal(tc.draw(floats()), 0.0)


def test_lex_roundtrip_nonnegative() raises:
    assert_equal(float_to_lex(0.0), UInt64(0))
    assert_equal(lex_to_float(UInt64(0)), 0.0)
    assert_true(
        float_to_lex(0.5) < float_to_lex(1.0),
        msg="lex order must match numeric order",
    )
    assert_true(
        float_to_lex(1.0) < float_to_lex(2.0),
        msg="lex order must match numeric order",
    )
    assert_equal(lex_to_float(float_to_lex(0.5)), 0.5)
    assert_equal(lex_to_float(float_to_lex(123.456)), 123.456)
    assert_equal(lex_to_float(float_to_lex(max_finite())), max_finite())


def test_nan_canonicalized() raises:
    var nan = lex_to_float(UInt64(0)) / lex_to_float(UInt64(0))
    assert_true(isnan(nan), msg="need a NaN probe")
    assert_equal(float_to_lex(nan), UInt64(0x7FF8000000000000))
    assert_true(isnan(lex_to_float(UInt64(0x7FF8000000000000))))


def test_allow_nan_false_never_nan() raises:
    var codes = List[UInt64]()
    codes.append(UInt64(0))
    codes.append(UInt64(1))
    codes.append(UInt64(0x3FF0000000000000))
    codes.append(UInt64(0x7FF0000000000000))
    codes.append(UInt64(0x7FF8000000000000))
    codes.append(UInt64(0xFFFFFFFFFFFFFFFF))
    for i in range(len(codes)):
        var tc = TestCase.replaying(_float_prefix(UInt64(0), codes[i]))
        assert_true(not isnan(tc.draw(floats(allow_nan=False))))


def test_allow_infinity_false_never_inf() raises:
    var inf_code = UInt64(0x7FF0000000000000)
    for sign in range(2):
        var tc = TestCase.replaying(_float_prefix(UInt64(sign), inf_code))
        var val = tc.draw(floats(allow_infinity=False))
        assert_true(not isinf(val), msg="must not be infinity")
        assert_true(val <= max_finite() and val >= -max_finite())

    # With finite positive lower bound
    for sign in range(2):
        var tc = TestCase.replaying(_float_prefix(UInt64(sign), inf_code))
        var val = tc.draw(floats(min_value=1.0, allow_infinity=False))
        assert_true(not isinf(val), msg="must not be infinity with lower bound")
        assert_true(val >= 1.0)


def test_ranges_honored() raises:
    var s = floats(min_value=1.5, max_value=2.5)
    var codes = List[UInt64]()
    codes.append(UInt64(0))
    codes.append(UInt64(0x3FF0000000000000))
    codes.append(UInt64(0x4000000000000000))
    codes.append(UInt64(0x7FF0000000000000))
    codes.append(UInt64(0x7FF8000000000000))
    for i in range(len(codes)):
        for sign in range(2):
            var tc = TestCase.replaying(_float_prefix(UInt64(sign), codes[i]))
            var value = tc.draw(s)
            assert_true(
                value >= 1.5 and value <= 2.5,
                msg="ranged floats must stay in range",
            )


def test_no_nan_when_bounded() raises:
    var s = floats(min_value=0.0, max_value=1.0)
    var tc = TestCase.replaying(
        _float_prefix(UInt64(0), UInt64(0x7FF8000000000000))
    )
    assert_true(not isnan(tc.draw(s)))


def test_direct_float_strategy_rejects_invalid_bounds() raises:
    var tc = TestCase.replaying(ChoiceSequence())
    var raised = False
    try:
        _ = tc.draw(Floats(10.0, 0.0, False, True))
    except:
        raised = True
    assert_true(raised, msg="direct float construction must validate bounds")


def test_direct_float_strategy_rejects_incompatible_flags() raises:
    var tc = TestCase.replaying(ChoiceSequence())
    var raised = False
    try:
        _ = tc.draw(Floats(0.0, 1.0, True, True))
    except:
        raised = True
    assert_true(raised, msg="bounded direct strategies must reject NaN")

    raised = False
    var positive_inf = inf[DType.float64]()
    try:
        _ = tc.draw(Floats(positive_inf, positive_inf, False, False))
    except:
        raised = True
    assert_true(
        raised,
        msg="direct strategies cannot require infinity while forbidding it",
    )


def test_infinite_only_bounds_require_infinity() raises:
    var positive = inf[DType.float64]()
    var raised = False
    try:
        _ = floats(positive, positive, allow_infinity=False)
    except:
        raised = True
    assert_true(raised, msg="positive infinity-only bounds are incompatible")
    var negative = -inf[DType.float64]()
    raised = False
    try:
        _ = floats(negative, negative, allow_infinity=False)
    except:
        raised = True
    assert_true(raised, msg="negative infinity-only bounds are incompatible")


def test_generated_values_in_default_range() raises:
    for i in range(16):
        var tc = TestCase.generating(derive(UInt64(16), UInt64(i)))
        var value = tc.draw(floats(allow_nan=False))
        assert_true(not isnan(value), msg="generated value must not be NaN")


def _lex_roundtrip_prop(mut tc: TestCase) raises:
    var code = tc.draw(integers(0, 1000000))
    var probe = Float64(code) / 1000.0
    assert_equal(lex_to_float(float_to_lex(probe)), probe)


def test_roundtrip_property() raises:
    for_all(_lex_roundtrip_prop, Settings(max_examples=20, seed=UInt64(16)))


def test_monotonic_above_inf_and_sign_boundary() raises:
    # Codes above INF_BITS must remain NaN, never wrapping to 0 or subnormal
    var codes = List[UInt64]()
    codes.append(UInt64(0x7FF0000000000001))
    codes.append(UInt64(0x7FFFFFFFFFFFFFFF))
    codes.append(UInt64(0x8000000000000000))
    codes.append(UInt64(0x8000000000000001))
    codes.append(UInt64(0xFFFFFFFFFFFFFFFF))
    for i in range(len(codes)):
        assert_true(
            isnan(lex_to_float(codes[i])),
            msg="codes above inf must be NaN, not wrapped",
        )


def test_negative_ranges_honored() raises:
    var s = floats(min_value=-5.0, max_value=-1.0)
    var tc_zero = TestCase.replaying(ChoiceSequence())
    assert_equal(tc_zero.draw(s), -1.0)
    for i in range(16):
        var tc = TestCase.generating(derive(UInt64(42), UInt64(i)))
        var value = tc.draw(s)
        assert_true(
            value >= -5.0 and value <= -1.0,
            msg="negative ranged floats must stay in range",
        )


def test_generation_biased_finite() raises:
    # Most generated floats should be finite (not NaN or Inf)
    var finite_count = 0
    for i in range(50):
        var tc = TestCase.generating(derive(UInt64(99), UInt64(i)))
        var value = tc.draw(floats())
        if not isnan(value) and not isinf(value):
            finite_count += 1
    assert_true(finite_count >= 40, msg="most generated floats must be finite")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
