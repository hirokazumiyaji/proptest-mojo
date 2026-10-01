from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy, kind_label
from proptest.strategies.primitives import (
    booleans,
    decode_integer_choice,
    integers,
    just,
)
from proptest.testcase import TestCase
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
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
    var expected: List[Int] = [0, 1, -1, 2, -2, 3]
    for k in range(len(expected)):
        assert_equal(_draw_replaying(integers(-10, 10), UInt64(k)), expected[k])
    var previous = 0
    for k in range(21):
        var value = _draw_replaying(integers(-10, 10), UInt64(k))
        var dist = abs(value)
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
    var minimums: List[Int] = [-10, 5, -10, 0, -1000000]
    var maximums: List[Int] = [10, 10, -5, 1, 1000000]
    var choices: List[UInt64] = [
        UInt64(0),
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(17),
        UInt64(1000),
        UInt64(0xFFFFFFFFFFFFFFFF),
    ]
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
    with assert_raises():
        _ = integers(10, 5)


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
    assert_equal(tc.spans[0].label, integers(0, 5).span_label())
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String("count"))
    assert_equal(len(tc.draw_values), 1)
    assert_equal(tc.draw_values[0], String(value))


def test_draw_with_default_label() raises:
    var tc = _empty()
    _ = tc.draw(booleans())
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String(""))


def test_span_label_follows_strategy_not_report_label() raises:
    # A reused reporting label must not merge two strategy kinds: shrink
    # passes may reorder blocks that share a span label.
    var tc = _empty()
    _ = tc.draw(integers(0, 5), "x")
    _ = tc.draw(booleans(), "x")
    assert_equal(len(tc.spans), 2)
    assert_not_equal(tc.spans[0].label, tc.spans[1].label)
    assert_equal(tc.spans[0].label, kind_label("integers"))
    assert_equal(tc.spans[1].label, kind_label("booleans"))
    # Equal reporting labels stay out of the structural identity.
    assert_equal(tc.draw_labels[0], tc.draw_labels[1])


def test_span_label_ignores_distinct_report_labels() raises:
    var tc = _empty()
    _ = tc.draw(integers(0, 5), "first")
    _ = tc.draw(integers(0, 5), "second")
    assert_equal(len(tc.spans), 2)
    assert_equal(tc.spans[0].label, tc.spans[1].label)


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
    var minimums: List[Int] = [-10, 3, -9]
    var maximums: List[Int] = [10, 9, -3]
    var targets: List[Int] = [0, 3, -3]
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
            var dist = abs(value - targets[r])
            assert_true(
                dist >= previous, msg="decoded distance must not shrink"
            )
            previous = dist


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
