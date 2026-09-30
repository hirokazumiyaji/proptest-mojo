"""Minimal proptest-mojo usage: one passing and one shrinking property."""

from proptest import Settings, TestCase, for_all, integers


def _commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-1000, 1000), "a")
    var b = tc.draw(integers(-1000, 1000), "b")
    if a + b != b + a:
        raise Error("addition must commute")


def _too_big(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def main() raises:
    for_all(_commutes, Settings(seed=UInt64(1), max_examples=20))
    print("passing property held: addition commutes")
    try:
        for_all(_too_big, Settings(seed=UInt64(1), max_examples=100))
        print("ERROR: failing property unexpectedly passed")
    except e:
        print("failing property shrunk to minimal counterexample:")
        print(String(e))
