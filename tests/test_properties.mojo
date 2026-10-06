from proptest import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Settings,
    TestCase,
    derive,
    for_all,
    integers,
)
from std.testing import TestSuite, assert_true


def _draw_sequence(mut tc: TestCase) raises -> ChoiceSequence:
    var sequence = ChoiceSequence()
    var length = tc.draw(integers(0, 4))
    for _ in range(length):
        var value = tc.draw(integers(0, 4))
        sequence.append(
            ChoiceNode(
                ChoiceKind.INTEGER,
                UInt64(value),
                UInt64(4),
                Bool(False),
            )
        )
    return sequence^


def _shortlex_is_total(mut tc: TestCase) raises:
    var a = _draw_sequence(tc)
    var b = _draw_sequence(tc)
    var c = _draw_sequence(tc)

    var ab = a < b
    var ba = b < a
    assert_true(ab or ba or a == b, msg="shortlex compares every pair")
    assert_true(not (ab and ba), msg="shortlex order is antisymmetric")

    var bc = b < c
    if ab and bc:
        assert_true(a < c, msg="shortlex order is transitive")


def _integers_stay_in_range(mut tc: TestCase) raises:
    var value = tc.draw(integers(-100, 100))
    assert_true(-100 <= value and value <= 100, msg="value is in range")


def _integer_choices_shrink_monotonically(mut tc: TestCase) raises:
    var choice = tc.draw(integers(0, 19))
    var lower = ChoiceSequence()
    lower.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(choice), UInt64(20), Bool(False))
    )
    var higher = ChoiceSequence()
    higher.append(
        ChoiceNode(
            ChoiceKind.INTEGER, UInt64(choice + 1), UInt64(20), Bool(False)
        )
    )
    var lower_case = TestCase.replaying(lower^)
    var higher_case = TestCase.replaying(higher^)
    var lower_value = lower_case.draw(integers(-10, 10))
    var higher_value = higher_case.draw(integers(-10, 10))
    assert_true(
        abs(lower_value) <= abs(higher_value),
        msg="larger choices are no closer to zero",
    )


def _derive_is_deterministic(mut tc: TestCase) raises:
    var seed = UInt64(tc.draw(integers(0, 1000000)))
    var index = UInt64(tc.draw(integers(0, 1000000)))
    var first = derive(seed, index)
    var second = derive(seed, index)
    for _ in range(8):
        assert_true(
            first.next_u64() == second.next_u64(),
            msg="the same seed and index give the same stream",
        )


def test_for_all_shortlex_is_a_total_order() raises:
    for_all(_shortlex_is_total, Settings(seed=UInt64(1), max_examples=200))


def test_for_all_integers_stay_in_range() raises:
    for_all(_integers_stay_in_range, Settings(seed=UInt64(2), max_examples=200))


def test_for_all_integer_shrinking_is_monotone() raises:
    for_all(
        _integer_choices_shrink_monotonically,
        Settings(seed=UInt64(3), max_examples=200),
    )


def test_for_all_prng_derivation_is_deterministic() raises:
    for_all(
        _derive_is_deterministic, Settings(seed=UInt64(4), max_examples=200)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
