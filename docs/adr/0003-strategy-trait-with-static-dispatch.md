# ADR-0003: Statically dispatch strategies through a trait and generic structs

- Status: Accepted
- Date: 2026-09-26
- Related: [specs/strategies.md](../specs/strategies.md)

## Context

We needed to decide how to represent a strategy (a value generator) in Mojo. We tested the most straightforward design, a `Gen[T]` that stores a generator function of type `def(mut TestCase) raises -> T`, with Mojo 1.2.0.dev2026092605 and found:

- A `def(...) -> T` type is treated as a trait and cannot be used as a struct field type (`struct fields do not support trait types`).
- Therefore, a single `Gen[T]` type holding a type-erased generator function cannot be implemented.

The following design did compile and run:

```mojo
trait Strategy(Copyable, Deinitable):
    comptime Value: Copyable & Writable & Deinitable
    def draw(self, mut tc: TestCase) raises -> Self.Value: ...

@fieldwise_init
struct ListOf[S: Strategy](Strategy):
    comptime Value = List[Self.S.Value]
    var elem: Self.S
    ...
```

## Decision

- Define `Strategy` as a trait with an associated type `Value`.
- Implement built-in strategies and combinators as generic structs parameterized by their inner strategy, following the same pattern as Rust iterator adapters.
- Use static dispatch for generation; do not use runtime type erasure.
- Require the associated type `Value` to satisfy `Copyable & Writable & Deinitable`. `Writable` is used to display counterexamples.

## Alternatives Considered

- `Gen[T]` storing a generator function: not implementable due to the language constraint described above.
- Type erasure using `ArcPointer` and a hand-written vtable: adds unsafe code and undermines the simplicity of the functional design. Revisit in a separate ADR if there is a need to put heterogeneous strategies in one collection, such as heterogeneous `one_of`.

## Consequences

- Generation can be inlined, keeping runtime overhead low.
- Composing combinators creates long type names. Users can rely on `var` type inference and rarely need to write those names.
- Recursive strategies, such as tree generators, cannot be written directly because their types would nest infinitely. They need a separate design (investigate in an issue).
- The current compiler cannot support method chains such as `s.map[f]()` through trait default methods because function parameters with dependent types do not satisfy trait requirements. Combinators are free functions such as `map[f](s)` instead ([ADR-0005](0005-thin-functions-as-comptime-parameters.md)).
