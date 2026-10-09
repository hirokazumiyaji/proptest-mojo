# ADR-0010: Implement heterogeneous `one_of` with `where` clauses and `rebind`

- Status: Accepted
- Date: 2026-09-30
- Related: Issue #14, [specs/strategies.md](../specs/strategies.md), [ADR-0003](0003-strategy-trait-with-static-dispatch.md)

## Context

`one_of` chooses one value from several strategies. With static dispatch (ADR-0003), a list of strategies of the same type (`List[S]`) is straightforward, but it was unclear whether strategies with different types but the same `Value` (for example, `Integers` and `Just[Int]`) could be combined. The ADR-0003 restriction against `def(...) -> T` fields prevents a single type-erased `Gen[T]`. As part of the investigation for Issue #14, we tested whether `OneOf2[A, B]` compiled with `mojo 1.2.0.dev2026092605`.

Results:

- A naive implementation does not compile. In a struct with `comptime Value = Self.A.Value`, writing `return self.b.draw(tc)` in `draw` produces `cannot implicitly convert 'B.Value' value to 'OneOf2[A, B].Value'`, even when both `A.Value` and `B.Value` are `Int`. Associated types are not automatically unified even when their concrete types match.
- A `where` clause inside the parameter list (`struct OneOf2[A: Strategy, B: Strategy where ...]`) is rejected as "no longer supported." A trailing `where` clause after the signature (`struct OneOf2[A: Strategy, B: Strategy](Strategy) where A.Value == B.Value`) works. Constructing a mismatched pair such as `OneOf2[Integers, Booleans]` fails with `violated constraint ... expected 'Bool(identical(A.Value, B.Value))'`, serving as evidence of type equality. The compiler normalizes `==` to `identical` in its diagnostic.
- Branching in the body works with `rebind[Self.Value](other^).copy()`. Matching pairs (`Integers`/`Integers`, `Integers`/`Just[Int]`) compile and run; mismatched pairs fail when `draw` is instantiated. `rebind` is built in and needs no import. Its return type is generic `Value` (`Copyable` but not `ImplicitlyCopyable`), so an explicit `.copy()` is needed.
- The constructor `one_of2` also requires a trailing `where A.Value == B.Value`. Without it, the definition fails with `lacking evidence to prove correctness`. With it, type inference works as usual (`one_of2(integers(0, 1), booleans())`) and a mismatch is reported as a `violated constraint` at the call site.

## Decision

- Use `OneOf[S]` and `one_of(var strategies: List[S])` for N strategies of the same type (`src/proptest/strategies/choice.mojo`).
- Use `SampledFrom[T]` and `sampled_from(var values: List[T])` to choose values.
- Use `OneOf2[A, B]` and `one_of2(var a: A, var b: B)` for two heterogeneous strategies. Add the trailing `where A.Value == B.Value` to both the struct and function, and branch with `rebind[Self.Value](other^).copy()`.
- For three or more heterogeneous branches, nest `one_of2` or convert branches to a single strategy type and use `one_of`. Do not introduce a type-erased vtable.

## Alternatives Considered

- Return `self.b.draw(tc)` directly: associated types are not unified, so this fails even when the types match, not just when they differ.
- Erase types using `ArcPointer` and a hand-written vtable: rejected in ADR-0003 because it adds unsafe code. It is unnecessary now that `where` and `rebind` make a static implementation possible.
- Require users to define an enum wrapper: this remains useful when payloads differ across N branches, but the library no longer needs to provide it as the standard mechanism.
- Wait for the compiler to improve associated-type unification: `rebind` already serves as evidence, so there is no need to wait. A future compiler improvement could simplify the implementation.

## Consequences

- Same-type `one_of`, `sampled_from`, and heterogeneous `one_of2` all satisfy shrink monotonicity: choice index 0 is the first branch. Since the index is drawn first, shrinking only lowers it and eventually reaches the first branch.
- Type mismatches between heterogeneous branches are compile-time errors rather than runtime errors.
- Heterogeneous N-way choices become nested and produce longer type names. As with recursive strategies, deep compositions have long type names (a known tradeoff from ADR-0003).
