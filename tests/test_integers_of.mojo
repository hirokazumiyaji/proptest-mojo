from proptest import decode_integers_of_choice as root_decoder
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from proptest.strategies.combinators import flat_map
from proptest.strategies.primitives import (
    IntegersOf,
    decode_integers_of_choice,
    integers,
    integers_of,
)
from proptest.testcase import TestCase
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _inverted_int8(_n: Int) -> IntegersOf[DType.int8]:
    # Non-raising thin factory: fieldwise construction can return inverted
    # bounds that only become invalid at draw time.
    return IntegersOf[DType.int8](Int8(10), Int8(5))


def test_decoder_is_exported_from_package_root() raises:
    # The public decoder is re-exported at the root, so a client using
    # `from proptest import decode_integers_of_choice` can import it.
    var minimum = Scalar[DType.int32](-5)
    var maximum = Scalar[DType.int32](7)
    assert_equal(
        root_decoder[DType.int32](UInt64(0), minimum, maximum),
        decode_integers_of_choice[DType.int32](UInt64(0), minimum, maximum),
    )


def _replaying(*values: UInt64) -> TestCase:
    var prefix = ChoiceSequence()
    for v in values:
        prefix.append(
            ChoiceNode(ChoiceKind.INTEGER, v, UInt64(100), Bool(False))
        )
    return TestCase.replaying(prefix^)


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _draw_empty[S: Strategy](strategy: S) raises -> S.Value:
    var tc = _empty()
    return tc.draw(strategy)


def _draw_replaying[
    S: Strategy
](strategy: S, *values: UInt64) raises -> S.Value:
    var tc = _replaying(*values)
    return tc.draw(strategy)


def _small_dist[dtype: DType](a: Scalar[dtype], b: Scalar[dtype]) -> UInt64:
    # Exact only for the small test ranges below (all values fit in Int64
    # with room to subtract without overflow).
    var d = Int64(a) - Int64(b)
    if d < 0:
        d = -d
    return UInt64(d)


def _check_full_bounds[dtype: DType]() raises:
    var s = integers_of[dtype]()
    assert_equal(s.minimum, Scalar[dtype].MIN)
    assert_equal(s.maximum, Scalar[dtype].MAX)


def _check_full_target_zero[dtype: DType]() raises:
    assert_equal(_draw_empty(integers_of[dtype]()), Scalar[dtype](0))


def _check_single_ignores_choice[dtype: DType]() raises:
    var seven = Scalar[dtype](7)
    assert_equal(_draw_replaying(integers_of[dtype](seven, seven)), seven)
    assert_equal(
        _draw_replaying(integers_of[dtype](seven, seven), UInt64(1)), seven
    )
    assert_equal(
        _draw_replaying(integers_of[dtype](seven, seven), UInt64(7)), seven
    )
    assert_equal(
        _draw_replaying(
            integers_of[dtype](seven, seven), UInt64(0xFFFFFFFFFFFFFFFF)
        ),
        seven,
    )


def _check_positive_counts_up[dtype: DType]() raises:
    var s = integers_of[dtype](Scalar[dtype](5), Scalar[dtype](10))
    for k in range(6):
        assert_equal(_draw_replaying(s, UInt64(k)), Scalar[dtype](5 + k))


def _check_target_near_zero[
    dtype: DType
](minimum: Scalar[dtype], maximum: Scalar[dtype], target: Scalar[dtype]) raises:
    var s = integers_of[dtype](minimum, maximum)
    assert_equal(_draw_empty(s), target)
    assert_equal(_draw_replaying(s, UInt64(0)), target)


def _check_monotone[
    dtype: DType
](minimum: Scalar[dtype], maximum: Scalar[dtype], target: Scalar[dtype]) raises:
    var width = _small_dist(maximum, minimum)
    var previous = UInt64(0)
    var k = UInt64(0)
    while k <= width:
        var value = decode_integers_of_choice[dtype](k, minimum, maximum)
        assert_true(
            minimum <= value and value <= maximum,
            msg="decoded value must stay in range",
        )
        var dist = _small_dist(value, target)
        assert_true(dist >= previous, msg="decoded distance must not shrink")
        previous = dist
        k += 1


def test_full_range_covers_dtype() raises:
    _check_full_bounds[DType.int8]()
    _check_full_bounds[DType.int16]()
    _check_full_bounds[DType.int32]()
    _check_full_bounds[DType.int64]()
    _check_full_bounds[DType.uint8]()
    _check_full_bounds[DType.uint16]()
    _check_full_bounds[DType.uint32]()
    _check_full_bounds[DType.uint64]()


def test_full_range_shrink_target_is_zero() raises:
    _check_full_target_zero[DType.int8]()
    _check_full_target_zero[DType.int16]()
    _check_full_target_zero[DType.int32]()
    _check_full_target_zero[DType.int64]()
    _check_full_target_zero[DType.uint8]()
    _check_full_target_zero[DType.uint16]()
    _check_full_target_zero[DType.uint32]()
    _check_full_target_zero[DType.uint64]()


def test_signed_shrink_target() raises:
    _check_target_near_zero[DType.int8](
        Scalar[DType.int8](-10), Scalar[DType.int8](10), Scalar[DType.int8](0)
    )
    _check_target_near_zero[DType.int8](
        Scalar[DType.int8](5), Scalar[DType.int8](10), Scalar[DType.int8](5)
    )
    _check_target_near_zero[DType.int8](
        Scalar[DType.int8](-10),
        Scalar[DType.int8](-5),
        Scalar[DType.int8](-5),
    )
    _check_target_near_zero[DType.int16](
        Scalar[DType.int16](-10),
        Scalar[DType.int16](10),
        Scalar[DType.int16](0),
    )
    _check_target_near_zero[DType.int32](
        Scalar[DType.int32](1),
        Scalar[DType.int32](100),
        Scalar[DType.int32](1),
    )
    _check_target_near_zero[DType.int32](
        Scalar[DType.int32](-100),
        Scalar[DType.int32](-1),
        Scalar[DType.int32](-1),
    )
    _check_target_near_zero[DType.int64](
        Scalar[DType.int64](-10),
        Scalar[DType.int64](10),
        Scalar[DType.int64](0),
    )


def test_unsigned_shrink_target() raises:
    _check_target_near_zero[DType.uint8](
        Scalar[DType.uint8](0), Scalar[DType.uint8](10), Scalar[DType.uint8](0)
    )
    _check_target_near_zero[DType.uint8](
        Scalar[DType.uint8](5), Scalar[DType.uint8](10), Scalar[DType.uint8](5)
    )
    _check_target_near_zero[DType.uint16](
        Scalar[DType.uint16](0),
        Scalar[DType.uint16](10),
        Scalar[DType.uint16](0),
    )
    _check_target_near_zero[DType.uint32](
        Scalar[DType.uint32](3),
        Scalar[DType.uint32](9),
        Scalar[DType.uint32](3),
    )
    _check_target_near_zero[DType.uint64](
        Scalar[DType.uint64](0),
        Scalar[DType.uint64](10),
        Scalar[DType.uint64](0),
    )


def test_positive_range_counts_up() raises:
    _check_positive_counts_up[DType.int8]()
    _check_positive_counts_up[DType.int16]()
    _check_positive_counts_up[DType.int32]()
    _check_positive_counts_up[DType.int64]()
    _check_positive_counts_up[DType.uint8]()
    _check_positive_counts_up[DType.uint16]()
    _check_positive_counts_up[DType.uint32]()
    _check_positive_counts_up[DType.uint64]()


def test_signed_negative_range_counts_down() raises:
    var s8 = integers_of[DType.int8](
        Scalar[DType.int8](-10), Scalar[DType.int8](-5)
    )
    for k in range(6):
        assert_equal(_draw_replaying(s8, UInt64(k)), Scalar[DType.int8](-5 - k))
    var s32 = integers_of[DType.int32](
        Scalar[DType.int32](-10), Scalar[DType.int32](-5)
    )
    for k in range(6):
        assert_equal(
            _draw_replaying(s32, UInt64(k)), Scalar[DType.int32](-5 - k)
        )
    var s64 = integers_of[DType.int64](
        Scalar[DType.int64](-10), Scalar[DType.int64](-5)
    )
    for k in range(6):
        assert_equal(
            _draw_replaying(s64, UInt64(k)), Scalar[DType.int64](-5 - k)
        )


def test_signed_symmetric_alternation() raises:
    var expected = List[Int]()
    expected.append(0)
    expected.append(1)
    expected.append(-1)
    expected.append(2)
    expected.append(-2)
    expected.append(3)
    var s = integers_of[DType.int32](
        Scalar[DType.int32](-10), Scalar[DType.int32](10)
    )
    for k in range(len(expected)):
        assert_equal(
            _draw_replaying(s, UInt64(k)), Scalar[DType.int32](expected[k])
        )
    var s8 = integers_of[DType.int8](
        Scalar[DType.int8](-10), Scalar[DType.int8](10)
    )
    for k in range(len(expected)):
        assert_equal(
            _draw_replaying(s8, UInt64(k)), Scalar[DType.int8](expected[k])
        )


def test_unsigned_range_counts_up_from_zero() raises:
    var s = integers_of[DType.uint8](
        Scalar[DType.uint8](0), Scalar[DType.uint8](5)
    )
    for k in range(6):
        assert_equal(_draw_replaying(s, UInt64(k)), Scalar[DType.uint8](k))


def test_single_value_range_ignores_choice() raises:
    _check_single_ignores_choice[DType.int8]()
    _check_single_ignores_choice[DType.int16]()
    _check_single_ignores_choice[DType.int32]()
    _check_single_ignores_choice[DType.int64]()
    _check_single_ignores_choice[DType.uint8]()
    _check_single_ignores_choice[DType.uint16]()
    _check_single_ignores_choice[DType.uint32]()
    _check_single_ignores_choice[DType.uint64]()


def test_sampled_draws_stay_in_range() raises:
    var choices = List[UInt64]()
    choices.append(UInt64(0))
    choices.append(UInt64(1))
    choices.append(UInt64(2))
    choices.append(UInt64(3))
    choices.append(UInt64(17))
    choices.append(UInt64(1000))
    choices.append(UInt64(0xFFFFFFFFFFFFFFFF))
    var s8 = integers_of[DType.int8](
        Scalar[DType.int8](-10), Scalar[DType.int8](10)
    )
    for c in range(len(choices)):
        var value = _draw_replaying(s8, choices[c])
        assert_true(
            Scalar[DType.int8](-10) <= value
            and value <= Scalar[DType.int8](10),
            msg="drawn value must stay in range",
        )
    var su = integers_of[DType.uint8](
        Scalar[DType.uint8](5), Scalar[DType.uint8](10)
    )
    for c in range(len(choices)):
        var value = _draw_replaying(su, choices[c])
        assert_true(
            Scalar[DType.uint8](5) <= value
            and value <= Scalar[DType.uint8](10),
            msg="drawn value must stay in range",
        )
    var s64 = integers_of[DType.int64]()
    for c in range(len(choices)):
        var value = _draw_replaying(s64, choices[c])
        assert_true(
            Scalar[DType.int64].MIN <= value
            and value <= Scalar[DType.int64].MAX,
            msg="drawn value must stay in range",
        )
    var u64 = integers_of[DType.uint64]()
    for c in range(len(choices)):
        var value = _draw_replaying(u64, choices[c])
        assert_true(
            Scalar[DType.uint64].MIN <= value
            and value <= Scalar[DType.uint64].MAX,
            msg="drawn value must stay in range",
        )


def test_edge_ranges_stay_in_range() raises:
    var s8lo = integers_of[DType.int8](
        Scalar[DType.int8].MIN, Scalar[DType.int8].MIN + Scalar[DType.int8](10)
    )
    for k in range(11):
        var value = _draw_replaying(s8lo, UInt64(k))
        assert_true(
            Scalar[DType.int8].MIN <= value
            and value <= Scalar[DType.int8].MIN + Scalar[DType.int8](10),
            msg="drawn value must stay in range",
        )
    var s8hi = integers_of[DType.int8](
        Scalar[DType.int8].MAX - Scalar[DType.int8](10),
        Scalar[DType.int8].MAX,
    )
    for k in range(11):
        var value = _draw_replaying(s8hi, UInt64(k))
        assert_true(
            Scalar[DType.int8].MAX - Scalar[DType.int8](10) <= value
            and value <= Scalar[DType.int8].MAX,
            msg="drawn value must stay in range",
        )
    var u64hi = integers_of[DType.uint64](
        Scalar[DType.uint64].MAX - Scalar[DType.uint64](10),
        Scalar[DType.uint64].MAX,
    )
    for k in range(11):
        var value = _draw_replaying(u64hi, UInt64(k))
        assert_true(
            Scalar[DType.uint64].MAX - Scalar[DType.uint64](10) <= value
            and value <= Scalar[DType.uint64].MAX,
            msg="drawn value must stay in range",
        )
    var i64lo = integers_of[DType.int64](
        Scalar[DType.int64].MIN,
        Scalar[DType.int64].MIN + Scalar[DType.int64](10),
    )
    for k in range(11):
        var value = _draw_replaying(i64lo, UInt64(k))
        assert_true(
            Scalar[DType.int64].MIN <= value
            and value <= Scalar[DType.int64].MIN + Scalar[DType.int64](10),
            msg="drawn value must stay in range",
        )


def test_generating_stays_in_range() raises:
    for seed in range(16):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(
            integers_of[DType.int8](
                Scalar[DType.int8](-50), Scalar[DType.int8](50)
            )
        )
        assert_true(
            Scalar[DType.int8](-50) <= value and value <= Scalar[DType.int8](50)
        )
    for seed in range(16):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(integers_of[DType.int64]())
        assert_true(
            Scalar[DType.int64].MIN <= value
            and value <= Scalar[DType.int64].MAX
        )
    for seed in range(16):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(integers_of[DType.uint64]())
        assert_true(
            Scalar[DType.uint64].MIN <= value
            and value <= Scalar[DType.uint64].MAX
        )


def test_int64_full_range_edges() raises:
    var minimum = Scalar[DType.int64].MIN
    var maximum = Scalar[DType.int64].MAX
    assert_equal(
        decode_integers_of_choice[DType.int64](UInt64(0), minimum, maximum),
        Scalar[DType.int64](0),
    )
    assert_equal(
        decode_integers_of_choice[DType.int64](UInt64(1), minimum, maximum),
        Scalar[DType.int64](1),
    )
    assert_equal(
        decode_integers_of_choice[DType.int64](UInt64(2), minimum, maximum),
        Scalar[DType.int64](-1),
    )
    assert_equal(
        decode_integers_of_choice[DType.int64](
            UInt64(0xFFFFFFFFFFFFFFFD), minimum, maximum
        ),
        maximum,
    )
    assert_equal(
        decode_integers_of_choice[DType.int64](
            UInt64(0xFFFFFFFFFFFFFFFF), minimum, maximum
        ),
        minimum,
    )


def test_uint64_full_range_edges() raises:
    var minimum = Scalar[DType.uint64].MIN
    var maximum = Scalar[DType.uint64].MAX
    assert_equal(
        decode_integers_of_choice[DType.uint64](UInt64(0), minimum, maximum),
        Scalar[DType.uint64](0),
    )
    assert_equal(
        decode_integers_of_choice[DType.uint64](UInt64(1), minimum, maximum),
        Scalar[DType.uint64](1),
    )
    assert_equal(
        decode_integers_of_choice[DType.uint64](UInt64(2), minimum, maximum),
        Scalar[DType.uint64](2),
    )
    assert_equal(
        decode_integers_of_choice[DType.uint64](
            UInt64(0xFFFFFFFFFFFFFFFF), minimum, maximum
        ),
        maximum,
    )


def test_narrow_full_ranges_cover_min_max() raises:
    var i8min = Scalar[DType.int8].MIN
    var i8max = Scalar[DType.int8].MAX
    assert_equal(
        decode_integers_of_choice[DType.int8](UInt64(0), i8min, i8max),
        Scalar[DType.int8](0),
    )
    var seen_min = False
    var seen_max = False
    for k in range(256):
        var value = decode_integers_of_choice[DType.int8](
            UInt64(k), i8min, i8max
        )
        assert_true(
            i8min <= value and value <= i8max,
            msg="decoded value must stay in range",
        )
        if value == i8min:
            seen_min = True
        if value == i8max:
            seen_max = True
    assert_true(seen_min, msg="full Int8 range must draw MIN")
    assert_true(seen_max, msg="full Int8 range must draw MAX")
    var u8min = Scalar[DType.uint8].MIN
    var u8max = Scalar[DType.uint8].MAX
    assert_equal(
        decode_integers_of_choice[DType.uint8](UInt64(0), u8min, u8max),
        Scalar[DType.uint8](0),
    )
    var useen_min = False
    var useen_max = False
    for k in range(256):
        var value = decode_integers_of_choice[DType.uint8](
            UInt64(k), u8min, u8max
        )
        assert_true(
            u8min <= value and value <= u8max,
            msg="decoded value must stay in range",
        )
        if value == u8min:
            useen_min = True
        if value == u8max:
            useen_max = True
    assert_true(useen_min, msg="full UInt8 range must draw MIN")
    assert_true(useen_max, msg="full UInt8 range must draw MAX")


def test_decode_is_monotone_around_target() raises:
    _check_monotone[DType.int8](
        Scalar[DType.int8](-10), Scalar[DType.int8](10), Scalar[DType.int8](0)
    )
    _check_monotone[DType.int8](
        Scalar[DType.int8](3), Scalar[DType.int8](9), Scalar[DType.int8](3)
    )
    _check_monotone[DType.int8](
        Scalar[DType.int8](-9), Scalar[DType.int8](-3), Scalar[DType.int8](-3)
    )
    _check_monotone[DType.int16](
        Scalar[DType.int16](-10),
        Scalar[DType.int16](10),
        Scalar[DType.int16](0),
    )
    _check_monotone[DType.int32](
        Scalar[DType.int32](-10),
        Scalar[DType.int32](10),
        Scalar[DType.int32](0),
    )
    _check_monotone[DType.uint8](
        Scalar[DType.uint8](0), Scalar[DType.uint8](10), Scalar[DType.uint8](0)
    )
    _check_monotone[DType.uint8](
        Scalar[DType.uint8](3), Scalar[DType.uint8](9), Scalar[DType.uint8](3)
    )
    _check_monotone[DType.uint32](
        Scalar[DType.uint32](0),
        Scalar[DType.uint32](10),
        Scalar[DType.uint32](0),
    )


def test_decode_clamps_choice_above_width() raises:
    # Any choice past the biased distance between the bounds must clamp to
    # the maximum reachable value, keeping the result in range.
    var i8min = Scalar[DType.int8](-5)
    var i8max = Scalar[DType.int8](5)
    var edge = decode_integers_of_choice[DType.int8](UInt64(10), i8min, i8max)
    for over in range(11, 20):
        var value = decode_integers_of_choice[DType.int8](
            UInt64(over), i8min, i8max
        )
        assert_true(
            i8min <= value and value <= i8max,
            msg="clamped decode must stay in range",
        )
        assert_equal(value, edge)
    var u8min = Scalar[DType.uint8](3)
    var u8max = Scalar[DType.uint8](9)
    var uedge = decode_integers_of_choice[DType.uint8](UInt64(6), u8min, u8max)
    var huge = decode_integers_of_choice[DType.uint8](
        UInt64(0xFFFFFFFFFFFFFFFF), u8min, u8max
    )
    assert_equal(huge, uedge)
    assert_true(
        u8min <= huge and huge <= u8max,
        msg="clamped decode must stay in range",
    )


def test_invalid_range_raises() raises:
    var raised8 = False
    try:
        _ = integers_of[DType.int8](
            Scalar[DType.int8](10), Scalar[DType.int8](5)
        )
    except:
        raised8 = True
    assert_true(raised8, msg="empty range must raise")
    var raisedu = False
    try:
        _ = integers_of[DType.uint8](
            Scalar[DType.uint8](10), Scalar[DType.uint8](5)
        )
    except:
        raisedu = True
    assert_true(raisedu, msg="empty range must raise")
    var raised64 = False
    try:
        _ = integers_of[DType.int64](
            Scalar[DType.int64](1), Scalar[DType.int64](0)
        )
    except:
        raised64 = True
    assert_true(raised64, msg="empty range must raise")


def test_draw_is_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(
        integers_of[DType.int32](
            Scalar[DType.int32](-10), Scalar[DType.int32](10)
        ),
        UInt64(3),
    )
    var second = _draw_replaying(
        integers_of[DType.int32](
            Scalar[DType.int32](-10), Scalar[DType.int32](10)
        ),
        UInt64(3),
    )
    assert_equal(first, second)
    var a = _replaying(UInt64(3))
    _ = a.draw(
        integers_of[DType.uint64](
            Scalar[DType.uint64](0), Scalar[DType.uint64](100)
        )
    )
    var b = _replaying(UInt64(3))
    _ = b.draw(
        integers_of[DType.uint64](
            Scalar[DType.uint64](0), Scalar[DType.uint64](100)
        )
    )
    assert_equal(a.choices, b.choices)


def test_integers_of_draw_rejects_inverted_range() raises:
    # Direct construction permits an invalid range, so `draw` must reject it
    # before the unsigned width calculation wraps.
    with assert_raises(contains="maximum must be >= minimum"):
        _ = _draw_empty(IntegersOf[DType.int8](Int8(10), Int8(5)))


def test_integers_of_draw_rejects_inverted_from_thin_factory() raises:
    with assert_raises(contains="maximum must be >= minimum"):
        _ = _draw_empty(flat_map[_inverted_int8](integers(0, 0)))


def test_integers_of_full_range_survives_draw_validation() raises:
    # Full signed/unsigned ranges remain valid after the inverted-range guard.
    assert_equal(_draw_empty(integers_of[DType.int8]()), Int8(0))
    assert_equal(_draw_empty(integers_of[DType.uint64]()), UInt64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
