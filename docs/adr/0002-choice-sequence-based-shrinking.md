# ADR-0002: Use choice-sequence-based internal shrinking

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/choice-sequence.md](../specs/choice-sequence.md), [specs/shrinking.md](../specs/shrinking.md)

## Context

The quality of property-based testing depends largely on its ability to shrink counterexamples to a minimal form that people can understand. There are three broad approaches to shrinking:

1. **Type-specific shrink functions** (QuickCheck): define a `shrink` function for each type `T` that returns candidate values as `List[T]`. Mapped values cannot be shrunk, and candidates may violate invariants established during generation.
2. **Value trees** (proptest's `ValueTree`): generate a "shrinkable value" and explore it with `simplify` / `complicate`. This supports `map`, but shrinking `flat_map` is weak, and each strategy needs its own ValueTree type.
3. **Internal shrinking** (Hypothesis's Conjecture): record the sequence of random choices consumed by the generator, then shrink that sequence and regenerate values. Shrinking is independent of the value types.

Mojo-specific constraints make type-erased closures and trait objects difficult to use ([ADR-0003](0003-strategy-trait-with-static-dispatch.md), [ADR-0005](0005-thin-functions-as-comptime-parameters.md)). Giving each strategy its own shrinking logic and ValueTree type would cause a combinatorial explosion of generic types.

A spike combined a `TestCase` that records choice sequences, the `Strategy` trait, a property implemented as a capturing closure, and a simple shrinking loop. It confirmed that a `List[Int]` counterexample could be shrunk.

## Decision

Adopt Hypothesis-style internal shrinking.

- Route all randomness through `TestCase` and record it as a `ChoiceSequence`, a sequence of typed choice nodes.
- Define a strategy as a deterministic function that produces a value from a choice sequence. Strategies do not contain shrinking logic.
- The shrinker operates only on choice sequences. It reruns the property with candidate sequences and keeps candidates that are simpler and still fail.
- Order simplicity by shortlex: shorter sequences are simpler; for equal lengths, compare choice values lexicographically.

## Alternatives Considered

- proptest-style value trees: each strategy would need a ValueTree type, which would cause generic type combinations to grow in Mojo. Shrinking `flat_map` and `filter` would also be weaker than internal shrinking.
- QuickCheck-style type-specific shrinking: values after `map` / `filter` cannot be shrunk correctly, so this would not meet the requirement for shrinking quality comparable to Hypothesis and proptest.

## Consequences

- `map`, `filter`, `flat_map`, and user-defined composed strategies can be shrunk without additional implementations.
- Shrinking quality depends on the quality of the shrink passes (deletion, zeroing, binary search, sorting, and so on). Structural shrinking requires recording spans (range labels) in the choice sequence.
- Since the property is rerun for each candidate, its execution cost directly affects shrinking time. Cache previously tried choice sequences to mitigate this.
- Serializing a choice sequence directly enables counterexample replay and persistence in the example database.
