# Runner

See [ADR-0004](../adr/0004-property-as-testcase-closure.md) and [ADR-0006](../adr/0006-explicit-state-prng.md).

## API

```mojo
def for_all[P: def(mut TestCase) raises -> None](
    prop: P, settings: Settings = Settings()
) raises
```

- `prop` may be a capturing closure.
- If a counterexample is found, raise an `Error` with a formatted message after shrinking. Used inside `std.testing.TestSuite`, this becomes a test failure.
- Return without a value when no counterexample is found.

```mojo
from proptest import for_all, Settings, TestCase, integers, lists
from std.testing import assert_equal, TestSuite

def test_addition_commutes() raises:
    def prop(mut tc: TestCase) raises:
        var a = tc.draw(integers(-1000, 1000), "a")
        var b = tc.draw(integers(-1000, 1000), "b")
        assert_equal(a + b, b + a)

    for_all(prop, Settings(max_examples=500))

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
```

## Settings

An immutable value type, constructed with `@fieldwise_init` and keyword arguments with defaults.

| Field | Type | Default | Meaning | M |
|-------|------|---------|---------|---|
| `max_examples` | `Int` | 100 | Target number of `VALID` executions | M1 |
| `seed` | `Optional[UInt64]` | `None` | Seed for the entire run. If `None`, use `PROPTEST_SEED` if set; otherwise derive it from the current time | M1 |
| `max_choices` | `Int` | 8192 | Maximum choices per execution; exceeding it results in `OVERRUN` | M1 |
| `max_shrink_evaluations` | `Int` | 5000 | Maximum number of executions during shrinking | M1 |
| `replay` | `Optional[String]` | `None` | Replay the reported choice sequence (without generation or shrinking) | M4 |
| `name` | `String` | `""` | Key for the example database; an empty string disables the database | M4 |
| `database_dir` | `String` | `".proptest-mojo"` | Directory used by the example database | M4 |
| `verbosity` | `Verbosity` | `NORMAL` | `QUIET` / `NORMAL` / `VERBOSE` (show every example) | M4 |

The `PROPTEST_MAX_EXAMPLES` and `PROPTEST_SEED` environment variables override `Settings` defaults, for example to increase the number of runs in CI. Values explicitly set in code take precedence.

The constructor accepts `max_examples` as `Optional[Int]` and stores whether it was explicitly provided (`max_examples_set`) separately from its value. Inferring omission by comparing against the default of 100 would let the environment override `Settings(max_examples=100)`.

`max_examples` must be positive. At 0 or less, the generation loop would never execute the property and the test would silently pass. `effective_max_examples` validates the value and raises `Error` (rather than validating in the constructor, because `for_all` cannot raise from its default argument `Settings()`). The same rule applies to `PROPTEST_MAX_EXAMPLES`.

Parse `PROPTEST_SEED` digit by digit as a `UInt64`. Parsing through signed `Int` would reject valid seeds above `Int.MAX` (half of the range of reported seeds). Raise `Error` for values outside the range or non-numeric values.

## Phases

```text
1. Replay      Replay stored choice sequences from settings.replay or the database (M4)
               → if INTERESTING, skip generation and proceed to shrinking
2. Generation  The i = 0 run uses all-zero choices (the simplest example)
               i >= 1 uses PRNG(derive(seed, i))
               Stop when VALID reaches max_examples or INTERESTING occurs
3. Shrinking   Run the loop described in shrinking.md
4. Reporting   Replay the best sequence and format a counterexample from draw records
               Save to the database (M4)
```

### Generation features (M4)

- **Prefer boundary values**: In generation mode, `draw_integer` returns boundary values such as `0`, `1`, `max_value`, and `max_value - 1` with some probability. This consumes no additional choices and does not affect shrinking.
- **Gradually increase size**: Early examples use shorter average collection lengths to find simple counterexamples sooner.

### Targeted generation (M5)

- Calling `tc.target(score)` records the highest score for that execution (ignoring NaN and infinity).
- The runner retains the choice sequence with the highest score from a `VALID` execution. After half of `max_examples` executions are `VALID`, generation mutates that sequence and replays it: each non-`forced` choice is replaced with a uniform value with probability 0.1, with at least one mutation. The mutations are generated with the PRNG from `derive(seed, attempt)`.
- Runs that do not use `target` keep the existing generation path and reproducibility.

## Health checks (M4)

| Condition | Result | Report |
|-----------|--------|--------|
| More than `10 * max_examples` `INVALID` runs occur before `VALID` reaches `max_examples` | Failure | Explain that `assume` / `filter` may be too strict and report the rejection rate |
| `OVERRUN` exceeds 20% of all executions | Failure | Explain that generated data may be too large |
| No execution is `VALID` | Failure | Explain that no input satisfying the conditions could be generated |

## Reports

```text
Falsifying example (after 37 examples, 112 shrink evaluations):
  a = 0
  xs = [1, 0]
  note: sorted = [0, 1]
Error: expected [0, 1] got [1, 0]
Seed: 1234567890
Reproduce with: Settings(replay="AAECAQ==")
```

- List counterexamples in the order recorded by `tc.draw`, as `label = value`. If a label is omitted, number the entries as `draw #1`, and so on.
- Show `tc.note` messages only when replaying a counterexample.
- Add a line to the report if shrinking stopped because of the evaluation budget.

## Example database (M4)

- If `settings.name` is non-empty, save the shrunk choice sequence to `{database_dir}/{first 16 digits of sha256(name)}/{choice-sequence hash}`.
- On the next run, replay all sequences in that directory before generation. Delete any sequence that is no longer `INTERESTING`.
- In their repository, users can either add `.proptest-mojo/` to `.gitignore` or commit it as a regression test.
- Callers must set `name` explicitly. Automatic derivation from the call site is not supported because the stdlib in Mojo 1.2.0.dev2026092605 has no `call_location` equivalent (see [ADR-0011](../adr/0011-example-database-persistence.md)).
