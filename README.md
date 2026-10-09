# proptest-mojo

`proptest-mojo` is a property-based testing library for Pure Mojo. It generates inputs for properties, searches for counterexamples, and shrinks failures to simpler examples that are easier to understand and reproduce.

The project is under active development. See the [roadmap](https://github.com/hirokazumiyaji/proptest-mojo/issues/34), [milestones](https://github.com/hirokazumiyaji/proptest-mojo/milestones), and [open issues](https://github.com/hirokazumiyaji/proptest-mojo/issues) for current work.

## Quick start

Install [pixi](https://pixi.sh/), then clone the repository and install its Mojo toolchain:

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
```

Create a property by drawing values from strategies. A property raises an error when it finds a counterexample; `for_all` runs it over generated examples and reports a shrunk failure.

```mojo
from proptest import Settings, TestCase, for_all, integers

def addition_commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-1000, 1000), "a")
    var b = tc.draw(integers(-1000, 1000), "b")
    if a + b != b + a:
        raise Error("addition must commute")

def main() raises:
    for_all(addition_commutes, Settings(seed=UInt64(1)))
```

Run the example program, which includes both a passing property and a deliberately failing property that demonstrates shrinking:

```sh
pixi run mojo run -I src examples/basic.mojo < /dev/null
```

## How it works

- **Strategies describe generated values.** Draw values with `tc.draw(strategy, label)`; labels are included in failure reports. Use `tc.assume(condition)` to reject an example or `tc.note(message)` to add context to a report.
- **Composition builds richer inputs.** Built-in strategies cover integers, booleans, floats, bytes, text, lists, unique lists, dictionaries, tuples, optional values, choices, and JSON-like recursive trees. `map`, `filter`, and `flat_map` derive strategies; custom `Strategy` structs can carry parameters and draw multiple related values.
- **Shrinking simplifies counterexamples.** The runner shrinks the recorded choice sequence, so generated structures and composed strategies can be reduced without requiring each property to define a separate shrinker. Strategy authors should make the all-zero choice produce the simplest value.
- **Failures can be replayed.** Reports include a replay string. Pass it through `Settings(replay=...)` to run that example directly. Set a `name` in `Settings` to persist and replay minimized examples in the example database.
- **Runs are configurable and reproducible.** `Settings` controls example count, seed, choice limits, shrink budget, replay, verbosity, and database configuration. `PROPTEST_SEED` and `PROPTEST_MAX_EXAMPLES` can configure runs through the environment.
- **Stateful behavior can be checked against a model.** Implement `StateMachine` and call `run_state_machine` to generate and shrink operation sequences while checking invariants after each operation.

## Run tests and examples

```sh
pixi run test
pixi run format-check
```

To run an individual example:

```sh
pixi run mojo run -I src examples/combinators.mojo < /dev/null
```

The `< /dev/null` redirection keeps execution consistent with CI. Example programs are under [`examples/`](examples/README.md).

## Publishing

Tag pushes matching `v*.*.*` run `.github/workflows/publish.yml`:

1. Build conda packages for `linux-64` and `osx-arm64` with Mojo `1.1.0`
2. Upload them to the configured prefix.dev channel
3. Create a GitHub Release (using `docs/releases/<tag>.md` when present)

Before publishing, set repository variable `PREFIX_CHANNEL` and secret `PREFIX_API_KEY`. Keep the tag version aligned with `pixi.toml`, `conda.recipe/recipe.yaml`, and `VERSION` in `src/proptest/__init__.mojo`.

Local package smoke (after `pixi install`):

```sh
pixi run test-consumer
```

## Documentation

- [User guide](docs/guide/README.md): setup, properties, strategies, composition, shrinking, and replay
- [Examples](examples/README.md): runnable programs
- [Specifications](docs/specs/README.md): current design and behavior
- [Architecture decision records](docs/adr/README.md): recorded design decisions
- [v0.1.0 release notes](docs/releases/v0.1.0.md)
- [Documentation guide](docs/README.md): documentation conventions
