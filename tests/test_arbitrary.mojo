from proptest import (
    Arbitrary,
    Settings,
    TestCase,
    arbitrary,
    for_all,
)
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategies.floats import float_to_lex
from proptest.strategies.primitives import integers
from std.math import isnan
from std.testing import TestSuite, assert_equal, assert_true


@fieldwise_init
struct SmallId(Arbitrary):
    var value: Int

    @staticmethod
    def arbitrary(mut tc: TestCase) raises -> Self:
        return Self(tc.draw(integers(1, 100)))

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.value)


@fieldwise_init
struct Pair(Copyable, Deinitable, Writable):
    var a: Int
    var b: Int

    def write_to(self, mut writer: Some[Writer]):
        writer.write("(", self.a, ", ", self.b, ")")


def _replaying(*values: UInt64) -> TestCase:
    var prefix = ChoiceSequence()
    for v in values:
        prefix.append(
            ChoiceNode(ChoiceKind.INTEGER, v, UInt64(100), Bool(False))
        )
    return TestCase.replaying(prefix^)


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def test_arbitrary_int_all_zero_draws_zero() raises:
    var tc = _empty()
    assert_equal(tc.draw(arbitrary[Int]()), 0)


def test_arbitrary_int_choice_encoding() raises:
    var tc = _replaying(UInt64(1))
    assert_equal(tc.draw(arbitrary[Int]()), 1)
    tc = _replaying(UInt64(2))
    assert_equal(tc.draw(arbitrary[Int]()), -1)


def test_arbitrary_int_covers_full_range() raises:
    for seed in range(32):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(arbitrary[Int]())
        assert_true(Int.MIN <= value and value <= Int.MAX)


def test_arbitrary_bool_all_zero_is_false() raises:
    var tc = _empty()
    assert_equal(tc.draw(arbitrary[Bool]()), False)
    tc = _replaying(UInt64(1))
    assert_equal(tc.draw(arbitrary[Bool]()), True)


def test_arbitrary_float_all_zero_is_zero() raises:
    var tc = _empty()
    assert_equal(tc.draw(arbitrary[Float64]()), 0.0)


def test_arbitrary_float_is_deterministic() raises:
    for seed in range(16):
        var a = _generating(UInt64(seed))
        var first = a.draw(arbitrary[Float64]())
        var b = _generating(UInt64(seed))
        var second = b.draw(arbitrary[Float64]())
        assert_equal(float_to_lex(first), float_to_lex(second))
        assert_true((not isnan(first)) or isnan(second))


def test_arbitrary_string_all_zero_is_empty() raises:
    var tc = _empty()
    assert_equal(tc.draw(arbitrary[String]()), String(""))


def test_arbitrary_string_generates() raises:
    for seed in range(16):
        var tc = _generating(UInt64(seed))
        var value = tc.draw(arbitrary[String]())
        var count = 0
        for _ in value.codepoints():
            count += 1
        assert_true(0 <= count and count <= 32)


def test_arbitrary_list_int_all_zero_is_empty() raises:
    var tc = _empty()
    var xs = tc.draw(arbitrary[List[Int]]())
    assert_equal(len(xs), 0)


def test_arbitrary_list_int_generates_bounded() raises:
    for seed in range(32):
        var tc = _generating(UInt64(seed))
        var xs = tc.draw(arbitrary[List[Int]]())
        assert_true(0 <= len(xs) and len(xs) <= 32)


def test_arbitrary_list_string_generates() raises:
    var tc = _generating(UInt64(7))
    var xs = tc.draw(arbitrary[List[String]]())
    assert_true(0 <= len(xs) and len(xs) <= 32)


def test_arbitrary_nested_list_all_zero_is_empty() raises:
    var tc = _empty()
    var xss = tc.draw(arbitrary[List[List[Int]]]())
    assert_equal(len(xss), 0)


def _fails_when_long(mut tc: TestCase) raises:
    var xs = tc.draw(arbitrary[List[Int]](), "xs")
    if len(xs) >= 3:
        raise Error("too long: " + String(xs))


def test_arbitrary_list_int_shrinks_to_three_zeros() raises:
    var report = String("")
    try:
        for_all(_fails_when_long, Settings(seed=UInt64(1), max_examples=100))
    except e:
        report = String(e)
    assert_true(
        ("[0, 0, 0]" in report), msg="expected [0, 0, 0], got: " + report
    )


def test_arbitrary_trait_custom_type() raises:
    var tc = _empty()
    assert_equal(tc.draw(arbitrary[SmallId]()).value, 1)
    for seed in range(16):
        var gen = _generating(UInt64(seed))
        var value = gen.draw(arbitrary[SmallId]())
        assert_true(1 <= value.value and value.value <= 100)


def test_arbitrary_unsupported_type_raises() raises:
    var raised = False
    try:
        var tc = _empty()
        _ = tc.draw(arbitrary[Pair]())
    except:
        raised = True
    assert_true(raised, msg="unsupported type must raise")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
