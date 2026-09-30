"""map / filter / flat_map: derive new strategies from old ones.

Run with: pixi run mojo run -I src examples/combinators.mojo
"""

from proptest import Integers, Settings, TestCase, for_all, integers
from proptest.strategies.combinators import filter, flat_map, map


def double(x: Int) -> Int:
    return x * 2


def is_even(x: Int) -> Bool:
    return x % 2 == 0


def capped(n: Int) -> Integers:
    return Integers(0, n)


def _doubled_is_even(mut tc: TestCase) raises:
    var y = tc.draw(map[double](integers(0, 100)), "y")
    if y % 2 != 0:
        raise Error("map broke parity: y=" + String(y))


def _filtered_is_even(mut tc: TestCase) raises:
    var z = tc.draw(filter[is_even](integers(0, 100)), "z")
    if z % 2 != 0:
        raise Error("filter let an odd value through: z=" + String(z))


def _capped_reaches_five(mut tc: TestCase) raises:
    var w = tc.draw(flat_map[capped](integers(0, 10)), "w")
    if w >= 5:
        raise Error("too big: w=" + String(w))


def main() raises:
    for_all(_doubled_is_even, Settings(seed=UInt64(7), max_examples=50))
    print("map: doubled draws are always even")
    for_all(_filtered_is_even, Settings(seed=UInt64(7), max_examples=50))
    print("filter: rejected odds never reach the property")
    try:
        for_all(_capped_reaches_five, Settings(seed=UInt64(7)))
    except e:
        print("flat_map: dependent bound shrinks to the minimal failure:")
        print(String(e))
