# proptest-mojo

Pure Mojo property-based testing library.

## Documentation

- Write and maintain all repository documentation in English, including Markdown files in the repository root, `docs/`, and `examples/`.
- Follow the documentation conventions in `docs/README.md`.
- `docs/specs/` describes the current design. Update the relevant specifications in the same change as implementation changes.
- When making a design decision, add an ADR under `docs/adr/` and update its index. Do not rewrite accepted ADRs.
- Keep temporary notes, plans, and spikes in `tmp/` or `.claude/tasks/`; do not commit them.

## Tasks

- Track tasks in GitHub Issues (`gh issue list`). Create a branch for each issue and use `Closes #N` in the pull request body.

## Implementation guidelines

- Favor functional design. See `docs/specs/coding-guidelines.md` for details.
- Use the latest nightly Mojo syntax (`def` only, `comptime`, `std.` imports, and so on).
- For Mojo language constraints, such as the inability to store capturing closures in structs, see ADR-0005 and `docs/specs/coding-guidelines.md`.

## Commands

- `pixi run test`: run all `tests/**/test_*.mojo` files with `mojo run -I src`.
- `pixi run format`: format `src` and `tests` with `mojo format`.
- `pixi run format-check`: check formatting; exits non-zero when files need formatting.
- `pixi run build`: generate `proptest.mojoc` with `mojo precompile`.

CI is configured in `.github/workflows/ci.yml` and runs `format-check` and `test` on Linux and macOS.
