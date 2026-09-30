# Architecture Decision Records

This directory records the project's architectural decisions. See [docs/README.md](../README.md) for documentation conventions.
To add an ADR, copy [template.md](template.md).

| No. | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-documentation-and-task-management.md) | Documentation and task management policy | Accepted | 2026-09-26 |
| [0002](0002-choice-sequence-based-shrinking.md) | Use choice-sequence-based internal shrinking | Accepted | 2026-09-26 |
| [0003](0003-strategy-trait-with-static-dispatch.md) | Statically dispatch strategies through a trait and generic structs | Accepted | 2026-09-26 |
| [0004](0004-property-as-testcase-closure.md) | Represent properties as `def(mut TestCase) raises` closures | Accepted | 2026-09-26 |
| [0005](0005-thin-functions-as-comptime-parameters.md) | Pass combinator functions as thin comptime parameters | Accepted | 2026-09-26 |
| [0006](0006-explicit-state-prng.md) | Use a custom PRNG with explicit state | Accepted | 2026-09-26 |
| [0007](0007-toolchain-pixi-and-mojo-nightly.md) | Use pixi and Mojo nightly for the toolchain | Accepted | 2026-09-26 |
| [0008](0008-functional-core-imperative-shell.md) | Use a functional core and imperative shell | Accepted | 2026-09-26 |
| [0009](0009-testcase-draw-module-cycle.md) | Allow a reference cycle between testcase and strategy for `TestCase.draw` | Accepted | 2026-09-30 |
| [0010](0010-heterogeneous-one-of.md) | Implement heterogeneous `one_of` with `where` clauses and `rebind` | Accepted | 2026-09-30 |
| [0011](0011-example-database-persistence.md) | Example database persistence format and explicit naming | Accepted | 2026-09-30 |
| [0012](0012-recursive-strategy-with-runtime-depth.md) | Implement recursive strategies with one struct and a runtime depth limit | Accepted | 2026-09-30 |
| [0013](0013-state-machine-op-sequence-encoding.md) | Test state machines with a `StateMachine` trait and encoded operation sequences | Accepted | 2026-09-30 |
| [0014](0014-distribution-and-release-process.md) | Define source distribution and release process for v0.1.0 | Accepted | 2026-09-30 |
