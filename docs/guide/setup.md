# Setup

## Prerequisites

- [pixi](https://pixi.sh/): manages the toolchain (Mojo nightly). The `platforms` in `pixi.toml` are `osx-arm64` and `linux-64`.
- Run Mojo through `pixi run mojo ...`; do not invoke Mojo directly.

## Installation

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
```

## Running commands

| Purpose | Command |
|---------|---------|
| Tests | `pixi run test` (runs all `tests/**/test_*.mojo` files) |
| Run an example | `pixi run mojo run -I src examples/basic.mojo < /dev/null` |
| Format | `pixi run format` |
| Check formatting | `pixi run format-check` |

`for_all` does not read standard input, but use `< /dev/null` to match the conditions used in CI.

## Use in your own tests

To try the library within this repository, add `src` to the import path with `-I` and import with `from proptest import ...`.

```sh
pixi run mojo run -I src path/to/my_property_test.mojo < /dev/null
```

When used inside `std.testing.TestSuite`, `for_all(prop)` raises an `Error` containing the counterexample, so the test runner will treat it as a test failure. See [basics](basics.md) and [Specs: Runner](../specs/runner.md) for details.

## Use from another repository

The v0.1.0 distribution uses a tagged source checkout. Clone the release and add its `src` directory to Mojo's import path:

```sh
git clone --branch v0.1.0 https://github.com/hirokazumiyaji/proptest-mojo.git vendor/proptest-mojo
pixi run mojo run -I vendor/proptest-mojo/src path/to/my_property_test.mojo < /dev/null
```

Install exactly Mojo `1.2.0.dev2026092605`, matching the version recorded in the release's `pixi.lock`. Compiled `.mojoc` and `.mojopkg` artifacts are not distributed.

## Running in CI

Override the example count with an environment variable without changing the code. An explicitly configured value other than the default takes precedence over the environment variable. If the explicitly configured value equals the default, the environment variable takes effect.

```sh
PROPTEST_MAX_EXAMPLES=1000 PROPTEST_SEED=42 pixi run test
```

- `PROPTEST_MAX_EXAMPLES`: overrides the default example count in `Settings`.
- `PROPTEST_SEED`: fixes the seed when `Settings(seed=None)` is used. See [replay](replay.md) for details.
