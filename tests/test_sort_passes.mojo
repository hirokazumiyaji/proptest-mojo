from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)
from proptest.shrink.span_passes import sort_spans, swap_adjacent_spans
from std.testing import TestSuite, assert_equal, assert_true

comptime _ELEM_LABEL = UInt64(0x6C697374456C656D)
comptime _OTHER_LABEL = UInt64(0x6F746865724C6162)


def _node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(100), Bool(False))


def _forced(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, UInt64(100), Bool(True))


def _seq(*values: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    for v in values:
        seq.append(_node(v))
    return seq^


def _span(start: Int, end: Int, depth: Int) -> Span:
    return Span(start, end, _ELEM_LABEL, depth, Bool(False))


def _labeled(start: Int, end: Int, label: UInt64, depth: Int) -> Span:
    return Span(start, end, label, depth, Bool(False))


def _width1_spans(n: Int) -> List[Span]:
    var spans = List[Span]()
    for i in range(n):
        spans.append(_span(i, i + 1, 1))
    return spans^


def _assert_values(seq: ChoiceSequence, *expected: UInt64) raises:
    var exp = _seq(*expected)
    assert_equal(len(seq), len(exp))
    for i in range(len(exp)):
        assert_equal(seq[i].value, exp[i].value)


def test_sort_spans_sorts_three_elements() raises:
    var seq = _seq(UInt64(3), UInt64(1), UInt64(2))
    var cands = sort_spans(seq.copy(), _width1_spans(3))
    assert_equal(len(cands), 1)
    _assert_values(cands[0].copy(), UInt64(1), UInt64(2), UInt64(3))
    assert_true(
        is_shortlex_smaller(cands[0].copy(), seq.copy()),
        msg="sorted candidate must be shortlex-smaller",
    )


def test_sort_spans_sorts_width2_list_elements() raises:
    # Flag/value element blocks mirroring strategies.collections ListOf.
    var seq = _seq(
        UInt64(1),
        UInt64(30),
        UInt64(1),
        UInt64(10),
        UInt64(1),
        UInt64(20),
        UInt64(0),
    )
    var spans = List[Span]()
    spans.append(_span(0, 2, 1))
    spans.append(_span(2, 4, 1))
    spans.append(_span(4, 6, 1))
    spans.append(Span(6, 7, _ELEM_LABEL, 1, Bool(True)))
    var cands = sort_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    _assert_values(
        cands[0].copy(),
        UInt64(1),
        UInt64(10),
        UInt64(1),
        UInt64(20),
        UInt64(1),
        UInt64(30),
        UInt64(0),
    )
    assert_true(
        is_shortlex_smaller(cands[0].copy(), seq.copy()),
        msg="sorted candidate must be shortlex-smaller",
    )


def test_sort_spans_skips_sorted_input() raises:
    var seq = _seq(UInt64(1), UInt64(2), UInt64(3))
    assert_equal(len(sort_spans(seq.copy(), _width1_spans(3))), 0)


def test_sort_spans_skips_discarded_empty_and_out_of_range() raises:
    var seq = _seq(UInt64(2), UInt64(1))
    var spans = List[Span]()
    spans.append(Span(0, 1, _ELEM_LABEL, 1, Bool(True)))
    spans.append(_span(1, 1, 1))
    spans.append(_span(5, 9, 1))
    assert_equal(len(sort_spans(seq.copy(), spans^)), 0)


def test_sort_spans_groups_by_label() raises:
    var seq = _seq(UInt64(2), UInt64(1), UInt64(4), UInt64(3))
    var spans = List[Span]()
    spans.append(_labeled(0, 1, _ELEM_LABEL, 1))
    spans.append(_labeled(1, 2, _OTHER_LABEL, 1))
    spans.append(_labeled(2, 3, _ELEM_LABEL, 1))
    spans.append(_labeled(3, 4, _ELEM_LABEL, 1))
    var cands = sort_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    _assert_values(cands[0].copy(), UInt64(2), UInt64(1), UInt64(3), UInt64(4))


def test_sort_spans_groups_by_depth() raises:
    var seq = _seq(UInt64(2), UInt64(1))
    var spans = List[Span]()
    spans.append(_labeled(0, 1, _ELEM_LABEL, 1))
    spans.append(_labeled(1, 2, _ELEM_LABEL, 0))
    assert_equal(len(sort_spans(seq.copy(), spans^)), 0)


def test_sort_spans_requires_adjacency() raises:
    # Same label and depth but a gap at index 1: two singleton runs.
    var seq = _seq(UInt64(3), UInt64(9), UInt64(1))
    var spans = List[Span]()
    spans.append(_span(0, 1, 1))
    spans.append(_span(2, 3, 1))
    assert_equal(len(sort_spans(seq.copy(), spans^)), 0)


def test_sort_spans_deepest_run_first() raises:
    var seq = _seq(UInt64(2), UInt64(1), UInt64(4), UInt64(3))
    var spans = List[Span]()
    spans.append(_labeled(0, 1, _ELEM_LABEL, 0))
    spans.append(_labeled(1, 2, _ELEM_LABEL, 0))
    spans.append(_labeled(2, 3, _ELEM_LABEL, 1))
    spans.append(_labeled(3, 4, _ELEM_LABEL, 1))
    var cands = sort_spans(seq.copy(), spans^)
    assert_equal(len(cands), 2)
    _assert_values(cands[0].copy(), UInt64(2), UInt64(1), UInt64(3), UInt64(4))
    _assert_values(cands[1].copy(), UInt64(1), UInt64(2), UInt64(4), UInt64(3))
    for i in range(len(cands)):
        assert_true(
            is_shortlex_smaller(cands[i].copy(), seq.copy()),
            msg="every sorted candidate must be shortlex-smaller",
        )


def test_sort_spans_moves_forced_nodes_whole() raises:
    var seq = ChoiceSequence()
    seq.append(_node(UInt64(3)))
    seq.append(_forced(UInt64(1)))
    seq.append(_node(UInt64(2)))
    var cands = sort_spans(seq.copy(), _width1_spans(3))
    assert_equal(len(cands), 1)
    _assert_values(cands[0].copy(), UInt64(1), UInt64(2), UInt64(3))
    assert_equal(cands[0][0].value, UInt64(1))
    assert_true(cands[0][0].forced, msg="forced flag must move with its block")
    assert_true(
        is_shortlex_smaller(cands[0].copy(), seq.copy()),
        msg="sorted candidate must be shortlex-smaller",
    )


def test_sort_spans_greedy_normalizes_order_independent_failure() raises:
    # An order-independent failure stays interesting under any reorder,
    # so the loop adopts the first candidate until the fixed point.
    var seq = _seq(UInt64(3), UInt64(1), UInt64(2))
    while True:
        var cands = sort_spans(seq.copy(), _width1_spans(len(seq)))
        if len(cands) == 0:
            break
        seq = cands[0].copy()
    _assert_values(seq.copy(), UInt64(1), UInt64(2), UInt64(3))


def test_swap_adjacent_spans_swaps_one_pair_downhill() raises:
    var seq = _seq(UInt64(3), UInt64(1), UInt64(2))
    var cands = swap_adjacent_spans(seq.copy(), _width1_spans(3))
    assert_equal(len(cands), 1)
    _assert_values(cands[0].copy(), UInt64(1), UInt64(3), UInt64(2))
    assert_true(
        is_shortlex_smaller(cands[0].copy(), seq.copy()),
        msg="every swap candidate must be shortlex-smaller",
    )


def test_swap_adjacent_spans_skips_sorted_and_equal() raises:
    var ordered = _seq(UInt64(1), UInt64(2), UInt64(3))
    assert_equal(len(swap_adjacent_spans(ordered.copy(), _width1_spans(3))), 0)
    var equal = _seq(UInt64(5), UInt64(5))
    assert_equal(len(swap_adjacent_spans(equal.copy(), _width1_spans(2))), 0)


def test_swap_adjacent_spans_swaps_width2_blocks() raises:
    var seq = _seq(UInt64(1), UInt64(30), UInt64(1), UInt64(10))
    var spans = List[Span]()
    spans.append(_span(0, 2, 1))
    spans.append(_span(2, 4, 1))
    var cands = swap_adjacent_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    _assert_values(
        cands[0].copy(), UInt64(1), UInt64(10), UInt64(1), UInt64(30)
    )


def test_swap_adjacent_spans_requires_same_label_and_depth() raises:
    var seq = _seq(UInt64(2), UInt64(1))
    var labels = List[Span]()
    labels.append(_labeled(0, 1, _ELEM_LABEL, 1))
    labels.append(_labeled(1, 2, _OTHER_LABEL, 1))
    assert_equal(len(swap_adjacent_spans(seq.copy(), labels^)), 0)
    var depths = List[Span]()
    depths.append(_labeled(0, 1, _ELEM_LABEL, 1))
    depths.append(_labeled(1, 2, _ELEM_LABEL, 0))
    assert_equal(len(swap_adjacent_spans(seq.copy(), depths^)), 0)


def test_swap_adjacent_spans_skips_discarded() raises:
    var seq = _seq(UInt64(2), UInt64(1))
    var spans = List[Span]()
    spans.append(_span(0, 1, 1))
    spans.append(Span(1, 2, _ELEM_LABEL, 1, Bool(True)))
    assert_equal(len(swap_adjacent_spans(seq.copy(), spans^)), 0)


def test_swap_adjacent_spans_bubble_sorts_order_independent_failure() raises:
    # Repeated downhill swaps converge like bubble sort when any
    # permutation stays interesting.
    var seq = _seq(UInt64(3), UInt64(2), UInt64(1))
    while True:
        var cands = swap_adjacent_spans(seq.copy(), _width1_spans(len(seq)))
        if len(cands) == 0:
            break
        seq = cands[0].copy()
    _assert_values(seq.copy(), UInt64(1), UInt64(2), UInt64(3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
