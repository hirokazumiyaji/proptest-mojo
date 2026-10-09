from proptest import ExampleDatabase, Settings, TestCase, encode_values, for_all
from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    shortlex_compare,
)
from proptest.database import name_dir
from proptest.shrink.float_passes import float_fraction_probes, simplify_floats
from proptest.shrink.shrinker import Evaluation, shrink, shrink_with
from proptest.strategies.floats import (
    float_to_lex,
    floats,
    lex_to_float,
    max_finite,
)
from std.math import isinf, isnan
from std.os import listdir, remove
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true
from std.time import monotonic

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


def test_fraction_probes_include_one_point_five_from_1_75() raises:
    # Exact integers yield no fraction probes (floor(n*d)/d == n); binary
    # search still finds 1.5 from 2.0. Non-integers expose the 1.5 probe.
    var probes = float_fraction_probes(float_to_lex(1.75))
    var found = False
    for i in range(len(probes)):
        if probes[i] == float_to_lex(1.5):
            found = True
            break
    assert_true(found, msg="1.75 must probe the 1.5 fraction code")


def _eval_float_at_least_1_5(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            var interesting = lex_to_float(seq.nodes[i].value) >= 1.5
            return Evaluation(interesting, seq.copy())
    return Evaluation(False, seq.copy())


def test_shrink_loop_float_threshold_within_budget() raises:
    var start = _float_seq(float_to_lex(2.0))
    var result = shrink[_eval_float_at_least_1_5](start.copy(), 5000)
    assert_equal(lex_to_float(result.best[0].value), 1.5)
    assert_true(not result.hit_budget, msg="must finish within default budget")
    var runtime = shrink_with(_eval_float_at_least_1_5, start.copy(), 5000)
    assert_equal(lex_to_float(runtime.best[0].value), 1.5)
    assert_true(not runtime.hit_budget, msg="shrink_with must finish in budget")


def _eval_is_nan(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            return Evaluation(
                isnan(lex_to_float(seq.nodes[i].value)), seq.copy()
            )
    return Evaluation(False, seq.copy())


def test_shrink_nan_code_terminates_without_hang() raises:
    # High-bit NaN magnitude codes used to overflow (lo+hi) and cycle on
    # cache hits forever. Safe midpoints must terminate within budget.
    var start = _float_seq(UInt64(0xC000000000000000))
    var result = shrink[_eval_is_nan](start.copy(), 5000)
    assert_true(isnan(lex_to_float(result.best[0].value)))
    assert_true(
        result.evaluations < 5000 or not result.hit_budget,
        msg="must not burn the full budget cycling cached mids",
    )
    assert_true(
        result.evaluations < 200,
        msg="safe search should finish quickly, got "
        + String(result.evaluations),
    )


def _eval_unsafe_square(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            var x = lex_to_float(seq.nodes[i].value)
            var square = x * x
            var interesting = (x != 0.0) and (square == 0.0 or isinf(square))
            return Evaluation(interesting, seq.copy())
    return Evaluation(False, seq.copy())


def test_shrink_prefers_least_positive_underflow() raises:
    var start = _float_seq(float_to_lex(max_finite()))
    var result = shrink[_eval_unsafe_square](start.copy(), 5000)
    assert_equal(result.best[0].value, UInt64(1))
    assert_true(not result.hit_budget, msg="must finish within budget")
    var runtime = shrink_with(_eval_unsafe_square, start.copy(), 5000)
    assert_equal(runtime.best[0].value, UInt64(1))
    assert_true(not runtime.hit_budget, msg="shrink_with must finish in budget")


def _eval_half_unsafe_square(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            var y = lex_to_float(seq.nodes[i].value) / 2.0
            var square = y * y
            var interesting = (y > 0.0) and (square == 0.0 or isinf(square))
            return Evaluation(interesting, seq.copy())
    return Evaluation(False, seq.copy())


def test_shrink_preserves_low_code_half_underflow() raises:
    # Code 1 halves to 0 so it passes; code 2 is the least interesting.
    var start = _float_seq(float_to_lex(max_finite()))
    var result = shrink[_eval_half_unsafe_square](start.copy(), 5000)
    assert_equal(result.best[0].value, UInt64(2))
    assert_true(not result.hit_budget, msg="must finish within budget")
    var runtime = shrink_with(_eval_half_unsafe_square, start.copy(), 5000)
    assert_equal(runtime.best[0].value, UInt64(2))
    assert_true(not runtime.hit_budget, msg="shrink_with must finish in budget")


def _eval_nonzero(seq: ChoiceSequence) -> Evaluation:
    if len(seq) == 0:
        return Evaluation(False, seq.copy())
    for i in range(len(seq)):
        if seq.nodes[i].kind == ChoiceKind.FLOAT:
            return Evaluation(
                lex_to_float(seq.nodes[i].value) != 0.0, seq.copy()
            )
    return Evaluation(False, seq.copy())


def test_shrink_prefers_unit_before_fractions_on_tight_budget() raises:
    var start = _float_seq(float_to_lex(1.75))
    var result = shrink[_eval_nonzero](start.copy(), 2)
    assert_equal(result.best[0].value, UInt64(1))
    var runtime = shrink_with(_eval_nonzero, start.copy(), 2)
    assert_equal(runtime.best[0].value, UInt64(1))


def _fails_at_1_5(mut tc: TestCase) raises:
    if tc.draw(floats(allow_nan=False), "x") >= 1.5:
        raise Error("threshold")


def _fresh_float_db_dir() -> String:
    return "/tmp/proptest-mojo-float-shrink-" + String(Int(monotonic()))


def _clean_float_db(database_dir: String, name: String) raises:
    try:
        var dir = name_dir(database_dir, name)
        var entries = listdir(dir)
        for i in range(len(entries)):
            var full = dir + "/" + String(entries[i])
            if Path(full).is_file():
                remove(full)
    except:
        pass


def test_for_all_float_threshold_reports_1_5() raises:
    var dir = _fresh_float_db_dir()
    var name = String("float-shrink")
    _clean_float_db(dir, name)
    var db = ExampleDatabase(dir.copy(), name.copy())
    var values = List[UInt64]()
    values.append(UInt64(0))
    values.append(float_to_lex(2.0))
    db.save(encode_values(values^))
    var report = String("")
    try:
        for_all(
            _fails_at_1_5,
            Settings(name=name, database_dir=dir, seed=UInt64(1)),
        )
    except e:
        report = String(e)
    assert_true(
        ("x = 1.5" in report) or ("1.5" in report),
        msg="must shrink to 1.5, got: " + report,
    )
    assert_true(
        not ("budget exhausted" in report),
        msg="must finish within default budget: " + report,
    )
    _clean_float_db(dir, name)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
