from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
    shortlex_compare,
)
from std.testing import TestSuite, assert_equal, assert_true


def _node(value: UInt64, max_value: UInt64 = UInt64(100)) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, max_value, Bool(False))


def _seq(*values: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    for v in values:
        seq.append(_node(v))
    return seq^


def test_choice_kind_constants_are_distinct() raises:
    assert_true(
        ChoiceKind.INTEGER != ChoiceKind.BOOLEAN,
        msg="INTEGER and BOOLEAN must differ",
    )
    assert_true(
        ChoiceKind.INTEGER != ChoiceKind.FLOAT,
        msg="INTEGER and FLOAT must differ",
    )
    assert_true(
        ChoiceKind.BOOLEAN != ChoiceKind.FLOAT,
        msg="BOOLEAN and FLOAT must differ",
    )
    assert_equal(ChoiceKind.INTEGER, ChoiceKind(0))
    assert_equal(ChoiceKind.BOOLEAN, ChoiceKind(1))
    assert_equal(ChoiceKind.FLOAT, ChoiceKind(2))


def test_shortlex_shorter_is_smaller() raises:
    var short = _seq(UInt64(99), UInt64(99))
    var long = _seq(UInt64(0), UInt64(0), UInt64(0))
    assert_true(short < long, msg="shorter sequence must be smaller")
    assert_true(long > short, msg="longer sequence must be larger")
    assert_equal(shortlex_compare(short, long), -1)
    assert_equal(shortlex_compare(long, short), 1)


def test_shortlex_lexicographic_on_equal_length() raises:
    var a = _seq(UInt64(0), UInt64(5))
    var b = _seq(UInt64(0), UInt64(6))
    var c = _seq(UInt64(1), UInt64(0))
    assert_true(a < b, msg="[0,5] < [0,6]")
    assert_true(b < c, msg="[0,6] < [1,0]")
    assert_true(a < c, msg="transitivity: [0,5] < [1,0]")
    assert_true(a <= b, msg="<= must hold when < holds")
    assert_true(b >= a, msg=">= must hold when > holds")
    assert_true(
        is_shortlex_smaller(a, c), msg="helper must agree with operator"
    )


def test_shortlex_is_total_order_on_examples() raises:
    var seqs = List[ChoiceSequence]()
    seqs.append(_seq())
    seqs.append(_seq(UInt64(0)))
    seqs.append(_seq(UInt64(1)))
    seqs.append(_seq(UInt64(0), UInt64(0)))
    seqs.append(_seq(UInt64(0), UInt64(1)))
    seqs.append(_seq(UInt64(1), UInt64(0)))
    seqs.append(_seq(UInt64(0), UInt64(0), UInt64(0)))
    for i in range(len(seqs)):
        var reflexive = seqs[i].copy()
        assert_true(seqs[i] == reflexive, msg="equality must be reflexive")
        assert_true(not (seqs[i] < reflexive), msg="irreflexivity of <")
        assert_true(seqs[i] <= reflexive, msg="reflexivity of <=")
        assert_true(seqs[i] >= reflexive, msg="reflexivity of >=")
        assert_equal(shortlex_compare(seqs[i], reflexive), 0)
        for j in range(len(seqs)):
            var lt = seqs[i] < seqs[j]
            var gt = seqs[i] > seqs[j]
            var eq = seqs[i] == seqs[j]
            assert_true(lt or gt or eq, msg="any pair must be comparable")
            assert_true(not (lt and gt), msg="no pair is both < and >")
            assert_true(
                (lt or eq) == (seqs[i] <= seqs[j]),
                msg="<= must match < or ==",
            )
            assert_true(
                (gt or eq) == (seqs[i] >= seqs[j]),
                msg=">= must match > or ==",
            )
            assert_true(
                (seqs[i] < seqs[j]) == (seqs[j] > seqs[i]),
                msg="antisymmetry of < and >",
            )
            for k in range(len(seqs)):
                if seqs[i] < seqs[j] and seqs[j] < seqs[k]:
                    assert_true(seqs[i] < seqs[k], msg="transitivity of <")


def test_values_truncated_deleted_zeroed() raises:
    var seq = _seq(UInt64(1), UInt64(2), UInt64(3), UInt64(4))
    var values = seq.values()
    assert_equal(len(values), 4)
    assert_equal(values[0], UInt64(1))
    assert_equal(values[3], UInt64(4))

    var cut = seq.truncated(2)
    assert_equal(len(cut), 2)
    assert_equal(cut[0].value, UInt64(1))
    assert_equal(cut[1].value, UInt64(2))
    assert_equal(len(seq), 4)

    var deleted = seq.deleted(1, 3)
    assert_equal(deleted.values()[0], UInt64(1))
    assert_equal(deleted.values()[1], UInt64(4))
    assert_equal(len(deleted), 2)

    var zeroed = seq.zeroed(1, 3)
    assert_equal(zeroed[0].value, UInt64(1))
    assert_equal(zeroed[1].value, UInt64(0))
    assert_equal(zeroed[2].value, UInt64(0))
    assert_equal(zeroed[3].value, UInt64(4))


def test_forced_choices_are_preserved() raises:
    var seq = ChoiceSequence()
    seq.append(_node(UInt64(7)))
    seq.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(9), UInt64(100), Bool(True))
    )
    var zeroed = seq.zeroed(0, 2)
    assert_equal(zeroed[0].value, UInt64(0))
    assert_equal(zeroed[1].value, UInt64(9))
    var moved = seq.with_value_at(1, UInt64(1))
    assert_equal(moved[1].value, UInt64(9))


def test_replaced_range_splices_nodes() raises:
    var seq = _seq(UInt64(1), UInt64(2), UInt64(3))
    var replacement = List[ChoiceNode]()
    replacement.append(_node(UInt64(8)))
    replacement.append(_node(UInt64(9)))
    var out = seq.replaced_range(1, 2, replacement)
    assert_equal(len(out), 4)
    assert_equal(out[0].value, UInt64(1))
    assert_equal(out[1].value, UInt64(8))
    assert_equal(out[2].value, UInt64(9))
    assert_equal(out[3].value, UInt64(3))


def test_span_helpers() raises:
    var span = Span(2, 5, UInt64(7), 1, Bool(False))
    assert_equal(span.length(), 3)
    assert_true(not span.is_empty(), msg="non-empty span")
    assert_true(
        Span(3, 3, UInt64(0), 0, Bool(False)).is_empty(),
        msg="empty span",
    )
    assert_equal(span, Span(2, 5, UInt64(7), 1, Bool(False)))
    assert_true(
        span != Span(2, 6, UInt64(7), 1, Bool(False)),
        msg="spans with different ends differ",
    )


def test_writable_output_is_readable() raises:
    var seq = _seq(UInt64(1), UInt64(2))
    var text = String(seq)
    assert_true(text.byte_length() > 0, msg="ChoiceSequence must render")
    var node_text = String(_node(UInt64(3), UInt64(10)))
    assert_true(
        node_text == "INTEGER(3/10, forced=False)",
        msg="unexpected node rendering: " + node_text,
    )
    var kind_text = String(ChoiceKind.BOOLEAN)
    assert_equal(kind_text, "BOOLEAN")
    var span_text = String(Span(0, 2, UInt64(1), 0, Bool(False)))
    assert_true(span_text.byte_length() > 0, msg="Span must render")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
