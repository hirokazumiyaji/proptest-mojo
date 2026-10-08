# ADR-0006: Use a custom PRNG with explicit state

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/runner.md](../specs/runner.md)

## Context

Generation depends on randomness. We needed to decide how to handle random state to make counterexamples reproducible, runs independent under parallel execution, and tests deterministic. `std.random` has process-wide global state, so results depend on the order of `seed()` calls.

## Decision

- Implement SplitMix64 (for seed expansion) and xoshiro256** (for generation) ourselves.
- Make the PRNG a value type with no global state. `TestCase` owns its state.
- Derive each example's PRNG using a pure function of `(run_seed, example_index)`. This allows any example to be reproduced independently.
- Do not use `std.random` in the library.

## Alternatives Considered

- Use `std.random`: its global state means that if users call `std.random` inside a property, the generated sequence changes and reproducibility breaks.
- Use cryptographic randomness: unnecessarily slow.

## Consequences

- A single seed deterministically reproduces the entire run.
- Changing the algorithm changes the generated values for the same seed, so algorithm changes must be noted in release notes.
