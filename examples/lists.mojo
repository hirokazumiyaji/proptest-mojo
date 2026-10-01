"""Composite strategies: build your own, e.g. lists of integers.

`map` / `filter` / `flat_map` cover pure transforms, but capturing
parameters (bounds, sizes, alphabets) belong in a composite `Strategy`
struct holding them as fields. This example builds small integer lists
that way and tests two list properties.

Run with: pixi run mojo run -I src examples/lists.mojo
"""

from proptest import Settings, TestCase, for_all, integers
from proptest.strategy import Strategy


@fieldwise_init
struct IntLists(Strategy):
    """Lists of `length in [0, max_size]`, elements in `[minimum, maximum]`."""

    comptime Value = List[Int]
    var minimum: Int
    var maximum: Int
    var max_size: Int

    def draw(self, mut tc: TestCase) raises -> List[Int]:
        var size = tc.draw(integers(0, self.max_size), "size")
        var out = List[Int]()
        for _ in range(size):
            out.append(tc.draw(integers(self.minimum, self.maximum), "item"))
        return out^


def is_sorted(xs: List[Int]) -> Bool:
    for i in range(1, len(xs)):
        if xs[i - 1] > xs[i]:
            return False
    return True


def reversed_copy(xs: List[Int]) -> List[Int]:
    var out = List[Int]()
    for i in range(len(xs)):
        out.append(xs[len(xs) - 1 - i].copy())
    return out^


def _double_reverse_is_identity(mut tc: TestCase) raises:
    var xs = tc.draw(IntLists(-10, 10, 8), "xs")
    var twice = reversed_copy(reversed_copy(xs))
    if twice != xs:
        raise Error("double reverse changed the list: " + String(xs))


def _every_list_is_sorted(mut tc: TestCase) raises:
    var xs = tc.draw(IntLists(-10, 10, 8), "xs")
    if not is_sorted(xs):
        raise Error("unsorted: " + String(xs))


def main() raises:
    for_all(
        _double_reverse_is_identity, Settings(seed=UInt64(3), max_examples=50)
    )
    print("composite: double reverse is the identity on small int lists")
    var raised = False
    try:
        for_all(_every_list_is_sorted, Settings(seed=UInt64(3)))
    except e:
        raised = True
        print("composite: the sortedness claim shrinks to:")
        print(String(e))
    if not raised:
        raise Error("expected _every_list_is_sorted to raise but it passed")
