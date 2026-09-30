from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.runner import Settings, for_all
from proptest.strategies.recursive import JsonTree, JsonValue, json_tree
from proptest.testcase import TestCase
from std.testing import TestSuite, assert_equal, assert_true


def _replaying(*values: UInt64) -> TestCase:
    var prefix = ChoiceSequence()
    for v in values:
        prefix.append(
            ChoiceNode(ChoiceKind.INTEGER, v, UInt64(100), Bool(False))
        )
    return TestCase.replaying(prefix^)


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _draw_empty(strategy: JsonTree) raises -> String:
    var tc = _empty()
    return String(tc.draw(strategy))


def _draw_replaying(strategy: JsonTree, *values: UInt64) raises -> String:
    var tc = _replaying(*values)
    return String(tc.draw(strategy))


def _fails_on_array(mut tc: TestCase) raises:
    var tree = json_tree(2, 2, -5, 5)
    var value = tc.draw(tree.copy(), "tree")
    if value.is_array():
        raise Error("found array: " + String(value))


def test_all_zero_draws_null() raises:
    assert_equal(_draw_empty(json_tree(3, 3, -5, 5)), String("null"))


def test_depth_zero_draws_leaf_only() raises:
    assert_equal(_draw_empty(json_tree(0, 3, -5, 5)), String("null"))
    var tc = _replaying(UInt64(1), UInt64(1), UInt64(1))
    var value = tc.draw(json_tree(0, 3, -5, 5))
    assert_true(not value.is_array(), msg="depth 0 must not draw arrays")
    assert_equal(value.depth(), 0)


def test_leaf_int_draws_target() raises:
    assert_equal(
        _draw_replaying(
            json_tree(3, 3, -5, 5), UInt64(0), UInt64(1), UInt64(0)
        ),
        String("0"),
    )


def test_branch_width_zero_draws_empty_array() raises:
    assert_equal(
        _draw_replaying(json_tree(3, 3, -5, 5), UInt64(1), UInt64(0)),
        String("[]"),
    )


def test_branch_width_one_draws_singleton() raises:
    assert_equal(
        _draw_replaying(
            json_tree(3, 3, -5, 5), UInt64(1), UInt64(1), UInt64(0), UInt64(0)
        ),
        String("[null]"),
    )


def test_singleton_int_child() raises:
    assert_equal(
        _draw_replaying(
            json_tree(3, 3, -5, 5),
            UInt64(1),
            UInt64(1),
            UInt64(0),
            UInt64(1),
            UInt64(0),
        ),
        String("[0]"),
    )


def test_width_two_draws_pair() raises:
    assert_equal(
        _draw_replaying(
            json_tree(3, 3, -5, 5),
            UInt64(1),
            UInt64(2),
            UInt64(0),
            UInt64(0),
            UInt64(0),
            UInt64(0),
        ),
        String("[null,null]"),
    )


def test_draws_are_deterministic_for_same_prefix() raises:
    var first = _draw_replaying(
        json_tree(3, 3, -5, 5), UInt64(1), UInt64(1), UInt64(0), UInt64(0)
    )
    var second = _draw_replaying(
        json_tree(3, 3, -5, 5), UInt64(1), UInt64(1), UInt64(0), UInt64(0)
    )
    assert_equal(first, second)


def test_depth_bound_holds_for_generated_trees() raises:
    for max_depth in range(4):
        for seed in range(50):
            var tc = TestCase.generating(derive(UInt64(seed), UInt64(7)))
            var value = tc.draw(json_tree(max_depth, 3, -5, 5))
            assert_true(
                value.depth() <= max_depth,
                msg="tree depth must respect max_depth",
            )


def test_generated_widths_respect_max_width() raises:
    for seed in range(50):
        var tc = TestCase.generating(derive(UInt64(seed), UInt64(11)))
        var value = tc.draw(json_tree(2, 2, -5, 5))
        assert_true(
            _widths_ok(value, 2), msg="array width must respect max_width"
        )


def _widths_ok(value: JsonValue, limit: Int) -> Bool:
    if not value.is_array():
        return True
    if len(value.children) > limit:
        return False
    for i in range(len(value.children)):
        if not _widths_ok(value.children[i][].copy(), limit):
            return False
    return True


def test_zeroed_choices_shrink_to_null() raises:
    var tc = TestCase.generating(derive(UInt64(0), UInt64(1)))
    var complex_tree = json_tree(3, 3, -5, 5)
    var complex_value = tc.draw(complex_tree.copy())
    assert_true(
        complex_value.node_count() > 1,
        msg="seed 0 attempt 1 must draw a non-trivial tree",
    )
    var replayed = _replaying()
    var simple_value = replayed.draw(json_tree(3, 3, -5, 5))
    assert_equal(String(simple_value), String("null"))
    assert_true(
        simple_value.node_count() < complex_value.node_count(),
        msg="all-zero choices must be simpler",
    )


def test_invalid_args_raise() raises:
    var raised_depth = False
    try:
        _ = json_tree(-1, 3, -5, 5)
    except:
        raised_depth = True
    assert_true(raised_depth, msg="negative max_depth must raise")
    var raised_width = False
    try:
        _ = json_tree(3, 0, -5, 5)
    except:
        raised_width = True
    assert_true(raised_width, msg="max_width < 1 must raise")
    var raised_range = False
    try:
        _ = json_tree(3, 3, 5, -5)
    except:
        raised_range = True
    assert_true(raised_range, msg="empty int range must raise")


def test_node_count_counts_arrays() raises:
    var tc = _replaying(
        UInt64(1), UInt64(2), UInt64(0), UInt64(0), UInt64(0), UInt64(0)
    )
    var value = tc.draw(json_tree(3, 3, -5, 5))
    assert_equal(String(value), String("[null,null]"))
    assert_equal(value.node_count(), 3)
    assert_equal(value.depth(), 1)


def test_for_all_shrinks_array_to_empty() raises:
    var report = String("")
    try:
        for_all(_fails_on_array, Settings(max_examples=100, seed=UInt64(12345)))
    except e:
        report = String(e)
    assert_true(
        ("tree = []" in report), msg="expected minimal array, got: " + report
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
