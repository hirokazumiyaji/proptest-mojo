"""Generation tweaks: edge bias and size ramp (runner.md M4)."""

from proptest import Settings, TestCase, for_all, integers, lists
from proptest.choice import ChoiceKind
from proptest.prng import Xoshiro256StarStar, derive
from proptest.strategies.floats import lex_to_float
from proptest.testcase import FLOAT_ONE_BITS
from std.testing import TestSuite, assert_equal, assert_true


def _fails_only_at_max(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 1000000), "x")
    if x == 1000000:
        raise Error("hit max")


def _fails_only_at_i64max(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 9223372036854775807), "x")
    if x == 9223372036854775807:
        raise Error("hit max")


def test_edge_only_failure_found_within_default_max_examples() raises:
    var report = String("")
    try:
        for_all(_fails_only_at_max, Settings(seed=UInt64(1)))
    except e:
        report = String(e)
    assert_true(
        ("x = 1000000" in report),
        msg="edge-only failure must be found, got: " + report,
    )


def test_i64max_edge_only_failure_found() raises:
    var report = String("")
    try:
        for_all(_fails_only_at_i64max, Settings(seed=UInt64(1)))
    except e:
        report = String(e)
    assert_true(
        ("x = 9223372036854775807" in report),
        msg="i64_max edge must be found, got: " + report,
    )


def test_edge_bias_hits_edges() raises:
    var tc = TestCase.generating(
        derive(UInt64(123), UInt64(1)), 8192, UInt64(1)
    )
    var hits = 0
    for _ in range(200):
        var v = tc.draw_integer(UInt64(1000000))
        if (
            v == UInt64(0)
            or v == UInt64(1)
            or v == UInt64(1000000)
            or v == UInt64(999999)
        ):
            hits += 1
    assert_true(hits > 0, msg="biased draws must hit edges")
    assert_equal(len(tc), 200)


def test_bias_records_single_choice_and_replays() raises:
    var gen = TestCase.generating(derive(UInt64(5), UInt64(2)), 8192, UInt64(2))
    var values = List[UInt64]()
    for _ in range(8):
        values.append(gen.draw_integer(UInt64(1000)))
    assert_equal(len(gen), 8)
    assert_equal(len(gen.choices), 8)
    var replay = TestCase.replaying(gen.choices.copy())
    for i in range(8):
        assert_equal(replay.draw_integer(UInt64(1000)), values[i])
    assert_equal(replay.choices, gen.choices)


def test_float_edge_slot_one_is_numeric_unity() raises:
    # Deterministic PRNG state that selects the biased path and edge slot 1.
    # Slot 1 must encode +1.0's magnitude bits, not UInt64(1) (subnormal).
    var tc = TestCase.generating(
        Xoshiro256StarStar(
            s0=UInt64(72057594037927936),
            s1=UInt64(0),
            s2=UInt64(0),
            s3=UInt64(0),
        )
    )
    var code = tc.draw_float_bits()
    assert_equal(code, FLOAT_ONE_BITS)
    assert_equal(lex_to_float(code), 1.0)
    assert_equal(len(tc.choices), 1)
    assert_equal(tc.choices[0].kind, ChoiceKind.FLOAT)
    assert_equal(tc.choices[0].value, FLOAT_ONE_BITS)
    var replay = TestCase.replaying(tc.choices.copy())
    assert_equal(replay.draw_float_bits(), FLOAT_ONE_BITS)
    assert_equal(replay.choices, tc.choices)


def test_size_scale_ramps_with_example_index() raises:
    var early = TestCase.generating(
        derive(UInt64(1), UInt64(1)), 8192, UInt64(1)
    )
    var late = TestCase.generating(
        derive(UInt64(1), UInt64(1)), 8192, UInt64(100)
    )
    assert_true(
        early.size_scale() < late.size_scale(),
        msg="early examples must use a smaller scale",
    )
    assert_equal(late.size_scale(), 1.0)


def test_early_examples_draw_shorter_lists() raises:
    var early_total = 0
    var late_total = 0
    var n = 40
    for s in range(n):
        var ec = TestCase.generating(
            derive(UInt64(s), UInt64(7)), 8192, UInt64(1)
        )
        var xs = ec.draw(lists(integers(0, 10), min_size=0, max_size=32))
        early_total += len(xs)
        var lc = TestCase.generating(
            derive(UInt64(s), UInt64(7)), 8192, UInt64(100)
        )
        var ys = lc.draw(lists(integers(0, 10), min_size=0, max_size=32))
        late_total += len(ys)
    assert_true(
        early_total < late_total,
        msg="early total "
        + String(early_total)
        + " must be shorter than late total "
        + String(late_total),
    )


def test_replay_ignores_size_scale() raises:
    var gen = TestCase.generating(derive(UInt64(9), UInt64(3)), 8192, UInt64(1))
    var strategy = lists(integers(0, 10), min_size=0, max_size=8)
    var xs = gen.draw(strategy)
    var replay = TestCase.replaying(gen.choices.copy(), 8192, UInt64(100))
    var ys = replay.draw(strategy)
    assert_equal(xs, ys)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
