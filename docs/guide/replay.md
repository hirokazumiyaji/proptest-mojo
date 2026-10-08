# Reproducing failures

Runs are deterministic. The same seed generates the same sequence of examples and produces the same report for the same counterexample.

## Fixing the seed

Use the value shown on the report's `Seed:` line.

```mojo
for_all(prop, Settings(seed=UInt64(3)))
```

You can also set the seed with an environment variable. It applies only when `Settings(seed=None)` (the default) is used. A value explicitly set in code takes precedence over the environment variable. For example, the environment variable is ignored by an example that sets `Settings(seed=UInt64(1))`, such as `basic.mojo`.

```sh
# Applies only to your tests that use Settings(seed=None):
PROPTEST_SEED=3 pixi run mojo run -I src path/to/my_property_test.mojo < /dev/null
```

## Changing the number of examples

Override the default `max_examples` value (100) with `PROPTEST_MAX_EXAMPLES`. This is useful for increasing the number of runs in CI. If code explicitly sets a value different from the default, that value takes precedence over the environment variable.

```sh
PROPTEST_MAX_EXAMPLES=1000 pixi run test
```

## Planned features

- `Settings(replay=...)`: directly replay a reported choice sequence (M4). For now, reproduce failures by fixing the seed.
- Example database (`.proptest-mojo/`): retry previously found counterexamples first on the next run (M4). For now, save found counterexamples separately as regression tests and run them with `just` or `for_all` using a fixed seed.

See [Specs: Runner](../specs/runner.md) for the latest status.
