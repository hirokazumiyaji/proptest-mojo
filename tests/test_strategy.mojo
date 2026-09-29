from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from proptest.strategies.primitives import (
    booleans,
    decode_integer_choice,
    integers,
    just,
)
from proptest.testcase import TestCase
from std.testing import TestSuite, assert_equal, assert_true


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


def _distance(a: Int, b: Int) -> Int:
    var d = a - b
    if d < 0:
        return -d
    return d


def test_integers_all_zero_draws_target() raises:
    assert_equal(_draw_empty(integers(-10, 10)), 0)
    assert_equal(_draw_empty(integers(5, 10)), 5)
    assert_equal(_draw_empty(integers(-10, -5)), -5)
    assert_equal(_draw_empty(integers(0, 0)), 0)
    assert_equal(_draw_empty(integers(7, 7)), 7)


def test_integers_choice_zero_is_target() raises:
    assert_equal(_draw_replaying(integers(-10, 10), UInt64(0)), 0)
    assert_equal(_draw_replaying(integers(5, 10), UInt64(0)), 5)
    assert_equal(_draw_replaying(integers(-10, -5), UInt64(0)), -5)
    assert_equal(_draw_replaying(integers(-3, 3), UInt64(0)), 0)
    assert_equal(_draw_replaying(integers(1, 100), UInt64(0)), 1)
    assert_equal(_draw_replaying(integers(-100, -1), UInt64(0)), -1)


def test_integers_small_choices_stay_near_target() raises:
    var expected = List[Int]()
    expected.append(0)
    expected.append(1)
    expected.append(-1)
    expected.append(2)
    expected.append(-2)
    expected.append(3)
    for k in range(len(expected)):
        assert_equal(_draw_replaying(integers(-10, 10), UInt64(k)), expected[k])
    var previous = 0
    for k in range(21):
        var value = _draw_replaying(integers(-10, 10), UInt64(k))
        var dist = _distance(value, 0)
        assert_true(
            dist >= previous, msg="distance from target must not shrink"
        )
        previous = dist


def test_integers_positive_range_counts_up() raises:
    for k in range(6):
        assert_equal(_draw_replaying(integers(5, 10), UInt64(k)), 5 + k)


def test_integers_negative_range_counts_down() raises:
    for k in range(6):
        assert_equal(_draw_replaying(integers(-10, -5), UInt64(k)), -5 - k)


def test_integers_single_value_range_ignores_choice() raises:
    assert_equal(_draw_replaying(integers(4, 4), UInt64(0)), 4)
    assert_equal(_draw_replaying(integers(4, 4), UInt64(1)), 4)
    assert_equal(_draw_replaying(integers(4, 4), UInt64(7)), 4)
    assert_equal(_draw_replaying(integers(4, 4), UInt64(0xFFFFFFFFFFFFFFFF)), 4)


def test_integers_always_in_range() raises:
    var minimums = List[Int]()
    var maximums = List[Int]()
    minimums.append(-10)
    maximums.append(10)
    minimums.append(5)
    maximums.append(10)
    minimums.append(-10)
    maximums.append(-5)
    minimums.append(0)
    maximums.append(1)
    minimums.append(-1000000)
    maximums.append(1000000)
    var choices = List[UInt64]()
    choices.append(UInt64(0))
    choices.append(UInt64(1))
    choices.append(UInt64(2))
    choices.append(UInt64(3))
    choices.append(UInt64(17))
    choices.append(UInt64(1000))
    choices.append(UInt64(0xFFFFFFFFFFFFFFFF))
    for r in range(len(minimums)):
        for c in range(len(choices)):
            var value = _draw_replaying(
                integers(minimums[r], maximums[r]), choices[c]
            )
            assert_true(
                minimums[r] <= value and value <= maximums[r],
                msg="drawn value must stay in range",
            )
    for seed in range(32):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(integers(-50, 50))
        assert_true(-50 <= value and value <= 50)


def test_integers_invalid_range_raises() raises:
    var raised = False
    try:
        _ = integers(10, 5)
    except:
        raised = True
    assert_true(raised, msg="empty range must raise")


def test_booleans_all_zero_is_false() raises:
    assert_equal(_draw_empty(booleans()), False)
    assert_equal(_draw_replaying(booleans(), UInt64(0)), False)
    assert_equal(_draw_replaying(booleans(), UInt64(1)), True)


def test_booleans_records_boolean_choice() raises:
    var tc = _replaying(UInt64(1))
    assert_equal(tc.draw(booleans()), True)
    assert_equal(len(tc.choices), 1)
    assert_equal(tc.choices[0].kind, ChoiceKind.BOOLEAN)
    assert_equal(tc.choices[0].max_value, UInt64(1))
    assert_equal(tc.choices[0].value, UInt64(1))


def test_just_returns_value_without_consuming() raises:
    var tc = _replaying(UInt64(99))
    assert_equal(tc.draw(just[Int](41)), 41)
    assert_equal(tc.draw(just[Int](42)), 42)
    assert_equal(len(tc), 0)
    var words = _empty()
    assert_equal(words.draw(just[String](String("hi"))), String("hi"))
    assert_equal(len(words), 0)


def test_draw_records_span_label_and_value() raises:
    var tc = _empty()
    var value = tc.draw(integers(0, 5), "count")
    assert_equal(len(tc.spans), 1)
    assert_equal(tc.spans[0].start, 0)
    assert_equal(tc.spans[0].end, 1)
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String("count"))
    assert_equal(len(tc.draw_values), 1)
    assert_equal(tc.draw_values[0], String(value))


def test_draw_with_default_label() raises:
    var tc = _empty()
    _ = tc.draw(booleans())
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String(""))


def test_draw_is_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(integers(-10, 10), UInt64(3))
    var second = _draw_replaying(integers(-10, 10), UInt64(3))
    assert_equal(first, second)
    var a = _replaying(UInt64(3))
    _ = a.draw(integers(-10, 10))
    var b = _replaying(UInt64(3))
    _ = b.draw(integers(-10, 10))
    assert_equal(a.choices, b.choices)


def test_decode_is_monotone_around_target() raises:
    var minimums = List[Int]()
    var maximums = List[Int]()
    var targets = List[Int]()
    minimums.append(-10)
    maximums.append(10)
    targets.append(0)
    minimums.append(3)
    maximums.append(9)
    targets.append(3)
    minimums.append(-9)
    maximums.append(-3)
    targets.append(-3)
    for r in range(len(minimums)):
        var width = maximums[r] - minimums[r]
        var previous = 0
        for k in range(width + 1):
            var value = decode_integer_choice(
                UInt64(k), minimums[r], maximums[r]
            )
            assert_true(
                minimums[r] <= value and value <= maximums[r],
                msg="decoded value must stay in range",
            )
            var dist = _distance(value, targets[r])
            assert_true(
                dist >= previous, msg="decoded distance must not shrink"
            )
            previous = dist


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
