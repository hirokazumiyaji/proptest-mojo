from proptest import (
    Integers,
    ListOf,
    Settings,
    TestCase,
    for_all,
    integers,
    lists,
)

from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_raises,
)


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _draw_empty[S: Strategy](strategy: S) raises -> S.Value:
    var tc = _empty()
    return tc.draw(strategy)


def _fails_when_long(mut tc: TestCase) raises:
    var xs = tc.draw(lists(integers(0, 1000), min_size=0, max_size=10), "xs")
    if len(xs) >= 3:
        raise Error("too long: " + String(xs))


def test_lists_all_zero_gives_min_simplest() raises:
    var xs = _draw_empty(lists(integers(0, 10), min_size=2, max_size=5))
    assert_equal(len(xs), 2)
    assert_equal(xs[0], 0)
    assert_equal(xs[1], 0)
    var empty = _draw_empty(lists(integers(0, 10)))
    assert_equal(len(empty), 0)
    var fixed = _draw_empty(lists(integers(5, 10), min_size=3, max_size=3))
    assert_equal(len(fixed), 3)
    for i in range(len(fixed)):
        assert_equal(fixed[i], 5)


def test_lists_all_ones_reaches_max() raises:
    var prefix = ChoiceSequence()
    for _ in range(64):
        prefix.append(
            ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
        )
    var tc = TestCase.replaying(prefix^)
    var xs = tc.draw(lists(integers(0, 10), min_size=0, max_size=4))
    assert_equal(len(xs), 4)


def test_lists_length_always_within_bounds() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var xs = tc.draw(lists(integers(0, 100), min_size=1, max_size=6))
        assert_true(
            1 <= len(xs) and len(xs) <= 6, msg="length must stay in bounds"
        )
        for i in range(len(xs)):
            assert_true(0 <= xs[i] and xs[i] <= 100)


def test_lists_min_size_survives_short_prefix() raises:
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(1), Bool(True))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(7), UInt64(10), Bool(False))
    )
    var tc = TestCase.replaying(prefix^)
    var xs = tc.draw(lists(integers(0, 10), min_size=3, max_size=8))
    assert_equal(len(xs), 3)
    assert_equal(xs[0], 7)
    assert_equal(xs[1], 0)
    assert_equal(xs[2], 0)


def test_lists_element_spans_cover_flag_and_value() raises:
    var tc = _empty()
    var xs = tc.draw(lists(integers(0, 10), min_size=2, max_size=5), "xs")
    assert_equal(len(xs), 2)
    assert_equal(len(tc.spans), 4)
    assert_equal(tc.spans[2].discarded, True)
    assert_equal(tc.choices[0].forced, True)
    assert_equal(tc.choices[2].forced, True)
    assert_equal(tc.choices[4].forced, False)


def test_lists_invalid_bounds_raise() raises:
    var raised = False
    try:
        _ = lists(integers(0, 10), min_size=5, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="max below min must raise")
    raised = False
    try:
        _ = lists(integers(0, 10), min_size=-1, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="negative min must raise")


def test_lists_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(9))
    var first = a.draw(lists(integers(-50, 50), min_size=0, max_size=8))
    var b = _generating(UInt64(9))
    var second = b.draw(lists(integers(-50, 50), min_size=0, max_size=8))
    assert_equal(first, second)
    assert_equal(a.choices, b.choices)


def test_lists_shrinks_to_three_zeros() raises:
    var report = String("")
    try:
        for_all(_fails_when_long, Settings(seed=UInt64(1), max_examples=100))
    except e:
        report = String(e)
    assert_true(
        ("[0, 0, 0]" in report), msg="expected [0, 0, 0], got: " + report
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_listof_validates_bounds_when_constructed_directly() raises:
    # `ListOf` is re-exported, so `@fieldwise_init` lets inconsistent
    # bounds reach `draw`, which would silently violate min_size.
    var negative = ListOf[Integers](Integers(0, 10), -1, 3, 0.0)
    with assert_raises(contains="min_size must be >= 0"):
        _ = _draw_empty(negative)
    var inverted = ListOf[Integers](Integers(0, 10), 5, 3, 0.0)
    with assert_raises(contains="max_size must be >= min_size"):
        _ = _draw_empty(inverted)
