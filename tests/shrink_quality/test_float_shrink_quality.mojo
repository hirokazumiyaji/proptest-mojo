"""Float shrink quality regressions for non-monotone subnormal islands.

Complements `tests/test_simplify_floats.mojo` with the scaled division
association case that sits past a fixed 256-code gap fill but still well
within the default evaluation budget when ascending small magnitudes.
"""

from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.shrink.shrinker import Evaluation, shrink, shrink_with
from proptest.strategies.floats import lex_to_float
from std.testing import TestSuite, assert_equal, assert_true

comptime FLOAT_MAX = UInt64(0xFFFFFFFFFFFFFFFF)


def _float_seq(code: UInt64) -> ChoiceSequence:
    var seq = ChoiceSequence()
    seq.append(ChoiceNode(ChoiceKind.FLOAT, code, FLOAT_MAX, Bool(False)))
    return seq^


def _eval_scaled_div_assoc(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            var x = lex_to_float(seq.nodes[i].value)
            return Evaluation((x / 2.0) / 256.0 != x / 512.0, seq.copy())
    return Evaluation(False, seq.copy())


def test_scaled_div_assoc_shrinks_past_gap_fill_bound() raises:
    var start = _float_seq(UInt64(767))
    var result = shrink[_eval_scaled_div_assoc](start.copy(), 5000)
    assert_equal(result.best[0].value, UInt64(257))
    assert_true(not result.hit_budget, msg="must finish within budget")
    var runtime = shrink_with(_eval_scaled_div_assoc, start.copy(), 5000)
    assert_equal(runtime.best[0].value, UInt64(257))
    assert_true(not runtime.hit_budget, msg="shrink_with must finish in budget")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
