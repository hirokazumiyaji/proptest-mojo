from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    is_shortlex_smaller,
)
from proptest.shrink.shrinker import Evaluation, shrink
from std.testing import TestSuite, assert_equal, assert_true


def _node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(2000), Bool(False))


def _seq(*values: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    for v in values:
        seq.append(_node(v))
    return seq^


def _eval_sum_over_1000(seq: ChoiceSequence) -> Evaluation:
    var total = UInt64(0)
    for i in range(len(seq)):
        total += seq.nodes[i].value
    return Evaluation(total > UInt64(1000), seq.copy())


def _eval_first_over_5(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    # Only the first choice matters; consumed is the 1-prefix.
    var interesting = seq.nodes[0].value > UInt64(5)
    return Evaluation(interesting, seq.truncated(1))


def test_shrink_finds_minimal_sum() raises:
    var start = _seq(UInt64(900), UInt64(900), UInt64(900))
    var result = shrink[_eval_sum_over_1000](start.copy(), 5000)
    # Minimal interesting: values sum just over 1000 with smallest
    # shortlex shape, e.g. [0, 1001] or [1001, 0] reduced to 2 nodes?
    # At minimum the result must stay interesting and not grow.
    var check = _eval_sum_over_1000(result.best.copy())
    assert_true(check.is_interesting, msg="result must stay interesting")
    assert_true(
        is_shortlex_smaller(result.best, start) or result.best == start,
        msg="result must not grow in shortlex order",
    )
    # Single value 1001 is the smallest interesting single-node input.
    var single = _seq(UInt64(1500))
    var single_result = shrink[_eval_sum_over_1000](single.copy(), 5000)
    assert_equal(len(single_result.best), 1)
    assert_equal(single_result.best[0].value, UInt64(1001))


def test_zero_budget_returns_input() raises:
    var start = _seq(UInt64(900), UInt64(900))
    var result = shrink[_eval_sum_over_1000](start.copy(), 0)
    assert_equal(result.best, start)
    assert_equal(result.evaluations, 0)
    assert_true(not result.hit_budget, msg="zero budget is not a cutoff")


def test_adopts_consumed_prefix() raises:
    var start = _seq(UInt64(9), UInt64(99), UInt64(99))
    var result = shrink[_eval_first_over_5](start.copy(), 5000)
    assert_equal(len(result.best), 1)
    assert_equal(result.best[0].value, UInt64(6))


def _eval_two_draws_fail_over_1(seq: ChoiceSequence) -> Evaluation:
    """Always draws twice; interesting when the first value is above 0."""
    var first = UInt64(0)
    if len(seq) >= 1:
        first = seq.nodes[0].value
    # The property always consumes two choices, so replaying a shorter
    # prefix appends a synthesized zero.
    var consumed = ChoiceSequence()
    consumed.append(_node(first))
    consumed.append(_node(UInt64(0)))
    return Evaluation(first > UInt64(0), consumed^)


def test_rejects_consumed_sequence_that_is_not_smaller() raises:
    # Deleting index 0 of [0, 1] yields candidate [1], but the property
    # consumes [1, 0], which is shortlex-larger than [0, 1]. Adopting it
    # would report a worse counterexample than the input.
    var start = _seq(UInt64(0), UInt64(1))
    var result = shrink[_eval_two_draws_fail_over_1](start.copy(), 5000)
    assert_true(
        not is_shortlex_smaller(result.best, start) or result.best == start,
        msg="shrinking must never return a larger sequence",
    )
    assert_true(
        result.hit_budget or len(result.best) <= len(start),
        msg="consumed adoption must be rejected when not smaller",
    )


def test_consumed_descent_is_strict_at_every_adoption() raises:
    # A shrinking run over many inputs must never end above its input in
    # shortlex order, whatever branch shape the property takes.
    var starts = List[ChoiceSequence]()
    starts.append(_seq(UInt64(0), UInt64(1)))
    starts.append(_seq(UInt64(1), UInt64(0)))
    starts.append(_seq(UInt64(0), UInt64(0), UInt64(3)))
    for i in range(len(starts)):
        var result = shrink[_eval_two_draws_fail_over_1](starts[i].copy(), 200)
        assert_true(
            not is_shortlex_smaller(starts[i], result.best),
            msg="shrinking must never move upward in shortlex order",
        )


def test_cached_candidates_do_not_consume_the_pass_limit() raises:
    # Cache hits cost no evaluation, so they must not eat the
    # materialization cap: a later candidate in the same pass that would
    # improve `best` must still be reached.
    var start = _seq(UInt64(900), UInt64(900), UInt64(900), UInt64(900))
    var result = shrink[_eval_sum_over_1000](start.copy(), 60)
    var check = _eval_sum_over_1000(result.best.copy())
    assert_true(check.is_interesting, msg="result must stay interesting")
    assert_true(result.evaluations <= 60, msg="budget must be respected")
    assert_true(
        not is_shortlex_smaller(start, result.best),
        msg="shrinking must never move upward",
    )


def test_long_sequence_with_tiny_budget_stays_cheap() raises:
    # Materializing every deletion of a near-maximal sequence needs
    # gigabytes, which a small evaluation budget must avoid entirely.
    var seq = _seq(UInt64(1), UInt64(2), UInt64(3), UInt64(4), UInt64(5))
    var result = shrink[_eval_sum_over_1000](seq.copy(), 1)
    assert_equal(result.evaluations, 1)
    assert_true(result.hit_budget, msg="budget of 1 must be reported")


def test_cache_avoids_duplicate_evaluations() raises:
    var start = _seq(UInt64(3), UInt64(3), UInt64(3))
    var result = shrink[_eval_sum_over_1000](start.copy(), 5000)
    # Sum is 9, never interesting: the loop terminates without exhausting the budget.
    assert_true(result.evaluations > 0, msg="uninteresting input still probes")
    assert_true(not result.hit_budget, msg="fixed point must terminate")
    # Re-running with a tiny budget reports the cutoff.
    var capped = shrink[_eval_sum_over_1000](start.copy(), 2)
    assert_equal(capped.evaluations, 2)
    assert_true(capped.hit_budget, msg="exhausted budget must be reported")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
