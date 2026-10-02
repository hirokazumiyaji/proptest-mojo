from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    is_shortlex_smaller,
    shortlex_compare,
)
from proptest.shrink.passes import (
    delete_chunks,
    minimize_individual,
    zero_chunks,
)
from std.testing import TestSuite, assert_equal, assert_true


def _node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(100), Bool(False))


def _forced(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(100), Bool(True))


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


def _first_over_100(seq: ChoiceSequence) -> Bool:
    return seq.nodes[0].value > UInt64(100)


def _second_nonzero(seq: ChoiceSequence) -> Bool:
    return seq.nodes[1].value != UInt64(0)


def _never_interesting(seq: ChoiceSequence) -> Bool:
    return False


def test_delete_chunks_lengths_and_order() raises:
    var seq = _seq(
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(4),
        UInt64(5),
        UInt64(6),
        UInt64(7),
        UInt64(8),
        UInt64(9),
        UInt64(10),
    )
    var cands = delete_chunks(seq.copy())
    assert_equal(len(cands), 3 + 7 + 9 + 10)
    for i in range(len(cands) - 1):
        assert_true(
            len(cands[i]) <= len(cands[i + 1]),
            msg="delete_chunks must emit simplest-first",
        )
    assert_equal(len(cands[0]), 2)
    assert_equal(cands[0][0].value, UInt64(9))
    assert_equal(cands[0][1].value, UInt64(10))
    assert_equal(len(cands[len(cands) - 1]), 9)


def test_delete_chunks_skips_empty_results() raises:
    var one = _seq(UInt64(5))
    assert_equal(len(delete_chunks(one.copy())), 0)
    var two = _seq(UInt64(5), UInt64(6))
    var cands = delete_chunks(two.copy())
    assert_equal(len(cands), 2)
    assert_equal(cands[0][0].value, UInt64(6))
    assert_equal(cands[1][0].value, UInt64(5))


def test_delete_chunks_all_shortlex_smaller() raises:
    var seq = ChoiceSequence()
    seq.append(_node(UInt64(3)))
    seq.append(_forced(UInt64(9)))
    seq.append(_node(UInt64(0)))
    seq.append(_node(UInt64(4)))
    var cands = delete_chunks(seq.copy())
    assert_true(len(cands) > 0, msg="non-empty input must yield candidates")
    for i in range(len(cands)):
        assert_true(
            is_shortlex_smaller(cands[i].copy(), seq.copy()),
            msg="every deletion must be shortlex-smaller",
        )
        assert_true(
            len(cands[i]) < len(seq), msg="deletion must shorten the input"
        )
        var forced_count = 0
        for j in range(len(cands[i])):
            if cands[i][j].forced:
                assert_equal(cands[i][j].value, UInt64(9))
                forced_count += 1
        assert_equal(
            forced_count,
            1,
            msg="delete_chunks must preserve every forced node",
        )


def test_zero_chunks_zeroes_blocks_simplest_first() raises:
    var seq = ChoiceSequence()
    for _ in range(10):
        seq.append(_node(UInt64(7)))
    var cands = zero_chunks(seq.copy())
    assert_equal(len(cands), 3 + 7 + 9 + 10)
    for i in range(8):
        assert_equal(cands[0][i].value, UInt64(0))
    assert_equal(cands[0][8].value, UInt64(7))
    assert_equal(cands[0][9].value, UInt64(7))


def test_zero_chunks_skips_unchanged() raises:
    var zeros = _seq(UInt64(0), UInt64(0))
    assert_equal(len(zero_chunks(zeros.copy())), 0)
    var mixed = _seq(UInt64(5), UInt64(0), UInt64(3))
    var cands = zero_chunks(mixed.copy())
    assert_equal(len(cands), 4)
    for i in range(len(cands)):
        assert_true(
            is_shortlex_smaller(cands[i].copy(), mixed.copy()),
            msg="every zeroing must be shortlex-smaller",
        )
        assert_true(
            cands[i].copy() != mixed.copy(),
            msg="no candidate may equal the input",
        )


def test_zero_chunks_preserves_forced() raises:
    var seq = ChoiceSequence()
    seq.append(_node(UInt64(7)))
    seq.append(_forced(UInt64(9)))
    seq.append(_node(UInt64(5)))
    var cands = zero_chunks(seq.copy())
    assert_true(len(cands) > 0, msg="non-zero input must yield candidates")
    for i in range(len(cands)):
        assert_equal(len(cands[i]), len(seq))
        assert_equal(cands[i][1].value, UInt64(9))
        assert_true(cands[i][1].forced, msg="forced flag must survive")
        assert_true(
            is_shortlex_smaller(cands[i].copy(), seq.copy()),
            msg="every zeroing must be shortlex-smaller",
        )


def test_delete_chunks_respects_limit() raises:
    var seq = _seq(
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(4),
        UInt64(5),
        UInt64(6),
        UInt64(7),
        UInt64(8),
        UInt64(9),
        UInt64(10),
    )
    var all = delete_chunks(seq.copy())
    assert_true(len(all) > 2, msg="input yields several candidates")
    # The budgeted form must be a prefix of the full form, so the shrink
    # loop sees the same candidates in the same order.
    var capped = delete_chunks(seq.copy(), 2)
    assert_equal(len(capped), 2)
    assert_equal(capped[0], all[0])
    assert_equal(capped[1], all[1])
    assert_equal(len(delete_chunks(seq.copy(), 0)), 0)


def test_zero_chunks_respects_limit() raises:
    var seq = _seq(
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
        UInt64(5),
    )
    var all = zero_chunks(seq.copy())
    assert_true(len(all) > 2, msg="input yields several candidates")
    var capped = zero_chunks(seq.copy(), 3)
    assert_equal(len(capped), 3)
    for i in range(3):
        assert_equal(capped[i], all[i])
    assert_equal(len(zero_chunks(seq.copy(), 0)), 0)


def test_minimize_individual_binary_search() raises:
    var seq = _seq(UInt64(1000))
    var best = minimize_individual[_first_over_100](seq.copy())
    assert_equal(len(best), 1)
    assert_equal(best[0].value, UInt64(101))
    assert_true(
        _first_over_100(best.copy()), msg="minimized input stays interesting"
    )
    assert_true(
        shortlex_compare(best.copy(), seq.copy()) <= 0,
        msg="minimize must not move up in shortlex order",
    )


def test_minimize_individual_balances_two_choices() raises:
    var seq = _seq(UInt64(5), UInt64(7))
    var best = minimize_individual[_sum_over_10](seq.copy())
    assert_equal(best[0].value, UInt64(4))
    assert_equal(best[1].value, UInt64(7))
    assert_true(
        _sum_over_10(best.copy()), msg="minimized input stays interesting"
    )


def test_minimize_individual_skips_forced() raises:
    var seq = ChoiceSequence()
    seq.append(_forced(UInt64(1000)))
    seq.append(_node(UInt64(5)))
    var best = minimize_individual[_second_nonzero](seq.copy())
    assert_equal(best[0].value, UInt64(1000))
    assert_true(best[0].forced, msg="forced flag must survive")
    assert_equal(best[1].value, UInt64(1))
    assert_true(
        _second_nonzero(best.copy()), msg="minimized input stays interesting"
    )


def test_minimize_individual_keeps_uninteresting_input() raises:
    var seq = _seq(UInt64(5), UInt64(7))
    var best = minimize_individual[_never_interesting](seq.copy())
    assert_true(
        best.copy() == seq.copy(), msg="without signal nothing may change"
    )


def test_minimize_individual_handles_trivial_inputs() raises:
    var empty = ChoiceSequence()
    assert_equal(len(minimize_individual[_sum_over_10](empty.copy())), 0)
    var zeros = _seq(UInt64(0), UInt64(0))
    var best = minimize_individual[_sum_over_10](zeros.copy())
    assert_true(
        best.copy() == zeros.copy(), msg="zeros leave nothing to minimize"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
