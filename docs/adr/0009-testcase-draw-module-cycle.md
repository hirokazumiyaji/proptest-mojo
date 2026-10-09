# ADR-0009: Allow a reference cycle between testcase and strategy for `TestCase.draw`

- Status: Accepted
- Date: 2026-09-30
- Related: Issue #6, [specs/choice-sequence.md](../specs/choice-sequence.md) (`TestCase.draw`), [specs/architecture.md](../specs/architecture.md)

## Context

The Spec defines `tc.draw(strategy)` as a `TestCase` method. Its signature, `draw[S: Strategy](mut self, strategy: S, ...)`, needs the `Strategy` trait name, so `testcase.mojo` must import `strategy.mojo`. Conversely, `Strategy.draw` needs `TestCase`, so `strategy.mojo` must import `testcase.mojo`. This creates an unavoidable reference cycle between the two modules.

We tested circular imports with Mojo 1.2.0.dev2026092605 and confirmed that compilation, execution, and `precompile` all work.

## Decision

- Allow a reference cycle between `testcase.mojo` and `strategy.mojo` (and future modules under `strategies/`). This is the sole exception; dependencies between other layers remain one-way.
- The dependency from `testcase` to `strategy` exists only for the generic boundary of `TestCase.draw`. The `TestCase` implementation (choice supply, recording, spans, and state) does not know strategy details.
- Keep runtime calls one-way from the shell to the core: `TestCase.draw` → `Strategy.draw` → `draw_integer`, and so on.

## Alternatives Considered

- Make `draw` a free function `draw(tc, strategy)` in `strategy.mojo`: this removes the cycle but changes the Spec's `tc.draw` API.
- Move the `Strategy` trait to `testcase.mojo`: this removes the cycle but mixes the responsibilities of choice supply and value generation in one module, contrary to the architecture's module organization.

## Consequences

- The API supports `tc.draw(strategy, label)` as specified.
- Document the limited scope of this cycle in the architecture section on dependency direction.
- If a future compiler rejects circular imports, revisit this ADR and consider switching to the free-function design.
