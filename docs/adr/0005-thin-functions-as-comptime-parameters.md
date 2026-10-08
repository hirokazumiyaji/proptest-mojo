# ADR-0005: Pass combinator functions as thin comptime parameters

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/strategies.md](../specs/strategies.md), [specs/coding-guidelines.md](../specs/coding-guidelines.md)

## Context

`map`, `filter`, and `flat_map` need to retain user functions within a strategy. Experiments with Mojo 1.2.0.dev2026092605 produced these results:

| Storage method | Result |
|----------------|--------|
| Store a capturing closure in a field `var f: Self.F` with type parameter `F: def(T) -> U` | Closure types are not `Copyable`, so they cannot satisfy the `Copyable` requirement for strategies. Type inference also fails when the type includes an associated type. |
| Store a thin function pointer in a field `var f: def(Self.S.Value) thin -> Self.U` | Works. |
| Make the thin function a comptime parameter `f: def(S.Value) thin -> U` | Works. `S` and `U` are also inferred in expressions such as `map[show](map[double](s))`. |
| Use a trait default method such as `s.map[f]()` | Does not compile because a function parameter with a dependent type does not match the trait requirement. |

## Decision

- Make `map`, `filter`, and `flat_map` free functions that take non-capturing (thin) functions as comptime parameters.

  ```mojo
  def map[S: Strategy, U: ..., //, f: def(S.Value) thin -> U](s: S) -> Map[S, U, f]
  ```

- For transformations that depend on external values and need captures, use a composed strategy with parameters stored in fields (a user-defined struct implementing `Strategy`). Document this as the standard pattern corresponding to Hypothesis `@composite` and proptest `prop_compose!`.

## Alternatives Considered

- Store a runtime thin function pointer in a field: works, but loses inlining opportunities compared with a comptime parameter. The benefit of removing one type parameter is small because type inference works.
- Accept capturing closures: the current compiler cannot store them.

## Consequences

- Functions passed to combinators are top-level or module-level pure functions, which fits the functional style.
- Cases that need captures require the more verbose step of defining a composed strategy.
- If the compiler supports storing capturing closures or trait default methods, consider adding a method-chain API in a separate ADR.
