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

## Directly replaying a choice sequence

The counterexample report ends with a `Reproduce with:` line that quotes the exact choice sequence as a replay token. Pass it to `Settings(replay=...)` to run only that sequence; generation and shrinking are skipped and the same counterexample is raised.

```mojo
for_all(prop, Settings(replay="AAECAQ=="))
```

A replay that no longer fails raises instead of searching for a new counterexample.

## Example database

Give the test a database name to persist shrunken counterexamples across runs. The next run replays every saved sequence under `.proptest-mojo/` before generating, so a regression that reappears is reported immediately; sequences that no longer fail are deleted.

```mojo
for_all(prop, Settings(name="my-property"))
```

Either add `.proptest-mojo/` to `.gitignore` or commit it as a regression corpus.

See [Specs: Runner](../specs/runner.md) for the full behavior.
