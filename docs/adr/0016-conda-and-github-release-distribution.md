# ADR-0016: Distribute via conda packages and GitHub Releases

- Status: Accepted
- Date: 2026-10-09
- Related: Issue #84, [ADR-0014](0014-distribution-and-release-process.md), [ADR-0007](0007-toolchain-pixi-and-mojo-nightly.md)

## Context

ADR-0014 chose tagged source checkouts for v0.1.0 and deferred conda packaging. Sibling libraries such as `crypto-mojo` already publish conda packages to prefix.dev on `v*.*.*` tags and pin a stable Mojo compiler in `conda.recipe/`. Mojo `1.1.0` is available on the Modular `max` channel, so a packaged artifact is now practical.

## Decision

- Distribute releases as conda packages built from `conda.recipe/` with `mojo-compiler =1.1.0`, uploaded to the configured prefix.dev channel.
- On each `v*.*.*` tag, also create a GitHub Release. Prefer `docs/releases/<tag>.md` as the release body when that file exists.
- Keep SemVer alignment across `pixi.toml` `[workspace].version`, `conda.recipe/recipe.yaml` `context.version`, the `VERSION` constant, and the Git tag (`v` prefix stripped).
- Prefer Mojo `1.1.0` on the `https://conda.modular.com/max` channel for published packages. Development may continue to pin a compatible Mojo through `pixi.lock`.
- This ADR supersedes ADR-0014's deferral of conda packaging and its "source checkout only" distribution rule.

## Alternatives Considered

- Source-only distribution (ADR-0014): still works for consumers who vendor `src`, but does not give a installable package.
- Nightly-only packaging: ties published artifacts to a rapidly moving compiler and complicates consumer pins.
- Publishing `.mojoc` artifacts on GitHub Releases without conda metadata: skips dependency pinning and channel install UX.

## Consequences

- Releases require repository variable `PREFIX_CHANNEL` and secret `PREFIX_API_KEY`.
- Tag pushes run `.github/workflows/publish.yml`, which builds linux-64 and osx-arm64 packages, uploads them, then creates the GitHub Release.
- Consumers can install from the prefix.dev channel or still clone a release tag and use `-I <checkout>/src`.
- Published packages depend on Mojo `1.1.0`; consumers must use a compatible compiler.
