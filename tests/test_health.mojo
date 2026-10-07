"""Health checks and verbosity for the generation loop.

Covers the M4 table in `docs/specs/runner.md`: too many rejections
(`assume` or an unsatisfiable `filter`, which rejects the same way),
too many overruns, no valid execution at all, plus `Verbosity` and the
shrink-budget note in the falsifying report.
"""

from proptest import Settings, Status, TestCase, Verbosity, for_all, integers
from proptest.runner import _format_example_line
from proptest.strategy import Strategy, kind_label
from std.testing import TestSuite, assert_equal, assert_true


struct RejectAll(Strategy):
    """Strategy rejecting every draw, like an unsatisfiable `filter`."""

    comptime Value = Int

    def __init__(out self):
        pass

    def span_label(self) -> UInt64:
        return kind_label("rejectall")

    def draw(self, mut tc: TestCase) raises -> Int:
        var x = tc.draw(integers(0, 10), "x")
        tc.assume(x < 0)
        return x


def _reject_everything(mut tc: TestCase) raises:
    tc.assume(False)


def _filtered_out(mut tc: TestCase) raises:
    _ = tc.draw(RejectAll(), "y")


def _small_values_only(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    var y = tc.draw(integers(0, 10000), "y")
    tc.assume(x == 0 and y == 0)


def _draws_three_integers(mut tc: TestCase) raises:
    var total = 0
    for _ in range(3):
        total += tc.draw(integers(0, 100), "n")
    tc.note("total=" + String(total))


def _verbose_passes(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 5), "x")
    tc.note("saw x=" + String(x))


def _fails_large(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def _run_and_capture[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings) raises -> String:
    var report = String("")
    try:
        for_all(prop, settings)
    except e:
        report = String(e)
    return report^


def test_verbosity_levels_render() raises:
    assert_equal(String(Verbosity.QUIET), "QUIET")
    assert_equal(String(Verbosity.NORMAL), "NORMAL")
    assert_equal(String(Verbosity.VERBOSE), "VERBOSE")
    assert_true(
        Verbosity.QUIET != Verbosity.NORMAL, msg="QUIET differs from NORMAL"
    )
    assert_true(
        Verbosity.NORMAL != Verbosity.VERBOSE, msg="NORMAL differs from VERBOSE"
    )


def test_verbosity_defaults_to_normal() raises:
    var settings = Settings()
    assert_true(settings.verbosity == Verbosity.NORMAL, msg="default is NORMAL")
    assert_true(
        ("verbosity=NORMAL" in String(settings)),
        msg="Settings shows verbosity: " + String(settings),
    )


def test_always_reject_reports_rejection_rate() raises:
    var report = _run_and_capture(
        _reject_everything, Settings(seed=UInt64(1), max_examples=5)
    )
    assert_true(
        ("100% rejection rate" in report),
        msg="expected rejection rate, got: " + report,
    )
    assert_true(
        ("without a single valid execution" in report),
        msg="expected no-valid diagnosis, got: " + report,
    )
    assert_true(
        ("unable to generate input" in report),
        msg="expected unable-to-generate note, got: " + report,
    )


def test_filter_like_strategy_reports_rejection_rate() raises:
    var report = _run_and_capture(
        _filtered_out, Settings(seed=UInt64(1), max_examples=5)
    )
    assert_true(
        ("100% rejection rate" in report),
        msg="expected rejection rate, got: " + report,
    )
    assert_true(
        ("assume/filter" in report),
        msg="expected filter mention, got: " + report,
    )


def test_strict_assume_after_valid_reports_rate() raises:
    var report = _run_and_capture(
        _small_values_only, Settings(seed=UInt64(11), max_examples=3)
    )
    assert_true(
        ("rejection rate" in report),
        msg="expected rejection rate, got: " + report,
    )
    assert_true(
        ("assume/filter condition too strict" in report),
        msg="expected too-strict diagnosis, got: " + report,
    )


def test_overrun_reports_data_too_large() raises:
    var report = _run_and_capture(
        _draws_three_integers, Settings(seed=UInt64(1), max_choices=1)
    )
    assert_true(
        ("overran max_choices=1" in report),
        msg="expected overrun count, got: " + report,
    )
    assert_true(
        ("overrun rate" in report), msg="expected overrun rate, got: " + report
    )
    assert_true(
        ("unable to generate input" in report),
        msg="expected no-valid diagnosis, got: " + report,
    )


def test_verbose_run_completes_and_shows_examples() raises:
    for_all(
        _verbose_passes,
        Settings(seed=UInt64(7), max_examples=5, verbosity=Verbosity.VERBOSE),
    )


def test_quiet_run_stays_silent_and_completes() raises:
    for_all(
        _verbose_passes,
        Settings(seed=UInt64(7), max_examples=5, verbosity=Verbosity.QUIET),
    )


def test_example_line_formats_draws() raises:
    var labels = List[String]()
    labels.append(String("x"))
    labels.append(String(""))
    var values = List[String]()
    values.append(String("3"))
    values.append(String("False"))
    assert_equal(
        _format_example_line(2, Status.VALID, labels.copy(), values.copy()),
        "example 2: VALID (x = 3, draw #2 = False)",
    )
    var empty_labels = List[String]()
    var empty_values = List[String]()
    assert_equal(
        _format_example_line(
            4, Status.INVALID, empty_labels.copy(), empty_values.copy()
        ),
        "example 4: INVALID",
    )


def test_shrink_budget_cutoff_noted_in_report() raises:
    var report = _run_and_capture(
        _fails_large,
        Settings(seed=UInt64(1), max_shrink_evaluations=1),
    )
    assert_true(
        ("Shrink budget exhausted" in report),
        msg="expected budget note, got: " + report,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
