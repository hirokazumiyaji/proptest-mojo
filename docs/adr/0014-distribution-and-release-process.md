# ADR-0014: Source distribution and release process for v0.1.0

- Status: Superseded by [ADR-0016](0016-conda-and-github-release-distribution.md)
- Date: 2026-09-30
- Related: Issue #33, [ADR-0007](0007-toolchain-pixi-and-mojo-nightly.md), [v0.1.0 release notes](../releases/v0.1.0.md)

## Context

The v0.1.0 release needs a distribution method users can consume. We evaluated source checkouts, compiled Mojo artifacts, and conda packages with the pinned Mojo nightly.

A tagged Git checkout works when consumers pass its `src` directory through `-I`. Compiled `.mojoc` artifacts are tied to the exact compiler build and are not intended for distribution. Conda packaging is the official package route, but this repository does not yet have the package metadata and publishing workflow it requires.

## Decision

- Distribute v0.1.0 as source through a tagged Git checkout. Consumers can clone the tag and run Mojo with `-I <checkout>/src`; setup steps are in [the setup guide](../guide/setup.md).
- Do not distribute `.mojoc` or `.mojopkg` artifacts. Keep `pixi run build` for local build checks.
- Defer conda packaging until the repository has package metadata and a publishing workflow.
- Follow SemVer. Keep the workspace version and `VERSION` constant in sync. Before each release, compare `pixi.toml`'s `[workspace].version` with the `VERSION` constant in `src/proptest/__init__.mojo`; the smoke test only checks the constant's expected format.
- For each release, verify CI, include release notes in the PR, then tag the merged commit and publish a GitHub Release. Recommend that consumers pin a release tag.

## Consequences

Users can consume v0.1.0 from a tagged source checkout. They must use the Mojo version pinned by the release's `pixi.lock`. Conda packaging remains future work.
