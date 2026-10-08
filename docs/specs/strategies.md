# Strategies

See [ADR-0003](../adr/0003-strategy-trait-with-static-dispatch.md), [ADR-0005](../adr/0005-thin-functions-as-comptime-parameters.md), and [ADR-0012](../adr/0012-recursive-strategy-with-runtime-depth.md).

## The `Strategy` Trait

```mojo
trait Strategy(Copyable, Deinitable):
    comptime Value: Copyable & Writable & Deinitable

    def span_label(self) -> UInt64:
        ...

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        ...
```

`span_label` is a `UInt64` label identifying the kind of strategy. It is used as the `label` of spans created automatically by `tc.draw`. It is independent of the reporting label (`label` in `tc.draw(strategy, label)`) and depends only on the strategy kind. Implementations return `kind_label("<kind>")`.

`span_label` is required and has no default. A common default would give every strategy that omitted an implementation the same label, causing sibling draws to be treated as compatible again.

Every strategy implementation must follow these rules.

| Rule | Reason |
|------|------|
| **Determinism**: Produce the same value from the same choice sequence. Do not read state outside `TestCase` (global variables, time, `std.random`). | Shrinking and replay must depend only on the choice sequence. |
| **Monotonic simplicity**: Smaller choices produce simpler values. All-zero choices produce the simplest value. | Smaller choice sequences in shortlex order should correspond to simpler counterexamples for people to understand. |
| **Immutability**: `draw` does not mutate `self`. | Strategies are freely copied and shared as values. |
| **Locality**: Create a span for each structural unit (such as one collection element). | Structural shrinking passes depend on spans. |
| **Structural labels**: `span_label` depends only on the strategy kind, not the reporting label. | Shrinking passes swap spans they consider to be of the same kind. |

## Built-in Strategies

“M” in the table identifies the implementation milestone.

| Function | Value type | Shrinking target | M |
|------|--------|-----------|---|
| `integers(min, max)` | `Int` | Value in range closest to 0 | M1 |
| `integers_of[dtype](min, max)` | `Scalar[dtype]`(`Int8` through `UInt64`) | Same; if the range is omitted, use the full range of the type | M2 |
| `booleans()` | `Bool` | `False` | M1 |
| `just(value)` | `T` | (consumes no choices) | M1 |
| `sampled_from(values: List[T])` | `T` | First element | M2 |
| `floats(min, max, allow_nan, allow_infinity)` | `Float64` | 0.0, then small integers, then simple fractions | M2 |
| `text(alphabet, min_size, max_size)` | `String` | Empty string, then toward the first character, `"0"` | M2 |
| `bytes(min_size, max_size)` | `List[UInt8]` | Empty sequence | M2 |
| `lists(elements, min_size, max_size)` | `List[T]` | Short lists with simple elements | M2 |
| `unique_lists(elements, min_size, max_size)` | `List[T]`(`T: Equatable`) | Same | M2 |
| `dicts(keys, values, min_size, max_size)` | `DictList[K, V]`(`K: Equatable`) | Empty dictionary | M2 |
| `tuples(a, b)` / `tuples(a, b, c)` | Values with 2–3 elements | Each element is simple | M2 |
| `optionals(s)` | `Optional[T]` | `None` | M2 |
| `one_of(strategies: List[S])` | `S.Value` | First strategy | M2 |
| `one_of2(a: A, b: B) where A.Value == B.Value` | `A.Value` | First strategy (`a`) | M2 |
| `json_tree(max_depth, max_width, minimum, maximum)` | `JsonValue` | `null` | M2 |

The standard library `Tuple` and `Optional` satisfy `Copyable & Writable & Deinitable`, so they can be used directly as `Strategy.Value`. Counterexamples use their respective `Writable` representations (for example, `(0, 1)` and `None`). `dicts` returns `DictList` (a `List` of pairs with unique keys) rather than `std.Dict` because the current Mojo compiler cannot return `std.Dict` as a value from the associated type of `draw`. This also allows keys that only satisfy `Equatable`.

### Type-Based Defaults

`arbitrary[T]()` selects a default strategy for `Int`, `Bool`, `Float64`, `String`, and supported list types. For a user-defined type, conform to `Arbitrary` and implement a static `arbitrary(tc)` method that returns the type itself. The generic list defaults cover the supported concrete element types and one level of `List[List[Int]]`.

### Integer Encoding

`integers(min, max)` maps distances from the shrink target `t` (the value in range closest to 0) to non-negative integers `k` in the following order.

```text
k:     0   1    2    3    4   ...
Values: t, t+1, t-1, t+2, t-2, ... (skip values that fall outside the range)
```

This gives the monotonic mapping “choice 0 → target value” and “smaller choice → value closer to target,” so shrinking passes can simply lower choices without considering signs.

### Collection Encoding

As with Hypothesis `many`, draw a boolean for whether to continue for each element.

```text
[span: element] continue=1, <element choices...> [/span] [span] continue=1, <...> [/span] continue=0
```

- The probability of continuing is determined by the average length `average_size` (default: `min(max(min_size * 2, min_size + 5), (min_size + max_size) / 2)`).
- Use `forced_integer` to force 1 until `min_size` is reached and force 0 at `max_size`. Forced choices are not shrunk.
- Each element span includes its continue flag, so a span-deletion pass removes one whole element.

### Floating-Point Encoding (M2)

Use the same lexicographic encoding as Hypothesis. Smaller 64-bit choices correspond to simpler floating-point values in this order: 0.0, small non-negative integers, values with small denominators, …, infinity, and NaN. The sign is a separate boolean choice.

## Combinators

These are free functions that accept thin (non-capturing) functions as comptime parameters.

```mojo
def map[S: Strategy, U: Copyable & Writable & Deinitable, //,
        f: def(S.Value) thin -> U](s: S) -> Map[S, U, f]

def filter[S: Strategy, //, p: def(S.Value) thin -> Bool](s: S) -> Filter[S, p]

def flat_map[S: Strategy, T: Strategy, //,
             f: def(S.Value) thin -> T](s: S) -> FlatMap[S, T, f]
```

Example:

```mojo
def double(x: Int) -> Int:
    return x * 2

def is_even(x: Int) -> Bool:
    return x % 2 == 0

def lists_up_to(n: Int) -> ListOf[IntRange]:
    return lists(integers(0, 100), max_size=n)

var evens = map[double](integers(0, 50))
var evens2 = filter[is_even](integers(0, 100))
var sized = flat_map[lists_up_to](integers(0, 10))
```

- `filter` marks the span of an attempt that draws a value failing the predicate as `discarded`, and retries up to three times. If no attempt succeeds, it behaves like `tc.assume(False)` and marks the example `INVALID`.
- `flat_map` creates an inner strategy based on the outer value. The inner strategy’s **type** must be fixed at compile time; only its value parameters may vary.

## Recursive Strategy (`json_tree`)

With static dispatch, types such as `Tree = OneOf[Leaf, Node[Tree]]` nest infinitely. Recursion therefore happens at the value level, not the type level (see [ADR-0012](../adr/0012-recursive-strategy-with-runtime-depth.md)).

```mojo
from proptest.strategies.recursive import JsonValue, json_tree

var tree = json_tree(max_depth=3, max_width=3, minimum=-5, maximum=5)
var value: JsonValue = tc.draw(tree.copy(), "tree")
```

- The `JsonValue` value is a concrete recursive value representing `null`, an integer, or an array. Children are held indirectly through `ArcPointer` and treated as immutable after `draw`.
- The `JsonTree` strategy has one concrete type and stops recursion using a runtime `max_depth` budget. There is no generic `prop_recursive(leaf, branch)` combinator. Write a strategy with the same structure as `JsonTree` for each desired shape.
- The encoding below makes smaller choices simpler. All-zero choices draw `null`. At depth 0, draw only a leaf without consuming a branch flag.

```text
node(depth):
  depth == 0 -> leaf
  depth > 0  -> branch_flag in 0..1 (0 = leaf, 1 = array)
leaf  -> kind in 0..1 (0 = null, 1 = integer in minimum..maximum)
array -> width in 0..max_width, then one child per element
```

- Draw each child inside a `JSON_CHILD_SPAN` span. Current shrinking passes (M1) do not inspect spans, but M3 span-based passes can operate on individual elements.
- `json_tree` raises for `max_depth < 0`, `max_width < 1`, or an empty integer range.

## Composite Strategies (equivalent to `@composite` / `prop_compose!`)

Write transformations that need captures, or generators that combine multiple values, as structs implementing `Strategy`.
This is the recommended pattern.

```mojo
@fieldwise_init
struct User(Copyable, Writable):
    var name: String
    var age: Int

@fieldwise_init
struct Users(Strategy):
    comptime Value = User
    var max_age: Int

    def span_label(self) -> UInt64:
        return kind_label("users")

    def draw(self, mut tc: TestCase) raises -> User:
        var name = tc.draw(text(min_size=1, max_size=20))
        var age = tc.draw(integers(0, self.max_age))
        return User(name^, age)
```

Composite strategies must also implement the required `span_label`. A structure-preserving `map` may reuse the inner strategy’s label. `filter` includes multiple attempts and must return a structural label distinct from the inner strategy.

It is also fine to make several direct `tc.draw` calls in a property. Use a composite strategy only for combinations that should be reused.

## State-Machine Testing

This corresponds to Hypothesis `RuleBasedStateMachine` / `proptest-state-machine`: generate sequences of operations and check that behavior matches a model.

```mojo
trait StateMachine(Movable, Deinitable):
    def num_rules(self) -> Int:
        ...
    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        ...
    def check_invariants(self) raises:
        ...
```

- A struct implementing `StateMachine` stores both the system under test (SUT) and a model (a record of correct behavior) in its fields.
- `run_state_machine(machine, tc, max_ops=32)` draws the number of operations with `integers(0, max_ops)`, draws each rule number from the choice sequence, and calls `run_rule` followed by `check_invariants`. It returns the machine after execution.
- `run_rule` draws arguments with `tc.draw` and expresses preconditions with `tc.assume` (a sequence rejected by `assume` is discarded as `INVALID`). Record each operation with `tc.note` so it appears in counterexample reports.
- All-zero choices produce zero operations. Each operation is wrapped in a span, so operation sequences shrink like collections: minimizing the count removes trailing operations, and chunk deletion removes operations from the middle.

Example: a stack with a bug that returns the first element:

```mojo
struct StackMachine(StateMachine):
    var sut: BuggyStack
    var model: List[Int]

    def num_rules(self) -> Int:
        return 2  # 0: push, 1: pop

    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        if rule == 0:
            var value = tc.draw(integers(0, 10), "push.value")
            tc.note("push(" + String(value) + ")")
            self.sut.push(value)
            self.model.append(value)
        else:
            tc.assume(len(self.model) > 0)
            var got = self.sut.pop()
            var want = self.model.pop()
            tc.note("pop() -> " + String(got))
            if got != want:
                raise Error("pop mismatch")

    def check_invariants(self) raises:
        if len(self.sut.items) != len(self.model):
            raise Error("size mismatch")

def stack_prop(mut tc: TestCase) raises:
    _ = run_state_machine(StackMachine(), tc)
```

The buggy stack above shrinks to three operations: `push(0), push(1), pop`. A shorter sequence cannot create a state with at least two elements, so this counterexample is minimal.

## Planned

- Heterogeneous strategy composition (implemented in M2): strategies of different types with the same `Value` can be combined with `one_of2(a, b)` (see [ADR-0010](../adr/0010-heterogeneous-one-of.md)). Equality is enforced by the trailing `where A.Value == B.Value`; a mismatch is a compile error. For three or more branches, nest `one_of2` or convert the branches to one strategy type and use `one_of`.
- Recursive strategies (implemented in M2): use value-level recursion with a runtime depth limit (see [ADR-0012](../adr/0012-recursive-strategy-with-runtime-depth.md)). `json_tree` generates JSON-like trees and shrinks to `null` when all choices are 0.
