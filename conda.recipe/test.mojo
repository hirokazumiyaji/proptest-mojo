from proptest import VERSION, Settings, TestCase, for_all, integers
from std.testing import assert_equal


def _addition_commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-100, 100), "a")
    var b = tc.draw(integers(-100, 100), "b")
    if a + b != b + a:
        raise Error("addition must commute")


def main() raises:
    assert_equal(VERSION, "0.1.0")
    for_all(_addition_commutes, Settings(seed=UInt64(1), max_examples=10))
