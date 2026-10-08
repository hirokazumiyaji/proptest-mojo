from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)
from proptest.shrink.span_passes import delete_spans, zero_spans
from std.testing import TestSuite, assert_equal, assert_true

comptime _ELEM_LABEL = UInt64(0x6C697374456C656D)


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


def _list_spans() -> List[Span]:
    # Three width-2 elements plus the discarded trailing break span,
    # mirroring strategies.collections ListOf recording.
    var spans = List[Span]()
    spans.append(_span(0, 2, 1))
    spans.append(_span(2, 4, 1))
    spans.append(_span(4, 6, 1))
    spans.append(Span(6, 7, _ELEM_LABEL, 1, Bool(True)))
    return spans^


def _elem_sum(seq: ChoiceSequence) -> UInt64:
    # Element values sit at odd indices of a flag/value list sequence.
    var total = UInt64(0)
    for i in range(1, len(seq) - 1, 2):
        total += seq.nodes[i].value
    return total


def _width2_spans(n: Int) -> List[Span]:
    # Fresh element spans for the current sequence length, as a runner
    # would re-record after adopting a candidate.
    var spans = List[Span]()
    var i = 0
    while i + 2 <= n - 1:
        spans.append(_span(i, i + 2, 1))
        i += 2
    return spans^


def test_delete_spans_removes_each_element() raises:
    var seq = _seq(
        UInt64(1),
        UInt64(5),
        UInt64(1),
        UInt64(99),
        UInt64(1),
        UInt64(7),
        UInt64(0),
    )
    var cands = delete_spans(seq.copy(), _list_spans())
    assert_equal(len(cands), 3)
    for i in range(len(cands)):
        assert_equal(len(cands[i]), 5)
        assert_true(
            is_shortlex_smaller(cands[i].copy(), seq.copy()),
            msg="every span deletion must be shortlex-smaller",
        )
    assert_equal(cands[0][1].value, UInt64(99))
    assert_equal(cands[1][1].value, UInt64(5))
    assert_equal(cands[1][3].value, UInt64(7))
    assert_equal(cands[2][1].value, UInt64(5))
    assert_equal(cands[2][3].value, UInt64(99))


def test_delete_spans_deepest_first() raises:
    var seq = _seq(
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(4),
        UInt64(5),
        UInt64(6),
    )
    var spans = List[Span]()
    spans.append(_span(0, 4, 0))
    spans.append(_span(0, 2, 1))
    spans.append(_span(2, 4, 1))
    spans.append(_span(4, 6, 0))
    var cands = delete_spans(seq.copy(), spans^)
    assert_equal(len(cands), 4)
    assert_equal(len(cands[0]), 4)
    assert_equal(cands[0][0].value, UInt64(3))
    assert_equal(len(cands[1]), 4)
    assert_equal(cands[1][0].value, UInt64(1))
    assert_equal(len(cands[2]), 2)
    assert_equal(cands[2][0].value, UInt64(5))
    assert_equal(len(cands[3]), 4)
    assert_equal(cands[3][0].value, UInt64(1))


def test_delete_spans_skips_discarded_and_empty() raises:
    var seq = _seq(UInt64(4), UInt64(5))
    var spans = List[Span]()
    spans.append(Span(0, 2, _ELEM_LABEL, 1, Bool(True)))
    spans.append(_span(1, 1, 1))
    assert_equal(len(delete_spans(seq.copy(), spans^)), 0)


def test_delete_spans_deduplicates_ranges() raises:
    var seq = _seq(UInt64(4), UInt64(5), UInt64(6))
    var spans = List[Span]()
    spans.append(_span(0, 2, 0))
    spans.append(_span(0, 2, 1))
    var cands = delete_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    assert_equal(len(cands[0]), 1)
    assert_equal(cands[0][0].value, UInt64(6))


def test_delete_spans_skips_empty_result() raises:
    var seq = _seq(UInt64(4))
    var spans = List[Span]()
    spans.append(_span(0, 1, 0))
    assert_equal(len(delete_spans(seq.copy(), spans^)), 0)


def test_delete_spans_greedy_removes_junk_one_by_one() raises:
    # Pure simulation of the shrink loop: adopt the first candidate
    # whose elements still sum above the threshold, with spans
    # re-recorded after each adoption like the runner does.
    var seq = _seq(
        UInt64(1),
        UInt64(5),
        UInt64(1),
        UInt64(99),
        UInt64(1),
        UInt64(7),
        UInt64(0),
    )
    while True:
        var cands = delete_spans(seq.copy(), _width2_spans(len(seq)))
        var adopted = False
        for i in range(len(cands)):
            if _elem_sum(cands[i].copy()) > UInt64(100):
                seq = cands[i].copy()
                adopted = True
                break
        if not adopted:
            break
    assert_equal(len(seq), 5)
    assert_equal(seq[1].value, UInt64(99))
    assert_equal(seq[3].value, UInt64(7))


def test_zero_spans_zeroes_each_span() raises:
    var seq = _seq(
        UInt64(1),
        UInt64(5),
        UInt64(1),
        UInt64(99),
        UInt64(1),
        UInt64(7),
        UInt64(0),
    )
    var cands = zero_spans(seq.copy(), _list_spans())
    assert_equal(len(cands), 3)
    assert_equal(cands[0][0].value, UInt64(0))
    assert_equal(cands[0][1].value, UInt64(0))
    assert_equal(cands[0][3].value, UInt64(99))
    assert_equal(cands[1][3].value, UInt64(0))
    assert_equal(cands[2][5].value, UInt64(0))
    for i in range(len(cands)):
        assert_equal(len(cands[i]), len(seq))
        assert_true(
            is_shortlex_smaller(cands[i].copy(), seq.copy()),
            msg="every span zeroing must be shortlex-smaller",
        )


def test_zero_spans_deepest_first() raises:
    var seq = _seq(
        UInt64(1), UInt64(2), UInt64(3), UInt64(4), UInt64(5), UInt64(6)
    )
    var spans = List[Span]()
    spans.append(_span(0, 4, 0))
    spans.append(_span(0, 2, 1))
    spans.append(_span(2, 4, 1))
    spans.append(_span(4, 6, 0))
    var cands = zero_spans(seq.copy(), spans^)
    assert_equal(len(cands), 4)
    assert_equal(cands[0][0].value, UInt64(0))
    assert_equal(cands[0][1].value, UInt64(0))
    assert_equal(cands[0][2].value, UInt64(3))
    assert_equal(cands[1][2].value, UInt64(0))
    assert_equal(cands[1][0].value, UInt64(1))


def test_zero_spans_skips_unchanged() raises:
    var zeros = _seq(UInt64(0), UInt64(0))
    var spans = List[Span]()
    spans.append(_span(0, 2, 0))
    assert_equal(len(zero_spans(zeros.copy(), spans^)), 0)
    var mixed = _seq(UInt64(5), UInt64(0), UInt64(3))
    var spans2 = List[Span]()
    spans2.append(_span(0, 1, 1))
    spans2.append(_span(1, 2, 1))
    spans2.append(_span(1, 3, 0))
    var cands = zero_spans(mixed.copy(), spans2^)
    assert_equal(len(cands), 2)
    for i in range(len(cands)):
        assert_true(
            is_shortlex_smaller(cands[i].copy(), mixed.copy()),
            msg="every span zeroing must be shortlex-smaller",
        )


def test_zero_spans_preserves_forced() raises:
    var seq = ChoiceSequence()
    seq.append(_node(UInt64(7)))
    seq.append(_forced(UInt64(9)))
    seq.append(_node(UInt64(5)))
    var spans = List[Span]()
    spans.append(_span(0, 3, 0))
    var cands = zero_spans(seq.copy(), spans^)
    assert_equal(len(cands), 1)
    assert_equal(cands[0][0].value, UInt64(0))
    assert_equal(cands[0][1].value, UInt64(9))
    assert_true(cands[0][1].forced, msg="forced flag must survive")
    assert_equal(cands[0][2].value, UInt64(0))


def test_zero_spans_skips_discarded_and_empty() raises:
    var seq = _seq(UInt64(4), UInt64(5))
    var spans = List[Span]()
    spans.append(Span(0, 2, _ELEM_LABEL, 1, Bool(True)))
    spans.append(_span(0, 0, 1))
    assert_equal(len(zero_spans(seq.copy(), spans^)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
