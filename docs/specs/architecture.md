# Architecture

## Layers and dependency direction

```text
┌──────────────────────────── Imperative shell ────────────────────────────┐
│ runner       for_all / Settings / Report / generation phase / shrinking loop   │
│ database     example database (file I/O)                          │
└───────────────┬──────────────────────────────────────────────────────┘
                │ calls
┌───────────────▼──────────────────────────────────────────────────────┐
│ testcase     TestCase: choice recording and replay, spans, state, PRNG ownership        │
└───────────────┬──────────────────────────────────────────────────────┘
                │ depends on
┌───────────────▼──────────────── Functional core ──────────────────────────┐
│ strategies   `Strategy` trait, built-in strategies, combinators        │
│ shrink       shrinking passes (choice sequence → candidate sequences), shortlex ordering              │
│ choice       ChoiceNode / ChoiceSequence / Span / serialization         │
│ prng         SplitMix64 / xoshiro256** and seed derivation                      │
└──────────────────────────────────────────────────────────────────────┘
```

Dependencies flow in one direction, from top to bottom. The only exception is the reference cycle between `testcase` and `strategies`（[ADR-0009](../adr/0009-testcase-draw-module-cycle.md)）。
`strategies` depends on `testcase` for the `draw(self, mut tc: TestCase)` signature and uses only `TestCase` primitives such as `draw_integer`.
The reverse dependency, from `testcase` to `strategies`, exists only for the generic bound (`S: Strategy`) on `TestCase.draw`; runtime calls still flow from the shell to the core.
`shrink` does not depend on `testcase` or `runner`. The runner evaluates candidates.

## Package structure

```text
pixi.toml
pixi.lock
src/proptest/
  __init__.mojo              Public API re-exports
  prng.mojo                  PRNG and derivation functions
  choice.mojo                ChoiceKind / ChoiceNode / ChoiceSequence / Span / shortlex
  encoding.mojo              Choice-sequence serialization (replay strings, database)
  testcase.mojo              TestCase, Status, exception classification
  strategy.mojo              `Strategy` trait
  strategies/
    primitives.mojo          integers, integers_of, booleans, just
    floats.mojo              floats
    text.mojo                text, bytes
    collections.mojo         lists, unique_lists, dicts, tuples, optionals
    choice.mojo              one_of, sampled_from
    combinators.mojo         map, filter, flat_map
  shrink/
    passes.mojo              Individual shrinking passes (pure functions)
    shrinker.mojo            shrinking loop (accepts an evaluation function)
  runner.mojo                for_all, Settings, Report
  database.mojo              ExampleDatabase
  stateful.mojo              StateMachine (Planned: M5)
tests/
  test_*.mojo                unit tests and property tests
  shrink_quality/            shrinking quality regression tests
examples/                    Usage examples
```

Tasks in `pixi.toml`:

| Task | Description |
|--------|------|
| `test` | Run all `tests/**/test_*.mojo` files with `mojo run -I src` (returns non-zero if any fail) |
| `format` | `mojo format src tests` |
| `format-check` | Run `mojo format` on a copy and diff against the working tree (does not modify the index) |
| `build` | `mojo precompile src/proptest -o proptest.mojoc` (the artifact is gitignored) |

Supported platforms are `osx-arm64` and `linux-64` (Linux/macOS CI assumptions in ADR-0007).

On pull requests and pushes to `main`, CI (`.github/workflows/ci.yml`) runs `pixi run format-check` and `pixi run test` on both `ubuntu-24.04` and `macos-15` (using `prefix-dev/setup-pixi` with caching enabled).

## PRNG (`prng.mojo`)

Value type; no global state (ADR-0006).

| API | Role |
|-----|------|
| `SplitMix64` | For seed expansion: `next_u64()`. |
| `Xoshiro256StarStar` | For generation: `from_seed` / `next_u64` / `next_below` / `next_float64` |
| `derive(run_seed, index)` | Purely derives the PRNG for each example |

`std.random` is not used by the library.

## Data flow for one `for_all` call

```text
for_all(prop, settings)
 │
 ├─ 1. Replay phase: replay choice sequences from the database and `settings.replay` using `TestCase(prefix=...)`
 │
 ├─ 2. generation phase: i = 0..max_examples
 │      tc = TestCase.generating(derive(seed, i))
 │      prop(tc)
 │        └─ tc.draw(strategy) → strategy.draw(tc) → tc.draw_integer(...) → recording
 │      Result: VALID / INVALID (`assume` or `filter`) / OVERRUN / INTERESTING (failure)
 │
 ├─ 3. Shrinking phase (when INTERESTING occurs)
 │      best = tc.choices
 │      loop: for pass in passes:
 │              for cand in pass(best):              ← pure function
 │                 if shortlex(cand) < shortlex(best) and evaluate(cand) is INTERESTING:
 │                     best = choice sequence from evaluate result (only choices actually consumed)
 │      Stop at a fixed point or when the budget is exhausted
 │
 └─ 4. Report: replay `best`, collect draw labels and values, and raise an exception
          Save `best` to the database
```

## Responsibilities of key types

| Type | Mutability | Responsibility |
|----|--------|------|
| `Strategy` implementation | Immutable | Deterministically creates values from a choice sequence |
| `ChoiceSequence` | Treated as immutable | Sequence of choices; unit of comparison and serialization |
| `TestCase` | Mutable (the only one) | Supplies choices (prefix replay or PRNG), records them, and tracks spans and state |
| `Settings` | Immutable | Execution parameters |
| `Shrinker` | Mutable only inside the loop | Holds the current best choice sequence and applies passes to a fixed point |
| `Report` | Immutable | Counterexample display and replay information |
