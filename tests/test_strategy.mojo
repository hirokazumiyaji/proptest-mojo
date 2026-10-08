from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy, kind_label
from proptest.strategies.primitives import (
    Integers,
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


def test_integers_invalid_range_raises() raises:
    with assert_raises():
        _ = integers(10, 5)


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
    assert_equal(tc.draw_labels[0], tc.draw_labels[1])


def test_span_label_ignores_distinct_report_labels() raises:
    var tc = _empty()
    _ = tc.draw(integers(0, 5), "first")
    _ = tc.draw(integers(0, 5), "second")
    assert_equal(len(tc.spans), 2)
    assert_equal(tc.spans[0].label, tc.spans[1].label)


def test_integers_draw_rejects_inverted_range() raises:
    # Direct construction permits an invalid range, so `draw` must reject it
    # before the unsigned width calculation.
    with assert_raises(contains="maximum must be >= minimum"):
        _ = _draw_empty(Integers(10, 5))


def test_integers_type_stores_range() raises:
    var strategy = Integers(-3, 7)
    assert_equal(strategy.minimum, -3)
    assert_equal(strategy.maximum, 7)


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


@fieldwise_init
struct Pair(Strategy):
    """Composite strategy that draws twice through `tc.draw` internally."""

    comptime Value = List[Int]
    var bound: Int

    def span_label(self) -> UInt64:
        return kind_label("pair")

    def draw(self, mut tc: TestCase) raises -> List[Int]:
        var a = tc.draw(integers(0, self.bound), "a")
        var b = tc.draw(integers(0, self.bound), "b")
        return [a, b]


@fieldwise_init
struct FailsAfterDrawing(Strategy):
    """Composite that draws once and then raises, leaving a nested record."""

    comptime Value = Int

    def span_label(self) -> UInt64:
        return kind_label("fails_after_drawing")

    def draw(self, mut tc: TestCase) raises -> Int:
        var value = tc.draw(integers(0, 9), "kept")
        raise Error("after draw: " + String(value))


def test_failed_composite_keeps_nested_draw_records() raises:
    # The reserved outer slot is not the tail once nested draws appended
    # their own records, so popping would delete those instead.
    var tc = _empty()
    var reported = String("")
    try:
        _ = tc.draw(FailsAfterDrawing(), "outer")
    except e:
        reported = String(e)
    assert_true("after draw" in reported, msg="expected the raise")
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String("kept"))
    assert_equal(len(tc.draw_values), 1)
    assert_true(
        not tc.draw_values[0].byte_length() == 0,
        msg="the nested draw's value must survive",
    )
    # Spans stay balanced: the nested draw closed its own, and the outer
    # one was closed while unwinding.
    assert_equal(len(tc.spans), 2)
    assert_equal(len(tc.open_spans), 0)


def test_composite_draw_records_outer_before_inner() raises:
    # The outer record slot is reserved before delegating, so the report
    # follows invocation order rather than completion order.
    var tc = _empty()
    var pair = tc.draw(Pair(5), "pair")
    assert_equal(len(pair), 2)
    assert_equal(len(tc.draw_labels), 3)
    assert_equal(tc.draw_labels[0], String("pair"))
    assert_equal(tc.draw_labels[1], String("a"))
    assert_equal(tc.draw_labels[2], String("b"))
    # The outer value is filled in once the draw returns.
    assert_equal(tc.draw_values[0], String(pair))


def test_failed_draw_drops_reserved_record() raises:
    var tc = _empty()
    assert_equal(tc.draw(just[Int](1), "outer"), 1)
    assert_equal(len(tc.draw_labels), 1)
    assert_equal(tc.draw_labels[0], String("outer"))


def test_draw_is_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(integers(-10, 10), UInt64(3))
    var second = _draw_replaying(integers(-10, 10), UInt64(3))
    assert_equal(first, second)
    var a = _replaying(UInt64(3))
    _ = a.draw(integers(-10, 10))
    var b = _replaying(UInt64(3))
    _ = b.draw(integers(-10, 10))
    assert_equal(a.choices, b.choices)


def test_decode_full_int_range_handles_largest_choices() raises:
    var minimum = Int(-0x8000000000000000)
    var maximum = Int(0x7FFFFFFFFFFFFFFF)
    assert_equal(
        decode_integer_choice(UInt64(0xFFFFFFFFFFFFFFFD), minimum, maximum),
        maximum,
    )
    assert_equal(
        decode_integer_choice(UInt64(0xFFFFFFFFFFFFFFFE), minimum, maximum),
        minimum + 1,
    )
    assert_equal(
        decode_integer_choice(UInt64(0xFFFFFFFFFFFFFFFF), minimum, maximum),
        minimum,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
