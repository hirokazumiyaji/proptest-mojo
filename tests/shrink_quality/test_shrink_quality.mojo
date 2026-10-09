"""End-to-end shrink quality regression tests (M3).

Per `docs/specs/shrinking.md`, each problem below has a known minimal
counterexample; `for_all` with a fixed seed must reproduce it. The
evaluation budget is capped per test: exceeding it would either leave a
non-minimal counterexample or add the budget-exhausted note to the
report, so asserting the minimal rendering and the absence of that note
verifies both quality and cost.
"""

from proptest import Settings, TestCase, for_all, integers, lists
from proptest.strategy import Strategy, kind_label
from std.testing import TestSuite, assert_true


comptime _AB_ELEMENT_LABEL = UInt64(0x4142456C656D656E)


@fieldwise_init
struct ABText(Strategy):
    """Two-letter strings over `{"a", "b"}` with `"a"` simplest.

    A minimal stand-in for the `text` strategy (which lives on another
    branch): length uses the same continue-flag encoding as `lists`, so
    span deletion removes one character, and choice 0 draws `"a"`, so
    minimization drives characters toward `"a"`.
    """

    comptime Value = String
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def span_label(self) -> UInt64:
        return kind_label("ab_text")

    def draw(self, mut tc: TestCase) raises -> String:
        var out = String("")
        var count = 0
        var p_continue: Float64 = 0.0
        if self.average_size > 0.0:
            p_continue = self.average_size / (1.0 + self.average_size)
        while True:
            tc.start_span(_AB_ELEMENT_LABEL)
            try:
                var cont: Bool
                if count >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif count < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
                if not cont:
                    tc.stop_span(discard=True)
                    break
                var v = tc.draw_integer(UInt64(1))
                if v == UInt64(0):
                    out += "a"
                else:
                    out += "b"
                count += 1
                tc.stop_span()
            except e:
                tc.stop_span()
                raise e
        return out^


def _fails_sum_over_1000(mut tc: TestCase) raises:
    var xs = tc.draw(lists(integers(0, 1000)), "xs")
    var total = 0
    for i in range(len(xs)):
        total += xs[i]
    if total > 1000:
        raise Error("sum too big: " + String(xs))


def _fails_at_1000(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    if x >= 1000:
        raise Error("too big")


def _fails_length(mut tc: TestCase) raises:
    var xs = tc.draw(lists(integers(0, 100)), "xs")
    if len(xs) >= 3:
        raise Error("too long: " + String(xs))


def _fails_sorted(mut tc: TestCase) raises:
    var xs = tc.draw(lists(integers(0, 10)), "xs")
    for i in range(1, len(xs)):
        if xs[i] < xs[i - 1]:
            raise Error("unsorted: " + String(xs))


def _fails_pair_sum(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 100), "x")
    var y = tc.draw(integers(0, 100), "y")
    if x + y > 10:
        raise Error("pair sum too big")


def _fails_on_a(mut tc: TestCase) raises:
    var s = tc.draw(ABText(0, 8, 4.0), "s")
    if "a" in s:
        raise Error("contains a: " + s)


def _report_capped[
    P: def(mut TestCase) raises -> None
](prop: P, seed: UInt64, shrink_budget: Int) raises -> String:
    var report = String("")
    try:
        for_all(
            prop,
            Settings(seed=seed, max_shrink_evaluations=shrink_budget),
        )
    except e:
        report = String(e)
    return report^


def _assert_minimal(report: String, expected: String) raises:
    assert_true(report.byte_length() > 0, msg="must find a counterexample")
    assert_true(
        (expected in report),
        msg="expected " + expected + ", got: " + report,
    )
    assert_true(
        not ("budget exhausted" in report),
        msg="shrink must finish within budget: " + report,
    )


def test_sum_shrinks_to_one_and_thousand() raises:
    _assert_minimal(
        _report_capped(_fails_sum_over_1000, UInt64(1), 2500), "xs = [1, 1000]"
    )


def test_single_integer_shrinks_to_bound() raises:
    _assert_minimal(_report_capped(_fails_at_1000, UInt64(2), 1100), "x = 1000")


def test_length_shrinks_to_three_zeros() raises:
    _assert_minimal(
        _report_capped(_fails_length, UInt64(3), 200), "xs = [0, 0, 0]"
    )


def test_unsorted_shrinks_to_one_zero() raises:
    _assert_minimal(
        _report_capped(_fails_sorted, UInt64(4), 150), "xs = [1, 0]"
    )


def test_pair_sum_redistributes_to_zero_eleven() raises:
    var report = _report_capped(_fails_pair_sum, UInt64(5), 150)
    _assert_minimal(report, "x = 0")
    _assert_minimal(report, "y = 11")


def test_string_without_a_shrinks_to_a() raises:
    _assert_minimal(_report_capped(_fails_on_a, UInt64(6), 100), "s = a")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
