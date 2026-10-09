# ADR-0004: Represent properties as `def(mut TestCase) raises` closures

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/runner.md](../specs/runner.md)

## Context

We needed to choose the function type used to receive the property under test. The two candidates were:

1. **Receive values** (proptest / Hypothesis `@given`): `for_all(strategy, prop)` where `prop: def(S.Value) raises`.
2. **Receive a TestCase** (Hypothesis `data()` / `st.data()`): `for_all(prop)` where `prop: def(mut TestCase) raises`. The property calls `tc.draw(strategy)`.

The spike showed that option 1 did not compile with the current compiler. When the type parameter for a capturing closure, `P: def(S.Value) raises -> None`, contains the associated type `S.Value`, the compiler reports that `def(xs: List[Int]) raises -> None` does not conform to `def(S.Value) raises -> None`. Option 2 contains no dependent type and works with capturing closures.

## Decision

- A property is a closure conforming to `def(mut TestCase) raises -> None`. The runner accepts it as `for_all[P: def(mut TestCase) raises -> None](prop: P, settings: Settings = Settings())`.
- Draw values inside the property with `tc.draw(strategy, label)`.
- Properties may capture local variables, for example `{imm x}`.

## Alternatives Considered

- Receive values directly: cannot be implemented due to the type inference limitation above. If the compiler improves, consider a thin `for_all(strategy, prop)` wrapper in a separate ADR.

## Consequences

- Dependent generation, where the next strategy depends on a previously drawn value, can be written as ordinary code without `flat_map`.
- Counterexample output is assembled from the labels recorded during `tc.draw` and the `Writable` representation of the values.
- Test-time operations such as `assume` and `note` can be exposed naturally as `tc` methods.
- The API does not declare a fixed number of arguments, so declarative syntax such as `@given(a=..., b=...)` is unavailable.
