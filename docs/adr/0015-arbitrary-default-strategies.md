# ADR-0015: Type-Based Default Strategy Dispatch

- Status: Accepted
- Date: 2026-10-08
- Related: Issue #30, [strategy specification](../specs/strategies.md)

## Context

Properties often need a default strategy for common value types. Mojo's static dispatch cannot extract an abstract element type from List[E] and recursively construct a strategy for any E.

## Decision

- Provide arbitrary[T]() for supported builtin types: Int, Bool, Float64, String, and an enumerated set of list types.
- Support one nested list default, List[List[Int]], while general nested type decomposition remains unavailable.
- Let user-defined types conform to Arbitrary and expose their strategy through the type's static arbitrary() method.
- Keep unsupported builtin type requests as compile-time dispatch branches that raise Error when drawn.

## Consequences

Common values and supported lists can use a type-based default. Adding a new builtin or list shape requires extending the dispatch table and its tests. User-defined types control their own strategy implementation. Broader recursive list derivation can be considered if Mojo gains a way to name and inspect an abstract type's element type.
