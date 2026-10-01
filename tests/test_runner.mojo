from proptest import Settings, TestCase, for_all, integers
from std.os import getenv, setenv
from std.testing import TestSuite, assert_equal, assert_true


def _always_passes(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))


def _fails_at_1000(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def _fails_on_zero(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    if x == 0:
        raise Error("zero")


def _even_and_small(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.assume(x % 2 == 0)
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def _report_of[
    P: def(mut TestCase) raises -> None
](prop: P, seed: UInt64) raises -> String:
    # Thin (capture-free) properties route through here; capturing ones
    # call for_all directly in their own test.
    var report = String("")
    try:
        for_all(prop, Settings(seed=seed))
    except e:
        report = String(e)
    return report^


def test_settings_defaults_match_spec() raises:
    var settings = Settings()
    assert_equal(settings.max_examples, 100)
    assert_true(settings.seed is None, msg="default seed is None")
    assert_equal(settings.max_choices, 8192)
    assert_equal(settings.max_shrink_evaluations, 5000)
    assert_equal(settings.effective_max_examples(), 100)
    assert_equal(
        String(settings),
        (
            "Settings(max_examples=100, seed=None,"
            " max_choices=8192, max_shrink_evaluations=5000,"
            " verbosity=NORMAL)"
        ),
    )


def test_settings_explicit_values_win_over_env() raises:
    var saved_seed = getenv("PROPTEST_SEED")
    var saved_count = getenv("PROPTEST_MAX_EXAMPLES")
    _ = setenv("PROPTEST_SEED", "777")
    _ = setenv("PROPTEST_MAX_EXAMPLES", "7")
    var default_seed = UInt64(0)
    var default_count = 0
    var explicit_seed = UInt64(0)
    var explicit_count = 0
    var failure = String("")
    try:
        var defaulted = Settings()
        default_seed = defaulted.effective_seed()
        default_count = defaulted.effective_max_examples()
        var explicit = Settings(seed=UInt64(1), max_examples=3)
        explicit_seed = explicit.effective_seed()
        explicit_count = explicit.effective_max_examples()
    except e:
        failure = String(e)
    _ = setenv("PROPTEST_SEED", saved_seed)
    _ = setenv("PROPTEST_MAX_EXAMPLES", saved_count)
    if failure.byte_length() > 0:
        raise Error(failure)
    assert_equal(default_seed, UInt64(777))
    assert_equal(default_count, 7)
    assert_equal(explicit_seed, UInt64(1))
    assert_equal(explicit_count, 3)


def test_passing_property_raises_nothing() raises:
    for_all(_always_passes, Settings(seed=UInt64(1), max_examples=20))


def test_finds_and_shrinks_to_1000() raises:
    var report = _report_of(_fails_at_1000, UInt64(1))
    assert_true(
        ("x = 1000" in report), msg="expected minimal x, got: " + report
    )
    assert_true(
        ("note: saw x=1000" in report), msg="expected replayed note: " + report
    )
    assert_true(("Seed: 1" in report), msg="expected seed line: " + report)


def test_same_seed_gives_same_report() raises:
    var first = _report_of(_fails_at_1000, UInt64(42))
    var second = _report_of(_fails_at_1000, UInt64(42))
    assert_true(
        first.byte_length() > 0, msg="first run must find a counterexample"
    )
    assert_equal(first, second)


def test_first_example_is_all_zero() raises:
    var report = _report_of(_fails_on_zero, UInt64(999))
    assert_true(("x = 0" in report), msg="all-zero example fails: " + report)
    assert_true(
        ("after 1 examples" in report), msg="no generation needed: " + report
    )


def test_assume_rejections_are_skipped() raises:
    var report = _report_of(_even_and_small, UInt64(3))
    assert_true(
        ("x = 1000" in report), msg="minimal even failure, got: " + report
    )


def test_capturing_closure_property() raises:
    var limit = 1000

    def prop(mut tc: TestCase) raises {imm limit}:
        var x = tc.draw(integers(0, 10000), "x")
        if x >= limit:
            raise Error("too big: x=" + String(x))

    var report = String("")
    try:
        for_all(prop, Settings(seed=UInt64(2)))
    except e:
        report = String(e)
    assert_true(("x = 1000" in report), msg="captured limit applies: " + report)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
