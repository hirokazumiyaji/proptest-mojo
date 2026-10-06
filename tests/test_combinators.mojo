from std.io import Writer

from proptest import Settings, TestCase, for_all, integers
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy, kind_label
from proptest.strategies.combinators import filter, flat_map, map
from proptest.strategies.primitives import Integers, booleans
from proptest.testcase import Status
from std.testing import TestSuite, assert_equal, assert_true


def double(x: Int) -> Int:
    return x * 2


def is_even(x: Int) -> Bool:
    return x % 2 == 0


def capped(n: Int) -> Integers:
    return Integers(0, n)


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


def _fails_at_doubled_10(mut tc: TestCase) raises:
    var y = tc.draw(map[double](integers(0, 100)), "y")
    if y >= 10:
        raise Error("too big: y=" + String(y))


def _fails_at_capped_5(mut tc: TestCase) raises:
    var z = tc.draw(flat_map[capped](integers(0, 10)), "z")
    if z >= 5:
        raise Error("too big: z=" + String(z))


def _fails_on_adult_admin(mut tc: TestCase) raises:
    var user = tc.draw(Users(120), "user")
    if user.age >= 18 and user.admin:
        raise Error("adult admin: " + String(user))


def _report_of[
    P: def(mut TestCase) raises -> None
](prop: P, seed: UInt64) raises -> String:
    var report = String("")
    try:
        for_all(prop, Settings(seed=seed))
    except e:
        report = String(e)
    return report^


@fieldwise_init
struct User(Copyable, Movable, Writable):
    var age: Int
    var admin: Bool

    def write_to(self, mut writer: Some[Writer]):
        writer.write("User(age=", self.age, ", admin=", self.admin, ")")


@fieldwise_init
struct Users(Strategy):
    comptime Value = User
    var max_age: Int

    def span_label(self) -> UInt64:
        return kind_label("users")

    def draw(self, mut tc: TestCase) raises -> User:
        var age = tc.draw(integers(0, self.max_age), "age")
        var admin = tc.draw(booleans(), "admin")
        return User(age, admin)


def test_map_all_zero_is_simplest() raises:
    var tc = _empty()
    assert_equal(tc.draw(map[double](integers(0, 100))), 0)


def test_map_applies_function() raises:
    assert_equal(_draw_map_replaying(UInt64(0)), 0)
    assert_equal(_draw_map_replaying(UInt64(1)), 2)
    assert_equal(_draw_map_replaying(UInt64(2)), 4)


def _draw_map_replaying(choice: UInt64) raises -> Int:
    var tc = _replaying(choice)
    return tc.draw(map[double](integers(0, 100)))


def test_map_is_deterministic() raises:
    var first = _draw_map_replaying(UInt64(3))
    var second = _draw_map_replaying(UInt64(3))
    assert_equal(first, second)


def test_map_shrinks_through_base() raises:
    var report = _report_of(_fails_at_doubled_10, UInt64(1))
    assert_true(("y = 10" in report), msg="expected minimal y, got: " + report)


def test_filter_accepts_matching_draw() raises:
    var tc = _empty()
    assert_equal(tc.draw(filter[is_even](integers(0, 100))), 0)


def test_filter_always_satisfies_predicate() raises:
    for seed in range(32):
        var tc = _generating(UInt64(seed))
        try:
            var value = tc.draw(filter[is_even](integers(0, 100)))
            assert_true(value % 2 == 0, msg="filtered value must be even")
        except:
            assert_true(
                tc.status == Status.INVALID,
                msg="filter may only fail as INVALID",
            )


def test_filter_records_discarded_span_on_reject() raises:
    var tc = _replaying(UInt64(1), UInt64(0))
    var value = tc.draw(filter[is_even](integers(0, 100)))
    assert_equal(value, 0)
    assert_equal(len(tc.choices), 2)
    var saw_discarded = False
    var saw_kept = False
    for i in range(len(tc.spans)):
        if tc.spans[i].discarded:
            saw_discarded = True
        else:
            saw_kept = True
    assert_true(
        saw_discarded, msg="rejected attempt must leave a discarded span"
    )
    assert_true(saw_kept, msg="accepted attempt must leave a kept span")


def test_filter_invalid_after_three_failures() raises:
    var tc = _empty()
    var raised = False
    try:
        _ = tc.draw(filter[is_even](integers(1, 1)))
    except:
        raised = True
    assert_true(raised, msg="exhausted filter must raise")
    assert_true(tc.status == Status.INVALID, msg="exhausted filter is INVALID")
    assert_equal(len(tc.choices), 3)


def test_flat_map_all_zero_is_simplest() raises:
    var tc = _empty()
    assert_equal(tc.draw(flat_map[capped](integers(0, 10))), 0)


def test_flat_map_inner_depends_on_outer() raises:
    var tc = _replaying(UInt64(3), UInt64(2))
    assert_equal(tc.draw(flat_map[capped](integers(0, 10))), 2)
    var wide = _replaying(UInt64(5), UInt64(5))
    assert_equal(wide.draw(flat_map[capped](integers(0, 10))), 5)


def test_flat_map_outer_and_inner_shrink() raises:
    var report = _report_of(_fails_at_capped_5, UInt64(1))
    assert_true(("z = 5" in report), msg="expected minimal z, got: " + report)


def test_composite_users_all_zero_is_simplest() raises:
    var tc = _empty()
    var user = tc.draw(Users(120))
    assert_equal(user.age, 0)
    assert_equal(user.admin, False)


def test_composite_users_shrinks_to_minimal() raises:
    var report = _report_of(_fails_on_adult_admin, UInt64(1))
    assert_true(("age = 18" in report), msg="expected minimal age: " + report)
    assert_true(
        ("admin = True" in report), msg="expected admin True: " + report
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
