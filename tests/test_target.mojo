"""Targeted PBT: tc.target score maximization (choice-sequence.md M5)."""

from proptest import Settings, TestCase, for_all, integers
from proptest.prng import derive
from std.testing import TestSuite, assert_equal, assert_true


def _generating(seed: UInt64 = UInt64(1)) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _rare_sum_targeted(mut tc: TestCase) raises:
    var total = 0
    for _ in range(8):
        var x = tc.draw(integers(0, 100), "x")
        total += x
    tc.target(Float64(total))
    if total > 650:
        raise Error("rare sum: " + String(total))


def _targeted_passes(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 100), "x")
    tc.target(Float64(x))
    tc.note("saw x=" + String(x))


def test_target_starts_empty() raises:
    var tc = _generating()
    assert_equal(tc.has_target, False)
    assert_equal(tc.target_score, 0.0)


def test_target_keeps_maximum_score() raises:
    var tc = _generating()
    tc.target(10.0)
    assert_equal(tc.has_target, True)
    assert_equal(tc.target_score, 10.0)
    tc.target(4.0)
    assert_equal(tc.target_score, 10.0)
    tc.target(25.0, "sum")
    assert_equal(tc.target_score, 25.0)


def test_target_ignores_nan() raises:
    var tc = _generating()
    tc.target(5.0)
    var nan = Float64(0.0) / Float64(0.0)
    assert_true(nan != nan, msg="test needs a NaN value")
    tc.target(nan)
    assert_equal(tc.has_target, True)
    assert_equal(tc.target_score, 5.0)
    var fresh = _generating()
    fresh.target(nan)
    assert_equal(fresh.has_target, False)


def test_target_with_label_still_records() raises:
    var tc = _generating()
    tc.target(7.0, "my-label")
    assert_equal(tc.has_target, True)
    assert_equal(tc.target_score, 7.0)


def test_targeted_finds_rare_sum_stably() raises:
    for seed in range(5):
        var report = String("")
        try:
            for_all(
                _rare_sum_targeted,
                Settings(max_examples=100, seed=UInt64(seed + 1)),
            )
        except e:
            report = String(e)
        assert_true(
            ("rare sum" in report),
            msg="seed "
            + String(seed + 1)
            + " must find rare sum, got: "
            + report,
        )


def test_targeted_report_is_deterministic() raises:
    var first = String("")
    var second = String("")
    try:
        for_all(_rare_sum_targeted, Settings(max_examples=100, seed=UInt64(42)))
    except e:
        first = String(e)
    try:
        for_all(_rare_sum_targeted, Settings(max_examples=100, seed=UInt64(42)))
    except e:
        second = String(e)
    assert_true(first.byte_length() > 0, msg="must find a counterexample")
    assert_equal(first, second)


def test_target_passing_property_raises_nothing() raises:
    for_all(_targeted_passes, Settings(max_examples=20, seed=UInt64(1)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
