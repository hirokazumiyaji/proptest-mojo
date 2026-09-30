from proptest import (
    DictList,
    Settings,
    Status,
    TestCase,
    booleans,
    dicts,
    for_all,
    integers,
    just,
    unique_lists,
)
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from std.testing import TestSuite, assert_equal, assert_true


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _draw_empty[S: Strategy](strategy: S) raises -> S.Value:
    var tc = _empty()
    return tc.draw(strategy)


def _boolean_node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.BOOLEAN, value, UInt64(1), Bool(False))


def _integer_node(value: UInt64) -> ChoiceNode:
    return ChoiceNode(
        ChoiceKind.INTEGER, value, UInt64(0xFFFFFFFFFFFFFFFF), Bool(False)
    )


def _assert_distinct(xs: List[Int]) raises:
    for i in range(len(xs)):
        for j in range(i + 1, len(xs)):
            assert_true(xs[i] != xs[j], msg="elements must be unique")


def test_unique_all_zero_gives_simplest() raises:
    var empty_list = _draw_empty(unique_lists(integers(0, 10)))
    assert_equal(len(empty_list), 0)
    var single = _draw_empty(unique_lists(integers(0, 10), min_size=1))
    assert_equal(len(single), 1)
    assert_equal(single[0], 0)


def test_unique_elements_always_unique_and_bounded() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var xs = tc.draw(unique_lists(integers(0, 5), min_size=0, max_size=6))
        assert_true(0 <= len(xs) and len(xs) <= 6)
        _assert_distinct(xs)
        for i in range(len(xs)):
            assert_true(0 <= xs[i] and xs[i] <= 5)
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var xs = tc.draw(unique_lists(integers(0, 100), min_size=1, max_size=6))
        assert_true(1 <= len(xs) and len(xs) <= 6)
        _assert_distinct(xs)


def test_unique_forces_duplicates_into_discarded_spans() raises:
    var prefix = ChoiceSequence()
    prefix.append(_boolean_node(UInt64(1)))
    prefix.append(_integer_node(UInt64(0)))
    prefix.append(_boolean_node(UInt64(1)))
    prefix.append(_integer_node(UInt64(0)))
    prefix.append(_integer_node(UInt64(1)))
    prefix.append(_boolean_node(UInt64(0)))
    var tc = TestCase.replaying(prefix^)
    var xs = tc.draw(unique_lists(integers(0, 5), min_size=0, max_size=3))
    assert_equal(len(xs), 2)
    assert_equal(xs[0], 0)
    assert_equal(xs[1], 1)
    var discarded = 0
    for i in range(len(tc.spans)):
        if tc.spans[i].discarded:
            discarded += 1
    assert_equal(discarded, 2)


def test_unique_unsatisfiable_is_invalid() raises:
    var tc = _empty()
    var saw_invalid = False
    try:
        _ = tc.draw(unique_lists(just(0), min_size=2, max_size=5))
    except:
        saw_invalid = tc.status == Status.INVALID
    assert_true(saw_invalid, msg="single-value domain below min must INVALID")
    var tc2 = _generating(UInt64(7))
    saw_invalid = False
    try:
        _ = tc2.draw(unique_lists(booleans(), min_size=3, max_size=5))
    except:
        saw_invalid = tc2.status == Status.INVALID
    assert_true(saw_invalid, msg="booleans below min_size=3 must INVALID")


def test_unique_invalid_bounds_raise() raises:
    var raised = False
    try:
        _ = unique_lists(integers(0, 10), min_size=5, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="max below min must raise")
    raised = False
    try:
        _ = unique_lists(integers(0, 10), min_size=-1, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="negative min must raise")


def test_unique_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(9))
    var first = a.draw(unique_lists(integers(-50, 50), min_size=0, max_size=8))
    var b = _generating(UInt64(9))
    var second = b.draw(unique_lists(integers(-50, 50), min_size=0, max_size=8))
    assert_equal(first, second)
    assert_equal(a.choices, b.choices)


def test_dicts_all_zero_gives_simplest() raises:
    var empty_dict = _draw_empty(dicts(integers(0, 10), integers(0, 100)))
    assert_equal(len(empty_dict), 0)
    assert_equal(String(empty_dict), "{}")
    var single = _draw_empty(
        dicts(integers(0, 10), integers(0, 100), min_size=1, max_size=5)
    )
    assert_equal(len(single), 1)
    assert_equal(single.keys()[0], 0)
    assert_equal(single[0], 0)
    assert_equal(String(single), "{0: 0}")


def test_dicts_size_in_range_and_keys_unique() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var d = tc.draw(dicts(integers(0, 5), integers(0, 100)))
        assert_true(0 <= len(d) and len(d) <= 32)
        _assert_distinct(d.keys())
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var d = tc.draw(
            dicts(integers(0, 100), integers(-50, 50), min_size=1, max_size=6)
        )
        assert_true(1 <= len(d) and len(d) <= 6)
        var keys = d.keys()
        _assert_distinct(keys)
        for i in range(len(keys)):
            assert_true(0 <= keys[i] and keys[i] <= 100)
        assert_equal(len(d.values()), len(d))


def test_dicts_duplicate_keys_are_discarded_spans() raises:
    var prefix = ChoiceSequence()
    prefix.append(_boolean_node(UInt64(1)))
    prefix.append(_integer_node(UInt64(0)))
    prefix.append(_integer_node(UInt64(7)))
    prefix.append(_boolean_node(UInt64(1)))
    prefix.append(_integer_node(UInt64(0)))
    prefix.append(_integer_node(UInt64(1)))
    prefix.append(_integer_node(UInt64(8)))
    prefix.append(_boolean_node(UInt64(0)))
    var tc = TestCase.replaying(prefix^)
    var d = tc.draw(
        dicts(integers(0, 5), integers(0, 100), min_size=0, max_size=3)
    )
    assert_equal(len(d), 2)
    assert_equal(d[0], 7)
    assert_equal(d[1], 8)
    var discarded = 0
    for i in range(len(tc.spans)):
        if tc.spans[i].discarded:
            discarded += 1
    assert_equal(discarded, 2)


def test_dicts_missing_key_raises() raises:
    var d = _draw_empty(
        dicts(integers(0, 10), integers(0, 100), min_size=1, max_size=5)
    )
    assert_equal(d[0], 0)
    var raised = False
    try:
        _ = d[1]
    except:
        raised = True
    assert_true(raised, msg="lookup of absent key must raise")


def test_dicts_unsatisfiable_is_invalid() raises:
    var tc = _empty()
    var saw_invalid = False
    try:
        _ = tc.draw(dicts(just(0), integers(0, 5), min_size=2, max_size=5))
    except:
        saw_invalid = tc.status == Status.INVALID
    assert_true(saw_invalid, msg="single-key domain below min must INVALID")
    var tc2 = _generating(UInt64(7))
    saw_invalid = False
    try:
        _ = tc2.draw(dicts(booleans(), integers(0, 5), min_size=3, max_size=5))
    except:
        saw_invalid = tc2.status == Status.INVALID
    assert_true(saw_invalid, msg="boolean keys below min_size=3 must INVALID")


def test_dicts_invalid_bounds_raise() raises:
    var raised = False
    try:
        _ = dicts(integers(0, 10), integers(0, 10), min_size=5, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="max below min must raise")
    raised = False
    try:
        _ = dicts(integers(0, 10), integers(0, 10), min_size=-1, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="negative min must raise")


def test_dicts_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(9))
    var first = a.draw(dicts(integers(0, 50), integers(0, 50)))
    var b = _generating(UInt64(9))
    var second = b.draw(dicts(integers(0, 50), integers(0, 50)))
    assert_equal(String(first), String(second))
    assert_equal(a.choices, b.choices)


def _prop_unique_and_dicts_hold(mut tc: TestCase) raises:
    var xs = tc.draw(
        unique_lists(integers(0, 50), min_size=0, max_size=8), "xs"
    )
    for i in range(len(xs)):
        for j in range(i + 1, len(xs)):
            tc.assume(xs[i] != xs[j])
    var d = tc.draw(
        dicts(integers(0, 50), integers(-10, 10), min_size=0, max_size=8), "d"
    )
    tc.assume(0 <= len(d) and len(d) <= 8)


def test_unique_dicts_run_under_for_all() raises:
    for_all(
        _prop_unique_and_dicts_hold, Settings(seed=UInt64(1), max_examples=20)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
