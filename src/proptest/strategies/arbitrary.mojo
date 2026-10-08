"""Per-type default strategies (`Arbitrary`).

Implements the `Arbitrary` section of
`docs/specs/strategies.md`: `arbitrary[T]()` returns the default strategy
for the value type `T`, so properties can draw values without naming a
strategy explicitly.

Builtin defaults:

| `T`                | strategy                       | simplest value |
|--------------------|--------------------------------|----------------|
| `Int`              | `integers(Int.MIN, Int.MAX)`   | `0`            |
| `Bool`             | `booleans()`                   | `False`        |
| `Float64`          | `floats()` (unbounded)         | `0.0`          |
| `String`           | `text()` (default alphabet)    | `""`           |
| `List[E]` (below)  | `lists(arbitrary[E]())`        | `[]`           |

Static dispatch cannot decompose `List[E]` for an abstract `E` (there is
no way to name "the element type of `T`" as a compile-time parameter),
so the list default enumerates concrete element types (`Int`, `Bool`,
`Float64`, `String`, and one level of nesting for `List[List[Int]]`).
Lifting this to arbitrary nesting is follow-up work alongside the
recursive-strategy investigation in the spec.

User-defined types opt in by conforming to `Arbitrary` and implementing
its static `arbitrary(tc)` method. Use `tc.draw(arbitrary[UserId]())` to
obtain a strategy whose value type is `UserId`.
"""

from proptest.strategy import Strategy, kind_label
from proptest.strategies.collections import lists
from proptest.strategies.floats import floats
from proptest.strategies.primitives import booleans, integers
from proptest.strategies.text import text
from proptest.testcase import TestCase


trait Arbitrary(Copyable, Deinitable, Writable):
    """Value type with a default strategy.

    Conform to this trait to generate values of the conforming type.
    `arbitrary[T]()` wraps this method in a strategy.
    """

    @staticmethod
    def arbitrary(mut tc: TestCase) raises -> Self:
        ...


struct ArbitraryStrategy[T: Copyable & Writable & Deinitable](Strategy):
    """Default strategy for a builtin value type `T`.

    See `arbitrary` for the type-to-strategy mapping. Drawing an
    unsupported type raises.
    """

    comptime Value = Self.T

    def __init__(out self):
        pass

    def span_label(self) -> UInt64:
        return kind_label("arbitrary")

    def draw(self, mut tc: TestCase) raises -> Self.T:
        comptime if Self.T == Int:
            var v = tc.draw(integers(Int.MIN, Int.MAX))
            return rebind[Self.T](v).copy()
        elif Self.T == Bool:
            var v = tc.draw(booleans())
            return rebind[Self.T](v).copy()
        elif Self.T == Float64:
            var v = tc.draw(floats())
            return rebind[Self.T](v).copy()
        elif Self.T == String:
            var v = tc.draw(text())
            return rebind[Self.T](v^).copy()
        elif Self.T == List[Int]:
            var v = tc.draw(lists(arbitrary[Int]()))
            return rebind[Self.T](v^).copy()
        elif Self.T == List[Bool]:
            var v = tc.draw(lists(arbitrary[Bool]()))
            return rebind[Self.T](v^).copy()
        elif Self.T == List[Float64]:
            var v = tc.draw(lists(arbitrary[Float64]()))
            return rebind[Self.T](v^).copy()
        elif Self.T == List[String]:
            var v = tc.draw(lists(arbitrary[String]()))
            return rebind[Self.T](v^).copy()
        elif Self.T == List[List[Int]]:
            var v = tc.draw(lists(arbitrary[List[Int]]()))
            return rebind[Self.T](v^).copy()
        elif conforms_to(Self.T, Arbitrary):
            return Self.T.arbitrary(tc)
        else:
            raise Error("arbitrary: unsupported type")


def arbitrary[T: Copyable & Writable & Deinitable]() -> ArbitraryStrategy[T]:
    """Default strategy for the builtin value type `T`.

    `tc.draw(arbitrary[List[Int]]())` draws a list of full-range `Int`
    values shrinking toward `[]` of `0`s. Drawing a type outside the
    builtin table raises; user-defined types conform to `Arbitrary`
    instead.
    """
    return ArbitraryStrategy[T]()
