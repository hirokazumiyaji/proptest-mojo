from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.strategy import Strategy
from proptest.strategies.choice import one_of, one_of2, sampled_from
from proptest.strategies.primitives import Integers, Just, integers, just
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


def _ints() raises -> List[Integers]:
    var opts = List[Integers]()
    opts.append(integers(0, 1))
    opts.append(integers(5, 6))
    return opts^


def _numbers() raises -> List[Int]:
    var values = List[Int]()
    values.append(10)
    values.append(20)
    values.append(30)
    return values^


def test_sampled_from_all_zero_draws_front() raises:
    assert_equal(_draw_empty(sampled_from[Int](_numbers())), 10)


def test_sampled_from_index_selects_element() raises:
    assert_equal(_draw_replaying(sampled_from[Int](_numbers()), UInt64(0)), 10)
    assert_equal(_draw_replaying(sampled_from[Int](_numbers()), UInt64(1)), 20)
    assert_equal(_draw_replaying(sampled_from[Int](_numbers()), UInt64(2)), 30)


def test_sampled_from_single_value_ignores_choice() raises:
    var only = List[Int]()
    only.append(7)
    assert_equal(_draw_replaying(sampled_from[Int](only^), UInt64(0)), 7)
    var other = List[Int]()
    other.append(7)
    assert_equal(_draw_replaying(sampled_from[Int](other^), UInt64(99)), 7)


def test_sampled_from_out_of_range_prefix_clamps_to_last() raises:
    assert_equal(_draw_replaying(sampled_from[Int](_numbers()), UInt64(99)), 30)


def test_sampled_from_empty_raises() raises:
    var raised = False
    try:
        _ = sampled_from[Int](List[Int]())
    except:
        raised = True
    assert_true(raised, msg="empty values must raise")


def test_sampled_from_records_one_integer_choice() raises:
    var tc = _replaying(UInt64(2))
    assert_equal(tc.draw(sampled_from[Int](_numbers())), 30)
    assert_equal(len(tc.choices), 1)
    assert_equal(tc.choices[0].kind, ChoiceKind.INTEGER)
    assert_equal(tc.choices[0].max_value, UInt64(2))
    assert_equal(tc.choices[0].value, UInt64(2))


def test_sampled_from_string_values() raises:
    var words = List[String]()
    words.append(String("a"))
    words.append(String("b"))
    assert_equal(_draw_empty(sampled_from[String](words^)), String("a"))
    var more = List[String]()
    more.append(String("a"))
    more.append(String("b"))
    assert_equal(
        _draw_replaying(sampled_from[String](more^), UInt64(1)), String("b")
    )


def test_sampled_from_is_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(sampled_from[Int](_numbers()), UInt64(1))
    var second = _draw_replaying(sampled_from[Int](_numbers()), UInt64(1))
    assert_equal(first, second)


def test_one_of_all_zero_draws_first_strategy_simplest() raises:
    assert_equal(_draw_empty(one_of[Integers](_ints())), 0)


def test_one_of_index_selects_strategy() raises:
    assert_equal(
        _draw_replaying(one_of[Integers](_ints()), UInt64(0), UInt64(0)), 0
    )
    assert_equal(
        _draw_replaying(one_of[Integers](_ints()), UInt64(1), UInt64(0)), 5
    )


def test_one_of_inner_choices_follow_index() raises:
    assert_equal(
        _draw_replaying(one_of[Integers](_ints()), UInt64(0), UInt64(1)), 1
    )
    assert_equal(
        _draw_replaying(one_of[Integers](_ints()), UInt64(1), UInt64(1)), 6
    )


def test_one_of_single_strategy_draws_through() raises:
    var opts = List[Integers]()
    opts.append(integers(3, 9))
    assert_equal(_draw_empty(one_of[Integers](opts^)), 3)
    var again = List[Integers]()
    again.append(integers(3, 9))
    assert_equal(
        _draw_replaying(one_of[Integers](again^), UInt64(0), UInt64(2)), 5
    )


def test_one_of_empty_raises() raises:
    var raised = False
    try:
        _ = one_of[Integers](List[Integers]())
    except:
        raised = True
    assert_true(raised, msg="empty strategies must raise")


def test_one_of_records_index_then_inner_choices() raises:
    var tc = _replaying(UInt64(1), UInt64(0))
    assert_equal(tc.draw(one_of[Integers](_ints())), 5)
    assert_equal(len(tc.choices), 2)
    assert_equal(tc.choices[0].kind, ChoiceKind.INTEGER)
    assert_equal(tc.choices[0].max_value, UInt64(1))
    assert_equal(len(tc.spans), 1)


def test_one_of2_empty_draws_first_branch() raises:
    var pair = one_of2[Integers, Just[Int]](integers(5, 10), just[Int](99))
    assert_equal(_draw_empty(pair.copy()), 5)


def test_one_of2_index_selects_hetero_branch() raises:
    var first = one_of2[Integers, Just[Int]](integers(5, 10), just[Int](99))
    assert_equal(_draw_replaying(first^, UInt64(0), UInt64(0)), 5)
    var second = one_of2[Integers, Just[Int]](integers(5, 10), just[Int](99))
    assert_equal(_draw_replaying(second^, UInt64(1)), 99)


def test_one_of2_second_branch_inner_choices() raises:
    var pair = one_of2[Just[Int], Integers](just[Int](42), integers(5, 10))
    assert_equal(_draw_replaying(pair.copy(), UInt64(0)), 42)
    assert_equal(_draw_replaying(pair.copy(), UInt64(1), UInt64(0)), 5)


def test_one_of2_nests_for_three_branches() raises:
    var inner = one_of2[Integers, Just[Int]](integers(0, 1), just[Int](99))
    var triple = one_of2[Just[Int], Integers](just[Int](-1), integers(7, 7))
    assert_equal(_draw_empty(triple.copy()), -1)
    assert_equal(_draw_replaying(inner.copy(), UInt64(1)), 99)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
