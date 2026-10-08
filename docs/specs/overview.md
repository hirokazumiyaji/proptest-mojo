# Overview

## Goals

Provide a property-based testing (PBT) library in pure Mojo with expressive strategies and high-quality shrinking.

The goals are defined in three areas:

1. **Expressiveness**: Build practical test data using strategies for primitive types, collections, strings, and floating-point values, as well as `map`, `filter`, `flat_map`, composite strategies, and state-machine testing.
2. **Shrinking quality**: Automatically find a minimal counterexample that people can read directly when a test fails. Shrinking should continue to work through `map`, `filter`, and dependent generation.
3. **Reproducibility**: Fully reproduce counterexamples from a seed and choice sequence, and retry previously discovered counterexamples first on subsequent runs.

## Non-goals

- API compatibility with Python Hypothesis.
- A dependency on the Python runtime (Python interop is not used).
- Property testing of GPU code.
- Coverage-guided fuzzing (only a candidate for future extension).

## Design principles

| Principle | Description | ADR |
|----|------|-----|
| Internal shrinking | Shrink choice sequences rather than values (Hypothesis Conjecture approach) | [0002](../adr/0002-choice-sequence-based-shrinking.md) |
| Static dispatch | Strategies are traits; combinators are generic structs | [0003](../adr/0003-strategy-trait-with-static-dispatch.md) |
| TestCase-driven | A property has type `def(mut TestCase) raises`; values are drawn with `tc.draw` | [0004](../adr/0004-property-as-testcase-closure.md) |
| Composition of pure functions | Combinators accept thin functions as comptime parameters | [0005](../adr/0005-thin-functions-as-comptime-parameters.md) |
| Deterministic randomness | A custom PRNG with explicit state | [0006](../adr/0006-explicit-state-prng.md) |
| Functional core | A pure core (strategies and shrinking passes) with an imperative shell (`TestCase` and runner) | [0008](../adr/0008-functional-core-imperative-shell.md) |

## Feature mapping

| Feature | Hypothesis | proptest | proptest-mojo | Status |
|------|-----------|----------|---------------|------|
| Deterministic PRNG | Internal | Internal | `SplitMix64` / `Xoshiro256StarStar` / `derive` | Implemented (M1) |
| Integers and booleans | `integers`, `booleans` | `any::<i32>`, ranges | `integers`, `booleans` | Implemented (M1) |
| Integer types | Typed `integers` | `any::<i32>`, etc. | `integers_of[DType]` | Implemented |
| Floating-point values | `floats` | `f64::ANY`, etc. | `floats` | Implemented |
| Strings and byte sequences | `text`, `binary` | Regex, `vec(u8)` | `text`, `bytes` | Implemented |
| Collections | `lists`, `sets`, `dictionaries` | `vec`, `hash_set`, `hash_map` | `lists`, `unique_lists`, `dicts` | Implemented |
| Tuples and Optional | `tuples`, `none() \| x` | Tuples, `option::of` | `tuples`, `optionals` | Implemented |
| Selection | `one_of`, `sampled_from`, `just` | `prop_oneof!`, `select`, `Just` | `just`, `one_of`, `sampled_from` | Implemented |
| Transformation | `.map`, `.filter`, `.flatmap` | `prop_map`, `prop_filter`, `prop_flat_map` | `map[f]`, `filter[p]`, `flat_map[f]` | Implemented |
| Composition | `@composite`, `data()` | `prop_compose!` | Composite strategy struct, `tc.draw` | Implemented (M1) |
| Preconditions | `assume` | `prop_assume!` | `tc.assume` | Implemented (M1) |
| Shrinking | Internal shrinking | Value trees | Internal shrinking | Implemented |
| Preferential generation of boundary values | Yes | Partial | Yes | Implemented |
| Replay | `@seed`, `@reproduce_failure` | Failure persistence file | `Settings(seed=...)`, `Settings(replay=...)` | Implemented |
| Counterexample persistence | Example database | `proptest-regressions/` | Example database | Implemented |
| Health checks | Yes | Partial | Yes | Implemented |
| State-machine testing | `RuleBasedStateMachine` | `proptest-state-machine` | `StateMachine` trait | Implemented |
| Recursive data | `recursive` | `prop_recursive` | `json_tree` | Implemented |
| Derivation from types | `from_type` | `Arbitrary` | `Arbitrary` trait | Planned |
| Targeted PBT | `target` | None | `tc.target` | Implemented |

## Terminology

| Term | Meaning |
|------|------|
| Strategy | An immutable value describing how to generate values. `draw` creates a value from a `TestCase`. |
| property | A condition that should hold for every input. A failure is represented by an exception (`raise`). |
| TestCase | Represents one property execution and records or replays its choice sequence. |
| choice | One random choice made during generation, represented as a typed value such as a bounded integer. |
| choice sequence | The sequence of choices made during one execution. The unit of shrinking and replay. |
| span | An interval in a choice sequence representing the choices consumed by one strategy call; used for structural shrinking. |
| shrinking | Replacing a failing choice sequence with a simpler one while preserving the failure. |
