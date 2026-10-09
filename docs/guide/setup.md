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

### conda package

Published releases install a precompiled `proptest.mojoc` into the environment's `lib/mojo` directory. Packages target Mojo `1.1.0` on the Modular `max` channel and are uploaded to the project's prefix.dev channel by `.github/workflows/publish.yml`.

Set repository variable `PREFIX_CHANNEL` and secret `PREFIX_API_KEY` before tagging a release. After install, import with `from proptest import ...` without adding a source checkout to `-I`.

### Tagged source checkout

You can still clone a release tag and add its `src` directory to Mojo's import path:

```sh
git clone --branch v0.1.0 https://github.com/hirokazumiyaji/proptest-mojo.git vendor/proptest-mojo
pixi run mojo run -I vendor/proptest-mojo/src path/to/my_property_test.mojo < /dev/null
```

For source checkouts, install the Mojo version recorded in that release's `pixi.lock`. Published conda packages require Mojo `1.1.0`.

## Running in CI

Override the example count with an environment variable without changing the code. An explicitly configured value other than the default takes precedence over the environment variable. If the explicitly configured value equals the default, the environment variable takes effect.

```sh
PROPTEST_MAX_EXAMPLES=1000 PROPTEST_SEED=42 pixi run test
```

- `PROPTEST_MAX_EXAMPLES`: overrides the default example count in `Settings`.
- `PROPTEST_SEED`: fixes the seed when `Settings(seed=None)` is used. See [replay](replay.md) for details.
