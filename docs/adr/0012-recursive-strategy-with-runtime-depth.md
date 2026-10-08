# ADR-0012: Implement recursive strategies with one struct and a runtime depth limit

- Status: Accepted
- Date: 2026-09-30
- Related: Issue #29, [specs/strategies.md](../specs/strategies.md), [ADR-0003](0003-strategy-trait-with-static-dispatch.md)

## Context

We need to generate recursive data such as trees. With static dispatch (ADR-0003), a naive recursive type such as `Tree = OneOf[Leaf, Node[Tree]]` cannot be written because its type nests infinitely. As noted under Planned in `specs/strategies.md`, a spike compared limiting depth with type parameters against limited type erasure (`mojo 1.2.0.dev2026092605`, tested only in a worktree and not committed).

Results:

- **Depth as a type parameter:** nested `Branch[S: Strategy](Strategy) where S.Value == Int` compiled and ran. However, each depth requires a different type (`OneOf2[Integers, Branch[OneOf2[...]]]`), so type names grow with depth. The recursive value type itself is also a problem (`List[Self]` is rejected with `field 'children' has non-'Deinitable' type`), so type-level recursion alone cannot produce JSON-like values.
- **Limited type erasure:** `def(...) -> T` is treated as a trait and cannot be stored in a struct field (ADR-0003), so a single `Gen[T]` type is not possible. Erasure with `ArcPointer` and a hand-written vtable would add unsafe code, so it was not chosen.
- **Runtime depth limit:** indirect references using `List[ArcPointer[Self]]` instead of `List[Self]` allow a concrete recursive value type, `JsonValue` (null, integers, and arrays), to compile and run. One `JsonTree` strategy for that type stops recursion using a runtime `max_depth` field. There is only one strategy type. We also confirmed that all-zero choices produce `null` and that depth and width limits fit within the choice budget.

## Decision

- Express recursion at the value level rather than the type level. Put the concrete recursive value `JsonValue` and a single `JsonTree` strategy with a runtime depth budget in `src/proptest/strategies/recursive.mojo`.
- Store `JsonValue` children through `ArcPointer` indirection; do not introduce an unsafe vtable. Treat values as immutable after `draw`, and do not observe sharing between copies.
- Encode `node(depth)` as a branch flag (0 = leaf, 1 = array); a leaf draws a kind (0 = null, 1 = integer); an array draws a width (`0..max_width`) and its children recursively. At depth 0, do not consume a branch flag. All-zero choices produce `null`.
- Do not create a generic `prop_recursive(leaf, branch)` combinator. Branch construction varies by value type, and the inner strategy type must be statically determined (the same constraint as `flat_map`), so a single struct is more honest. Write a bespoke strategy like `JsonTree` for each recursive shape.

## Alternatives Considered

- Limit depth with a type parameter: works, but adds a new type at every depth and leaves the recursive value-type problem unresolved. Type names become impractical for deep trees.
- Erase strategy types with `ArcPointer` and a hand-written vtable: rejected in ADR-0003 because it adds unsafe code. Safe indirection for values was sufficient.
- Generate JSON as a `String`: avoids recursive value types, but checking structure (depth and element count) requires parsing strings and loses locality when shrinking.

## Consequences

- `json_tree(max_depth, max_width, minimum, maximum)` generates JSON-like trees that shrink to simple trees such as `[]` and `null` (covered by the `for_all` regression test in `tests/test_recursive.mojo`).
- Each recursive shape needs its own value type and strategy. The `Arbitrary` trait (M5) remains Planned.
- Child draws are wrapped in the `JSON_CHILD_SPAN` span. The current shrink passes (M1) ignore spans, but span-aware passes planned for M3 can operate on individual elements.
