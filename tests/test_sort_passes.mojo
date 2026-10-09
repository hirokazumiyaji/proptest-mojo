from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)
from proptest.encoding import decode_sequence
from proptest.shrink.span_passes import sort_spans, swap_adjacent_spans
from proptest.strategies.collections import lists
from proptest.strategies.combinators import filter
from proptest.strategies.primitives import booleans, integers, just
from proptest.strategies.tuples import optionals, tuples
from proptest.testcase import TestCase
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


def test_swap_adjacent_spans_unequal_width_prefix_blocks() raises:
    # Proper-prefix siblings: compare concatenations, not the blocks alone.
    var seq = _seq(UInt64(1), UInt64(1), UInt64(0))
    var spans = List[Span]()
    spans.append(_span(0, 1, 1))
    spans.append(_span(1, 3, 1))
    var cands = swap_adjacent_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    _assert_values(cands[0].copy(), UInt64(1), UInt64(0), UInt64(1))


def test_sort_spans_offset_skips_only_eligible_candidates() raises:
    # First gap-separated run is already sorted (no candidate); the second
    # is unsorted. offset=1 must be exhausted, not replay the only candidate.
    var seq = _seq(
        UInt64(1),
        UInt64(2),
        UInt64(0),
        UInt64(2),
        UInt64(1),
    )
    var spans = List[Span]()
    spans.append(_span(0, 1, 1))
    spans.append(_span(1, 2, 1))
    spans.append(_span(3, 4, 1))
    spans.append(_span(4, 5, 1))
    var all = sort_spans(seq.copy(), spans.copy())
    assert_equal(len(all), 1)
    _assert_values(
        all[0].copy(), UInt64(1), UInt64(2), UInt64(0), UInt64(1), UInt64(2)
    )
    var page = sort_spans(seq.copy(), spans.copy(), 1, 1)
    assert_equal(len(page), 0)


def test_swap_adjacent_spans_pages_large_sibling_runs() raises:
    # A descending run of n siblings yields n-1 downhill swaps; without a
    # limit that eagerly copies every full sequence.
    var n = 200
    var seq = ChoiceSequence()
    for i in range(n):
        seq.append(_node(UInt64(n - i)))
    var all = swap_adjacent_spans(seq.copy(), _width1_spans(n))
    assert_equal(len(all), n - 1)
    var page = swap_adjacent_spans(seq.copy(), _width1_spans(n), 1, 0)
    assert_equal(len(page), 1)
    var next_page = swap_adjacent_spans(seq.copy(), _width1_spans(n), 1, 1)
    assert_equal(len(next_page), 1)
    assert_true(
        page[0].values() != next_page[0].values(),
        msg="offset must advance to a different swap candidate",
    )


def test_sort_spans_pages_independent_runs() raises:
    # Many length-2 unsorted runs separated by gaps: unbounded sort would
    # copy one full sequence per run before the first evaluation.
    var runs = 100
    var seq = ChoiceSequence()
    var spans = List[Span]()
    for r in range(runs):
        var base = r * 3
        seq.append(_node(UInt64(2)))
        seq.append(_node(UInt64(1)))
        seq.append(_node(UInt64(0)))
        spans.append(_span(base, base + 1, 1))
        spans.append(_span(base + 1, base + 2, 1))
    var all = sort_spans(seq.copy(), spans.copy())
    assert_equal(len(all), runs)
    var page = sort_spans(seq.copy(), spans.copy(), 3, 0)
    assert_equal(len(page), 3)
    var next_page = sort_spans(seq.copy(), spans.copy(), 3, 3)
    assert_equal(len(next_page), 3)
    assert_true(
        page[0].values() != next_page[0].values(),
        msg="offset must page through independent sort candidates",
    )


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


def test_sort_spans_uses_recorded_list_enclosing_span() raises:
    # Real TestCase.draw recordings interleave the enclosing list span
    # between element siblings in global (start, end) order.
    var tc = TestCase.replaying(decode_sequence("AQMBAQA="))
    var drawn = tc.draw(lists(integers(0, 9), min_size=2, max_size=2))
    assert_equal(len(drawn), 2)
    assert_equal(drawn[0], 3)
    assert_equal(drawn[1], 1)
    var cands = sort_spans(tc.choices.copy(), tc.spans.copy())
    assert_equal(len(cands), 1)
    _assert_values(
        cands[0].copy(), UInt64(1), UInt64(1), UInt64(1), UInt64(3), UInt64(0)
    )
    var replay = TestCase.replaying(cands[0].copy())
    var sorted_list = replay.draw(lists(integers(0, 9), min_size=2, max_size=2))
    assert_equal(sorted_list[0], 1)
    assert_equal(sorted_list[1], 3)


def test_swap_adjacent_spans_uses_recorded_list_enclosing_span() raises:
    var tc = TestCase.replaying(decode_sequence("AQMBAQA="))
    _ = tc.draw(lists(integers(0, 9), min_size=2, max_size=2))
    var cands = swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())
    assert_equal(len(cands), 1)
    _assert_values(
        cands[0].copy(), UInt64(1), UInt64(1), UInt64(1), UInt64(3), UInt64(0)
    )


def _nested_list_of_pairs_prefix() -> ChoiceSequence:
    var prefix = ChoiceSequence()
    # List element 0: forced continue, tuple (3, 0)
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(1), Bool(True))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(3), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(9), Bool(False))
    )
    # List element 1: forced continue, tuple (1, 0)
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(1), Bool(True))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(9), Bool(False))
    )
    # Trailing stop
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(1), Bool(True))
    )
    return prefix^


def test_sort_spans_uses_recorded_nested_collection_spans() raises:
    # Nested tuple field spans sit between outer list element siblings in
    # global (start, end) order and must not split the outer sibling run.
    # Deepest-first emission may also sort nested fields; one candidate must
    # reorder the outer list elements.
    var strategy = lists(
        tuples(integers(0, 9), integers(0, 9)), min_size=2, max_size=2
    )
    var tc = TestCase.replaying(_nested_list_of_pairs_prefix())
    var drawn = tc.draw(strategy)
    assert_equal(drawn[0][0], 3)
    assert_equal(drawn[1][0], 1)
    var cands = sort_spans(tc.choices.copy(), tc.spans.copy())
    assert_true(len(cands) >= 1, msg="nested recording must yield candidates")
    var found_outer = False
    for i in range(len(cands)):
        var replay = TestCase.replaying(cands[i].copy())
        var sorted_list = replay.draw(strategy)
        if sorted_list[0][0] == 1 and sorted_list[1][0] == 3:
            found_outer = True
            break
    assert_true(
        found_outer,
        msg="outer list siblings must sort despite nested field spans",
    )


def test_swap_adjacent_spans_uses_recorded_nested_collection_spans() raises:
    var strategy = lists(
        tuples(integers(0, 9), integers(0, 9)), min_size=2, max_size=2
    )
    var tc = TestCase.replaying(_nested_list_of_pairs_prefix())
    _ = tc.draw(strategy)
    var cands = swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())
    assert_true(len(cands) >= 1, msg="nested recording must yield swaps")
    var found_outer = False
    for i in range(len(cands)):
        var replay = TestCase.replaying(cands[i].copy())
        var swapped = replay.draw(strategy)
        if swapped[0][0] == 1 and swapped[1][0] == 3:
            found_outer = True
            break
    assert_true(
        found_outer,
        msg="outer list siblings must swap despite nested field spans",
    )


def test_sibling_runs_keep_equal_range_ancestors() raises:
    # Nested equal-range wrappers under different parents must not join.
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(3), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(9), Bool(False))
    )
    var strategy = tuples(
        tuples(just(0), integers(0, 9)),
        tuples(integers(0, 9), just(0), just(0)),
    )
    var tc = TestCase.replaying(prefix^)
    _ = tc.draw(strategy)
    assert_equal(len(sort_spans(tc.choices.copy(), tc.spans.copy())), 0)
    assert_equal(
        len(swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())), 0
    )


def test_equal_range_top_level_wrappers_remain_reorderable() raises:
    # Two top-level `tuples(just, int)` draws share each wrapper's range with
    # its child; the wrappers must still form a sibling run.
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(3), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(9), Bool(False))
    )
    var strategy = tuples(just(0), integers(0, 9))
    var tc = TestCase.replaying(prefix^)
    _ = tc.draw(strategy)
    _ = tc.draw(strategy)
    var sorts = sort_spans(tc.choices.copy(), tc.spans.copy())
    assert_equal(len(sorts), 1)
    _assert_values(sorts[0].copy(), UInt64(1), UInt64(3))
    var swaps = swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())
    assert_equal(len(swaps), 1)
    _assert_values(swaps[0].copy(), UInt64(1), UInt64(3))


def _pair_at_least_four(value: Tuple[Int, Int]) -> Bool:
    return value[0] >= 4 and value[1] >= 4


def test_discarded_filter_parents_separate_sibling_runs() raises:
    # Rejected filter attempts keep discarded parent spans; their children
    # must not reorder across those attempt boundaries.
    var prefix = ChoiceSequence()
    for v in [
        UInt64(9),
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(4),
        UInt64(5),
    ]:
        prefix.append(ChoiceNode(ChoiceKind.INTEGER, v, UInt64(9), Bool(False)))
    var tc = TestCase.replaying(prefix^)
    var drawn = tc.draw(
        filter[_pair_at_least_four](tuples(integers(0, 9), integers(0, 9)))
    )
    assert_equal(drawn[0], 4)
    assert_equal(drawn[1], 5)
    var bad = List[UInt64]()
    bad.append(UInt64(1))
    bad.append(UInt64(2))
    bad.append(UInt64(3))
    bad.append(UInt64(9))
    bad.append(UInt64(4))
    bad.append(UInt64(5))
    var sorts = sort_spans(tc.choices.copy(), tc.spans.copy())
    for i in range(len(sorts)):
        assert_true(
            sorts[i].values() != bad,
            msg="must not reorder across discarded filter attempts",
        )


def test_sibling_runs_require_shared_immediate_parent() raises:
    # Choice-adjacent optionals under different tuple parents must not form
    # one sibling run even when they share label and depth.
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(0), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(9), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(9), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(0), UInt64(1), Bool(False))
    )
    var strategy = tuples(
        tuples(booleans(), optionals(integers(0, 9))),
        tuples(optionals(integers(0, 9)), booleans()),
    )
    var tc = TestCase.replaying(prefix^)
    _ = tc.draw(strategy)
    assert_equal(len(sort_spans(tc.choices.copy(), tc.spans.copy())), 0)
    assert_equal(
        len(swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())), 0
    )


def test_sibling_runs_keep_used_boundary_separators() raises:
    # After a deeper boolean run marks `[3,4)`, that span must still separate
    # tuple blocks under different parents so they are not joined.
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(20), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(0), UInt64(1), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(9), UInt64(20), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(0), UInt64(20), Bool(False))
    )
    var strategy = tuples(
        tuples(integers(0, 20), tuples(booleans(), booleans())),
        tuples(tuples(booleans(), integers(0, 20)), integers(0, 20)),
    )
    var tc = TestCase.replaying(prefix^)
    _ = tc.draw(strategy)
    var bad = List[UInt64]()
    bad.append(UInt64(0))
    bad.append(UInt64(0))
    bad.append(UInt64(9))
    bad.append(UInt64(1))
    bad.append(UInt64(1))
    bad.append(UInt64(0))
    var sorts = sort_spans(tc.choices.copy(), tc.spans.copy())
    for i in range(len(sorts)):
        assert_true(
            sorts[i].values() != bad,
            msg="must not splice cross-parent tuple spans",
        )
    var swaps = swap_adjacent_spans(tc.choices.copy(), tc.spans.copy())
    for i in range(len(swaps)):
        assert_true(
            swaps[i].values() != bad,
            msg="must not swap cross-parent tuple spans",
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
