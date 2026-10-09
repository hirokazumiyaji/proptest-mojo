# Coding Guidelines

The guiding principle is [ADR-0008](../adr/0008-functional-core-imperative-shell.md) (functional core, imperative shell). This document specifies concrete coding practices.

## Functional conventions

| Convention | Practice |
|------|----------------|
| Treat values as immutable | Do not mutate `Strategy`, `ChoiceSequence`, `Settings`, or `Report` after construction. Represent changes with functions that return new values |
| Restrict where side effects occur | Only `TestCase` and the runner (including the shrinking loop) hold mutable state. Core functions do not take `mut` arguments, except `draw(self, mut tc)` |
| Compose pure functions | Functions passed to combinators are thin (non-capturing). Define them at module scope |
| Inject side effects through higher-order functions | Core functions that need evaluation or I/O accept the operation as a function argument (for example, an adaptive shrinking pass accepts `is_interesting`) |
| Avoid global state | Do not use module-level `var` or `std.random` |
| Allow local mutability | Local `var` and loops are allowed when their effects cannot be observed outside the function |
| Make ownership explicit | Move values with `var` arguments and `^`; avoid unnecessary `.copy()` |
| Represent failures as state | Core classifications are returned as values such as `Status`. Use `raise` only to interrupt a property or report a result from the runner to the user |

## Mojo language constraints and workarounds

Validation results for `mojo 1.2.0.dev2026092605`. If a compiler update removes a constraint, create an ADR to revisit the approach.

| Constraint | Workaround |
|------|--------|
| `def(...) -> T` types are treated as traits and cannot be struct fields | Pass functions as thin-function comptime parameters ([ADR-0005](../adr/0005-thin-functions-as-comptime-parameters.md)) |
| Capturing closures are not `Copyable` and cannot be stored in a struct | Represent transformations that need captures as composite strategies (structs with value fields) |
| Type inference fails when a capturing closure’s type parameters include an associated type (`S.Value`) | Have properties accept `def(mut TestCase) raises -> None` ([ADR-0004](../adr/0004-property-as-testcase-closure.md)) |
| Trait default methods cannot use function parameters with dependent types | Implement combinators as free functions (`map[f](s)`) |
| `Deinitable` is required to use a trait associated type in fields or temporary values | Require `Deinitable` for `Strategy` and `Strategy.Value` |

## Mojo style

- Use current syntax: `def` only, `comptime`, imports prefixed with `std.`, the `out self` / `mut` / `var` argument conventions, `@fieldwise_init`, and `Writable`.
- Qualify struct parameters in the body, for example as `Self.T`.
- Comments should explain why; do not add comments that narrate what the code does.
- Write docstrings for public APIs.

## Testing conventions

- Put module tests in `tests/test_<module>.mojo` and run them with `TestSuite.discover_tests`.
- For the functional core (PRNG, choice sequences, shrinking passes), use unit tests without properties to compare inputs and outputs directly.
- For shrinking-pass unit tests, pass a pure predicate as the evaluation function.
- Verify library properties (for example, that shortlex is a total order and strategies generate in-range values) with the library’s own `for_all` (dogfooding). Continue to test the internal functional core by comparing concrete inputs and outputs directly.
- Protect shrinking quality with regression tests in `tests/shrink_quality/` ([shrinking.md](shrinking.md)).
