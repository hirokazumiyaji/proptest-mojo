from proptest import Settings, for_all, tuples, optionals
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from proptest.strategies.primitives import booleans, integers, just
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


def _draw_empty[S: Strategy](strategy: S) raises -> S.Value:
    var tc = _empty()
    return tc.draw(strategy)


def _draw_replaying[
    S: Strategy
](strategy: S, *values: UInt64) raises -> S.Value:
    var tc = _replaying(*values)
    return tc.draw(strategy)


def test_tuples2_all_zero_draws_simplest() raises:
    var value = _draw_empty(tuples(integers(-10, 10), booleans()))
    assert_equal(value[0], 0)
    assert_equal(value[1], False)
    assert_equal(String(value), "(0, False)")


def test_tuples3_all_zero_draws_simplest() raises:
    var value = _draw_empty(
        tuples(integers(-10, 10), booleans(), integers(5, 10))
    )
    assert_equal(value[0], 0)
    assert_equal(value[1], False)
    assert_equal(value[2], 5)
    assert_equal(String(value), "(0, False, 5)")


def test_tuples2_is_deterministic_for_same_prefix() raises:
    var strategy = tuples(integers(-10, 10), integers(-10, 10))
    var first = _draw_replaying(strategy, UInt64(3), UInt64(4))
    var second = _draw_replaying(strategy, UInt64(3), UInt64(4))
    assert_equal(String(first), String(second))
    assert_equal(first[0], second[0])
    assert_equal(first[1], second[1])


def test_tuples2_elements_shrink_independently() raises:
    # Choice 3 draws 2 in [-10, 10] (0, 1, -1, 2, ...); each side follows
    # only its own choice.
    var left = _draw_replaying(
        tuples(integers(-10, 10), integers(-10, 10)), UInt64(3), UInt64(0)
    )
    assert_equal(left[0], 2)
    assert_equal(left[1], 0)
    var right = _draw_replaying(
        tuples(integers(-10, 10), integers(-10, 10)), UInt64(0), UInt64(3)
    )
    assert_equal(right[0], 0)
    assert_equal(right[1], 2)
    # Widening the second choice leaves the first element unchanged.
    var widened = _draw_replaying(
        tuples(integers(-10, 10), integers(-10, 10)), UInt64(3), UInt64(5)
    )
    assert_equal(widened[0], 2)
    assert_equal(widened[1], 3)


def test_tuples2_gives_each_element_a_span() raises:
    var tc = _empty()
    _ = tc.draw(tuples(integers(-10, 10), booleans()))
    # Outer span plus one span per element (locality convention).
    assert_equal(len(tc.spans), 3)
    assert_equal(len(tc.choices), 2)


def test_tuples3_gives_each_element_a_span() raises:
    var tc = _empty()
    _ = tc.draw(tuples(integers(0, 5), booleans(), integers(0, 5)))
    assert_equal(len(tc.spans), 4)
    assert_equal(len(tc.choices), 3)


def test_tuples_over_just_consumes_no_choices() raises:
    var tc = _replaying(UInt64(99))
    var value = tc.draw(tuples(just[Int](1), just[Int](2)))
    assert_equal(String(value), "(1, 2)")
    assert_equal(len(tc), 0)


def test_tuples_nests_with_optionals() raises:
    var value = _draw_empty(tuples(optionals(integers(0, 5)), booleans()))
    assert_equal(String(value[0]), "None")
    assert_equal(value[1], False)
    assert_equal(String(value), "(None, False)")


def test_optionals_all_zero_is_none() raises:
    assert_equal(String(_draw_empty(optionals(integers(-10, 10)))), "None")
    assert_equal(
        String(_draw_replaying(optionals(integers(-10, 10)), UInt64(0))),
        "None",
    )


def test_optionals_none_consumes_one_choice() raises:
    var tc = _replaying(UInt64(0), UInt64(99), UInt64(99))
    assert_equal(String(tc.draw(optionals(integers(-10, 10)))), "None")
    assert_equal(len(tc), 1)


def test_optionals_some_draws_inner() raises:
    assert_equal(
        String(
            _draw_replaying(optionals(integers(-10, 10)), UInt64(1), UInt64(0))
        ),
        "0",
    )
    assert_equal(
        String(
            _draw_replaying(optionals(integers(-10, 10)), UInt64(1), UInt64(3))
        ),
        "2",
    )


def test_optionals_inner_shrinks_independently() raises:
    # Same presence flag; the inner value follows only its own choice.
    var narrow = _draw_replaying(
        optionals(integers(-10, 10)), UInt64(1), UInt64(1)
    )
    var wide = _draw_replaying(
        optionals(integers(-10, 10)), UInt64(1), UInt64(5)
    )
    assert_equal(String(narrow), "1")
    assert_equal(String(wide), "3")


def test_optionals_is_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(
        optionals(integers(-10, 10)), UInt64(1), UInt64(3)
    )
    var second = _draw_replaying(
        optionals(integers(-10, 10)), UInt64(1), UInt64(3)
    )
    assert_equal(String(first), String(second))


def _fails_unless_origin(mut tc: TestCase) raises:
    var pair = tc.draw(tuples(integers(0, 100), integers(0, 100)), "pair")
    if pair[0] != 0 or pair[1] != 0:
        return
    raise Error("at origin: pair=" + String(pair))


def _fails_on_none(mut tc: TestCase) raises:
    var maybe = tc.draw(optionals(integers(0, 100)), "maybe")
    if String(maybe) != "None":
        return
    raise Error("got None")


def test_for_all_reports_tuple_readably() raises:
    var report = String("")
    try:
        for_all(_fails_unless_origin, Settings(seed=UInt64(7), max_examples=20))
    except e:
        report = String(e)
    assert_true(
        ("pair = (0, 0)" in report), msg="readable pair, got: " + report
    )


def test_for_all_reports_none_readably() raises:
    var report = String("")
    try:
        for_all(_fails_on_none, Settings(seed=UInt64(7), max_examples=20))
    except e:
        report = String(e)
    assert_true(("maybe = None" in report), msg="readable None, got: " + report)


def test_for_all_shrinks_each_element_independently() raises:
    def prop(mut tc: TestCase) raises:
        var pair = tc.draw(tuples(integers(0, 100), integers(0, 100)), "pair")
        if pair[0] < 5 or pair[1] < 7:
            return
        raise Error("too big: pair=" + String(pair))

    var report = String("")
    try:
        for_all(prop, Settings(seed=UInt64(11), max_examples=100))
    except e:
        report = String(e)
    assert_true(("pair = (5, 7)" in report), msg="minimal pair, got: " + report)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
