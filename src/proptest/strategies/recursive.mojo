"""Recursive strategies: JSON-like trees with bounded depth.

Implements the recursive row of `docs/specs/strategies.md`
(ADR-0003, ADR-0011).

Static dispatch cannot express an infinitely nested strategy type
(`Tree = OneOf[Leaf, Node[Tree]]`), so recursion lives at the value
level, not the type level. `JsonTree` is a single concrete strategy
holding a runtime `max_depth` budget, and `JsonValue` is a concrete
recursive value using `ArcPointer` indirection for its children.
All-zero choices draw `null`, so shrinking drives trees toward leaves.
"""

from std.io import Writer
from std.memory import ArcPointer

from proptest.strategy import Strategy, kind_label
from proptest.strategies.primitives import Integers, integers
from proptest.testcase import TestCase

comptime JSON_CHILD_SPAN = UInt64(0x4A534F4E4348494C)


@fieldwise_init
struct JsonValue(Copyable, Deinitable, Writable):
    """JSON-like value: null, integer, or array of values.

    Children use `ArcPointer` indirection because Mojo cannot hold
    `List[Self]` directly. Values are treated as immutable after
    `draw`, so the shared ownership of copies is never observed.
    """

    var kind: Int
    var int_value: Int
    var children: List[ArcPointer[Self]]

    def is_null(self) -> Bool:
        return self.kind == 0

    def is_int(self) -> Bool:
        return self.kind == 1

    def is_array(self) -> Bool:
        return self.kind == 2

    def depth(self) -> Int:
        """Nesting depth: 0 for leaves, 1 plus the deepest child."""
        if self.kind != 2:
            return 0
        var deepest = 0
        for i in range(len(self.children)):
            var child_depth = self.children[i][].depth()
            if child_depth > deepest:
                deepest = child_depth
        return deepest + 1

    def node_count(self) -> Int:
        """Total nodes including `self`."""
        if self.kind != 2:
            return 1
        var total = 1
        for i in range(len(self.children)):
            total += self.children[i][].node_count()
        return total

    def write_to(self, mut writer: Some[Writer]):
        if self.kind == 0:
            writer.write("null")
        elif self.kind == 1:
            writer.write(self.int_value)
        else:
            writer.write("[")
            for i in range(len(self.children)):
                if i > 0:
                    writer.write(",")
                writer.write(self.children[i][])
            writer.write("]")


def _null_value() -> JsonValue:
    return JsonValue(0, 0, List[ArcPointer[JsonValue]]())


@fieldwise_init
struct JsonTree(Strategy):
    """Strategy drawing `JsonValue` trees bounded by `max_depth`.

    Encoding (smaller choices are simpler):

    ```text
    node(depth):
      depth == 0 -> leaf
      depth > 0  -> branch_flag in 0..1 (0 = leaf, 1 = array)
    leaf  -> kind in 0..1 (0 = null, 1 = integer in [minimum, maximum])
    array -> width in 0..max_width, then one child per element
    ```

    Each child draws inside its own span for structural shrinking.
    All-zero choices draw `null`. Depth 0 skips the branch flag, so a
    depth-0 strategy only draws leaves.
    """

    comptime Value = JsonValue
    var max_depth: Int
    var max_width: Int
    var leaf_ints: Integers

    def span_label(self) -> UInt64:
        return kind_label("json_value")

    def draw(self, mut tc: TestCase) raises -> JsonValue:
        return self._draw_at_depth(tc, self.max_depth)

    def _draw_at_depth(self, mut tc: TestCase, depth: Int) raises -> JsonValue:
        if depth <= 0:
            return self._draw_leaf(tc)
        var branch = tc.draw_integer(UInt64(1))
        if branch == 0:
            return self._draw_leaf(tc)
        var width = Int(tc.draw_integer(UInt64(self.max_width)))
        var kids = List[ArcPointer[JsonValue]]()
        for _ in range(width):
            tc.start_span(JSON_CHILD_SPAN)
            try:
                var child = self._draw_at_depth(tc, depth - 1)
                kids.append(ArcPointer[JsonValue](child^))
                tc.stop_span()
            except e:
                tc.stop_span()
                raise e
        return JsonValue(2, 0, kids^)

    def _draw_leaf(self, mut tc: TestCase) raises -> JsonValue:
        var kind = tc.draw_integer(UInt64(1))
        if kind == 0:
            return _null_value()
        var value = self.leaf_ints.draw(tc)
        return JsonValue(1, value, List[ArcPointer[JsonValue]]())


def json_tree(
    max_depth: Int = 3,
    max_width: Int = 3,
    minimum: Int = -5,
    maximum: Int = 5,
) raises -> JsonTree:
    """Strategy drawing JSON-like trees of bounded depth and width.

    All-zero choices draw `null`. Raises when `max_depth < 0`,
    `max_width < 1`, or the integer leaf range is empty.
    """
    if max_depth < 0:
        raise Error("json_tree: max_depth must be >= 0")
    if max_width < 1:
        raise Error("json_tree: max_width must be >= 1")
    if maximum < minimum:
        raise Error("json_tree: integer leaf range must be non-empty")
    var leaf_ints = integers(minimum, maximum)
    return JsonTree(max_depth, max_width, leaf_ints^)
