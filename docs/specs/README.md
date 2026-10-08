# Specifications

These documents describe the **current** design of proptest-mojo and must stay aligned with the implementation. See [docs/README.md](../README.md) for documentation maintenance guidelines.
Items that are not implemented are marked as Planned.

| Document | Contents |
|------|------|
| [overview.md](overview.md) | Goals, scope, and feature mapping to Hypothesis and proptest |
| [architecture.md](architecture.md) | Module structure, data flow, and dependency direction |
| [choice-sequence.md](choice-sequence.md) | Choice sequences, `TestCase`, spans, and state transitions |
| [strategies.md](strategies.md) | The `Strategy` trait, built-in strategies, and combinators |
| [shrinking.md](shrinking.md) | Simplicity ordering, shrinking passes, and the shrinking loop |
| [runner.md](runner.md) | `for_all`, settings, generation, reports, replay, and the example database |
| [coding-guidelines.md](coding-guidelines.md) | Functional implementation rules and Mojo language constraints |

For the reasoning behind design decisions, see the [ADRs](../adr/README.md).
