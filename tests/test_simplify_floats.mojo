from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    shortlex_compare,
)
from proptest.shrink.float_passes import simplify_floats
from proptest.strategies.floats import float_to_lex, lex_to_float
from std.testing import TestSuite, assert_equal, assert_true

comptime FLOAT_MAX = UInt64(0xFFFFFFFFFFFFFFFF)


def _float_node(code: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.FLOAT, code, FLOAT_MAX, Bool(False))


def _float_seq(code: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    seq.append(_float_node(code))
    return seq^


def _at_least_1_5(seq: ChoiceSequence) -> Bool:
    return lex_to_float(seq.nodes[0].value) >= 1.5


def _at_least_1_0(seq: ChoiceSequence) -> Bool:
    return lex_to_float(seq.nodes[0].value) >= 1.0


def _at_least_0_5(seq: ChoiceSequence) -> Bool:
    return lex_to_float(seq.nodes[0].value) >= 0.5


def _always_interesting(seq: ChoiceSequence) -> Bool:
    return True


def _never_interesting(seq: ChoiceSequence) -> Bool:
    _ = seq
    return False


def test_threshold_1_5_yields_1_5() raises:
    var seq = _float_seq(float_to_lex(2.0))
    var best = simplify_floats[_at_least_1_5](seq.copy())
    assert_equal(best[0].value, float_to_lex(1.5))
    assert_equal(lex_to_float(best[0].value), 1.5)


def test_threshold_1_5_from_large_value() raises:
    var seq = _float_seq(float_to_lex(100.0))
    var best = simplify_floats[_at_least_1_5](seq.copy())
    assert_equal(best[0].value, float_to_lex(1.5))
    assert_true(
        _at_least_1_5(best.copy()), msg="simplified input stays interesting"
    )


def test_truncates_1_3927_to_1_0() raises:
    var seq = _float_seq(float_to_lex(1.3927))
    var best = simplify_floats[_at_least_1_0](seq.copy())
    assert_equal(best[0].value, float_to_lex(1.0))
    assert_equal(lex_to_float(best[0].value), 1.0)


def test_fraction_0_9_to_0_5() raises:
    var seq = _float_seq(float_to_lex(0.9))
    var best = simplify_floats[_at_least_0_5](seq.copy())
    assert_equal(best[0].value, float_to_lex(0.5))
    assert_equal(lex_to_float(best[0].value), 0.5)


def test_identity_simplifies_to_zero() raises:
    var seq = _float_seq(float_to_lex(1.3927))
    var best = simplify_floats[_always_interesting](seq.copy())
    assert_equal(best[0].value, UInt64(0))
    assert_equal(lex_to_float(best[0].value), 0.0)


def test_skips_forced() raises:
    var seq = ChoiceSequence()
    seq.append(
        ChoiceNode(ChoiceKind.FLOAT, float_to_lex(2.0), FLOAT_MAX, Bool(True))
    )
    var best = simplify_floats[_always_interesting](seq.copy())
    assert_equal(best[0].value, float_to_lex(2.0))
    assert_true(best[0].forced, msg="forced flag must survive")


def test_ignores_non_float() raises:
    var seq = ChoiceSequence()
    seq.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(7), UInt64(100), Bool(False))
    )
    var best = simplify_floats[_always_interesting](seq.copy())
    assert_equal(best[0].value, UInt64(7))


def test_keeps_uninteresting_input() raises:
    var seq = _float_seq(float_to_lex(2.0))
    var best = simplify_floats[_never_interesting](seq.copy())
    assert_true(
        best.copy() == seq.copy(), msg="without signal nothing may change"
    )


def test_result_never_larger() raises:
    var seq = _float_seq(float_to_lex(2.5))
    var best = simplify_floats[_at_least_1_5](seq.copy())
    assert_true(
        shortlex_compare(best.copy(), seq.copy()) <= 0,
        msg="simplify must not move up in shortlex order",
    )
    assert_true(
        _at_least_1_5(best.copy()), msg="simplified input stays interesting"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
