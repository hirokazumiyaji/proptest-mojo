"""Small example of a passing property and a minimized counterexample."""

from proptest import Settings, TestCase, for_all, integers


def _addition_commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-1000, 1000), "a")
    var b = tc.draw(integers(-1000, 1000), "b")
    if a + b != b + a:
        raise Error("addition must commute")


def _below_limit(mut tc: TestCase) raises:
    var value = tc.draw(integers(0, 10000), "value")
    if value >= 1000:
        raise Error("value reached 1000: " + String(value))


def main() raises:
    for_all(_addition_commutes, Settings(seed=UInt64(1), max_examples=20))
    print("addition commutes")

    var report = String("")
    try:
        for_all(_below_limit, Settings(seed=UInt64(1), max_examples=100))
    except e:
        report = String(e)
    if report.byte_length() == 0:
        raise Error("failing property did not produce a counterexample")
    print("counterexample after shrinking:")
    print(report)
