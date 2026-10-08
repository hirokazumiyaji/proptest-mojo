# ADR-0008: Use a functional core and imperative shell

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/architecture.md](../specs/architecture.md), [specs/coding-guidelines.md](../specs/coding-guidelines.md)

## Context

We want an implementation shaped by functional programming. Mojo, however, is an imperative language with ownership (`var` / `mut` / `^`), not a purely functional language. A property-based testing engine has inherent side effects: randomness, property execution, timing, example database file I/O, and report output. Trying to make everything pure in Mojo would add copies, making the code slower and harder to read.

## Decision

Structure the project as a "functional core and imperative shell."

- **Functional core** (pure and deterministic)
  - Strategies are immutable values. `draw` does not modify anything except `TestCase`.
  - Choice-sequence operations include shortlex comparison, serialization, and span calculation.
  - Shrink passes are pure functions that return a list of candidate choice sequences from an input sequence. They do not evaluate properties.
  - PRNG derivation is a pure function from `(seed, index)` to state.
- **Imperative shell** (side effects)
  - `TestCase` is the only mutable object that records choices and holds PRNG state.
  - The runner executes properties, runs the shrinking loop, produces reports, and performs example database I/O.
- Local mutation (`var` and loops inside a function) is allowed when it is not externally observable.

## Alternatives Considered

- Make everything pure (pass `TestCase` around like a State monad): passing a `mut` reference is more natural and faster with Mojo's ownership model, without a readability benefit.
- An unrestricted imperative implementation: shrink passes and evaluation would become entangled, making it difficult to test each pass independently.

## Consequences

- Shrink passes can be tested without a property by comparing input choice sequences with candidate outputs.
- Side effects are confined to `TestCase` and the runner, simplifying reasoning about reproducibility.
- Put detailed coding conventions in the Specs' coding guidelines; this ADR defines only the principles.
