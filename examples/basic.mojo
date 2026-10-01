"""Minimal proptest-mojo usage: one passing and one shrinking property.

Run with: pixi run mojo run -I src examples/basic.mojo
"""

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
    var raised = False
    try:
        for_all(_too_big, Settings(seed=UInt64(1), max_examples=200))
    except e:
        raised = True
        print("failing property shrunk to minimal counterexample:")
        print(String(e))
    if not raised:
        raise Error("expected _too_big to raise but it passed")
