from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
    shortlex_compare,
)
from proptest.shrink.adaptive import lower_duplicates, redistribute
from proptest.shrink.shrinker import Evaluation, shrink
from std.testing import TestSuite, assert_equal, assert_true


def _node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(2000), Bool(False))


def _forced(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(2000), Bool(True))


def _seq(*values: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    for v in values:
        seq.append(_node(v))
    return seq^


def _sum_over_10(seq: ChoiceSequence) -> Bool:
    var total = UInt64(0)
    for i in range(len(seq)):
        total += seq.nodes[i].value
    return total > UInt64(10)


def _equal_and_over_100(seq: ChoiceSequence) -> Bool:
    if len(seq) < 2:
        return False
    var x = seq.nodes[0].value
    var y = seq.nodes[1].value
    return x == y and x > UInt64(100)


def test_redistribute_moves_value_right() raises:
    var seq = _seq(UInt64(5), UInt64(7))
    var best = redistribute[_sum_over_10](seq.copy())
    assert_equal(len(best), 2)
    assert_equal(best[0].value, UInt64(0))
    assert_equal(best[1].value, UInt64(11))
    assert_true(
        _sum_over_10(best.copy()), msg="redistributed input stays interesting"
    )
    assert_true(
        is_shortlex_smaller(best.copy(), seq.copy()),
        msg="redistribution must move down in shortlex order",
    )


def test_redistribute_from_balanced_start() raises:
    var seq = _seq(UInt64(8), UInt64(8))
    var best = redistribute[_sum_over_10](seq.copy())
    assert_equal(best[0].value, UInt64(0))
    assert_equal(best[1].value, UInt64(11))
    assert_true(_sum_over_10(best.copy()), msg="result stays interesting")


def test_redistribute_skips_forced() raises:
    var seq = ChoiceSequence()
    seq.append(_forced(UInt64(5)))
    seq.append(_node(UInt64(7)))
    var best = redistribute[_sum_over_10](seq.copy())
    assert_true(
        best.copy() == seq.copy(), msg="forced donor leaves nothing to move"
    )
    assert_true(best[0].forced, msg="forced flag must survive")
    assert_equal(best[0].value, UInt64(5))


def test_redistribute_keeps_uninteresting_input() raises:
    var seq = _seq(UInt64(1), UInt64(2))
    var best = redistribute[_sum_over_10](seq.copy())
    assert_true(
        best.copy() == seq.copy(), msg="without signal nothing may change"
    )


def test_redistribute_handles_trivial_inputs() raises:
    var empty = ChoiceSequence()
    assert_equal(len(redistribute[_sum_over_10](empty.copy())), 0)
    var one = _seq(UInt64(50))
    var best_one = redistribute[_sum_over_10](one.copy())
    assert_true(
        best_one.copy() == one.copy(), msg="single choice has no pair to move"
    )
    var zeros = _seq(UInt64(0), UInt64(0))
    var best_zeros = redistribute[_sum_over_10](zeros.copy())
    assert_true(
        best_zeros.copy() == zeros.copy(), msg="zeros leave nothing to move"
    )


def test_lower_duplicates_finds_equal_minimum() raises:
    var seq = _seq(UInt64(500), UInt64(500))
    var best = lower_duplicates[_equal_and_over_100](seq.copy())
    assert_equal(len(best), 2)
    assert_equal(best[0].value, UInt64(101))
    assert_equal(best[1].value, UInt64(101))
    assert_true(
        _equal_and_over_100(best.copy()),
        msg="lowered duplicates stay interesting",
    )
    assert_true(
        shortlex_compare(best.copy(), seq.copy()) < 0,
        msg="lowering must move down in shortlex order",
    )


def test_lower_duplicates_handles_three_way_group() raises:
    var seq = _seq(UInt64(500), UInt64(500), UInt64(500))
    var best = lower_duplicates[_equal_and_over_100](seq.copy())
    assert_equal(best[0].value, UInt64(101))
    assert_equal(best[1].value, UInt64(101))
    assert_equal(best[2].value, UInt64(101))


def test_lower_duplicates_skips_forced() raises:
    var seq = ChoiceSequence()
    seq.append(_forced(UInt64(500)))
    seq.append(_node(UInt64(500)))
    var best = lower_duplicates[_equal_and_over_100](seq.copy())
    assert_true(
        best.copy() == seq.copy(),
        msg="forced member breaks the duplicate group",
    )
    assert_true(best[0].forced, msg="forced flag must survive")


def test_lower_duplicates_keeps_uninteresting_input() raises:
    var seq = _seq(UInt64(1), UInt64(2))
    var best = lower_duplicates[_equal_and_over_100](seq.copy())
    assert_true(
        best.copy() == seq.copy(), msg="without signal nothing may change"
    )


def test_lower_duplicates_handles_trivial_inputs() raises:
    var empty = ChoiceSequence()
    assert_equal(len(lower_duplicates[_equal_and_over_100](empty.copy())), 0)
    var one = _seq(UInt64(500))
    assert_true(
        lower_duplicates[_equal_and_over_100](one.copy()) == one.copy(),
        msg="single choice has no duplicate to lower",
    )
    var zeros = _seq(UInt64(0), UInt64(0))
    assert_true(
        lower_duplicates[_equal_and_over_100](zeros.copy()) == zeros.copy(),
        msg="zeros leave nothing to lower",
    )


def _sum_over_10_pair(seq: ChoiceSequence) -> Bool:
    if len(seq) != 2:
        return False
    return seq.nodes[0].value + seq.nodes[1].value > UInt64(10)


def _sum_over_10_eval(seq: ChoiceSequence) -> Evaluation:
    return Evaluation(_sum_over_10_pair(seq), seq.copy(), List[Span]())


def _equal_and_over_5_pair(seq: ChoiceSequence) -> Bool:
    if len(seq) != 2:
        return False
    var x = seq.nodes[0].value
    var y = seq.nodes[1].value
    return x == y and x > UInt64(5)


def _equal_and_over_5_eval(seq: ChoiceSequence) -> Evaluation:
    return Evaluation(_equal_and_over_5_pair(seq), seq.copy(), List[Span]())


def test_shrink_loop_invokes_redistribute() raises:
    var seq = _seq(UInt64(5), UInt64(7))
    var res = shrink[_sum_over_10_eval](seq.copy(), List[Span](), 200)
    assert_equal(res.best[0].value, UInt64(0))
    assert_equal(res.best[1].value, UInt64(11))


def test_shrink_loop_invokes_lower_duplicates() raises:
    var seq = _seq(UInt64(20), UInt64(20))
    var res = shrink[_equal_and_over_5_eval](seq.copy(), List[Span](), 200)
    assert_equal(res.best[0].value, UInt64(6))
    assert_equal(res.best[1].value, UInt64(6))


def test_shrink_redistribute_respects_max_evaluations() raises:
    var seq = _seq(UInt64(5), UInt64(7))
    for budget in range(1, 10):
        var res = shrink[_sum_over_10_eval](seq.copy(), List[Span](), budget)
        assert_true(res.evaluations <= budget)
        if res.evaluations == budget:
            assert_true(res.hit_budget)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
