# ADR-0007: Use pixi and Mojo nightly for the toolchain

- Status: Accepted
- Date: 2026-09-26
- Related: Milestone M0

## Context

Mojo's language specification changes rapidly, and syntax and standard-library APIs differ between stable and nightly releases. This project is designed around current syntax (`def` only, `comptime`, unified closures, and `std.` imports); experiments for ADR-0003 through ADR-0005 used `mojo 1.2.0.dev2026092605`. The `mojo test` subcommand has also been removed, so tests are written as executables using `std.testing.TestSuite`.

## Decision

- Use pixi for environment management, with the `https://conda.modular.com/max-nightly` and `conda-forge` channels.
- Commit `pixi.lock` to pin the Mojo version. Update it in a dedicated PR and verify that all tests pass.
- Run `test_*.mojo` files under `tests/` with `mojo run -I src`. Each file runs its own tests using `TestSuite.discover_tests`. Run all files with the `pixi run test` task.
- Run CI on both Linux and macOS using GitHub Actions.

## Alternatives Considered

- Use stable Mojo: some language features needed by this design are not available in stable, or use different syntax.
- Install with uv (pip): pixi follows Modular's official workflow and makes version pinning with a lockfile straightforward.

## Consequences

- Nightly breaking changes may cause failures. Pin the version in the lockfile and update it deliberately.
- Consider moving to stable Mojo in a separate ADR once stable meets the project's requirements.
