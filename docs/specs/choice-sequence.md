# Choice Sequences and TestCase

This document defines the data structures underlying shrinking and replay. See [ADR-0002](../adr/0002-choice-sequence-based-shrinking.md).

## ChoiceNode

Represents one choice.

```mojo
@fieldwise_init
struct ChoiceKind(Equatable, TrivialRegisterPassable, Writable):
    var value: UInt8
    comptime INTEGER = ChoiceKind(0)   # non-negative integer in 0..=max_value
    comptime BOOLEAN = ChoiceKind(1)   # 0 or 1
    comptime FLOAT = ChoiceKind(2)     # lexicographically encoded 64-bit value (see floats.md)

@fieldwise_init
struct ChoiceNode(Copyable, Equatable, Writable):
    var kind: ChoiceKind
    var value: UInt64       # Selected value; 0 is simplest
    var max_value: UInt64   # Maximum possible value (inclusive)
    var forced: Bool        # Choice fixed by the generator; excluded from shrinking
```

- All choices are normalized to non-negative integers in `0..=max_value`. Every strategy must follow the rule that **0 is the simplest value**.
  - For example, `integers(-10, 10)` maps distances from the shrink target (the value in range closest to zero) to non-negative integers in the order `+1, -1, +2, -2, ...`.
- `kind` lets shrinking passes choose meaning-aware operations (for example, never flipping booleans and trying to simplify floating-point values to integers).

### ChoiceSequence

An immutable value wrapping a `List[ChoiceNode]`.

- **shortlex ordering**: `a < b` iff `len(a) < len(b)`, or the lengths are equal and the values are lexicographically smaller. Shrinking only moves strictly downward in this order, so it always terminates.
- **Serialization**: Values alone are encoded as variable-length integers (LEB128) and converted to Base64. `kind` and `max_value` are not stored because strategies recompute them during replay.

### Span

An interval in a choice sequence representing a structural unit, such as one `tc.draw(strategy)` call or one collection element.

```mojo
@fieldwise_init
struct Span(Copyable, Writable):
    var start: Int      # Start index (inclusive)
    var end: Int        # End index (exclusive)
    var label: UInt64   # Label identifying the strategy kind (used to swap spans of the same kind)
    var depth: Int      # Nesting depth
    var discarded: Bool # Span for an attempt rejected by `filter`
```

- Record spans with TestCase.start_span(label) / stop_span(discard=False); tc.draw creates spans automatically.
- Shrinking passes use spans for structural operations such as deleting a whole list element or reordering spans with the same label.
- Span labels depend only on the strategy kind. The label passed to tc.draw(strategy, label) is for reporting; spans use the required Strategy.span_label() method, typically implemented with kind_label("<kind>"). Different strategies with the same reporting label therefore receive distinct span labels.
- draw reserves a recording slot before delegating to strategy.draw, then fills in its Writable representation after the value returns. This preserves call order in reports when composite strategies call tc.draw internally. The reserved slot is canceled if drawing raises.

### TestCase

The only mutable object for one property execution.

### Supplying choices

| Mode | Source | After the prefix is exhausted |
|--------|--------|------------------------|
| Generation | PRNG | Continue generating from the PRNG |
| Replay | Provided prefix | Return 0 (the simplest value) for all subsequent choices |

- If a prefix value exceeds the current `max_value`, clamp it to `max_value`. This keeps replay working when shrinking changes earlier choices and therefore the bounds of later choices.
- If the number of choices exceeds `Settings.max_choices` (8192 by default), set the state to `OVERRUN` and stop.

### Primitives

```mojo
def draw_integer(mut self, max_value: UInt64) raises -> UInt64
def draw_boolean(mut self, p_true: Float64 = 0.5) raises -> Bool
def draw_float_bits(mut self) raises -> UInt64
def forced_integer(mut self, value: UInt64, max_value: UInt64) raises -> UInt64
def start_span(mut self, label: UInt64)
def stop_span(mut self, discard: Bool = False)
```

The `draw_boolean` bias `p_true` is used only during generation; the recorded value is 0 or 1. 0 (`False`) is the simpler value.

`forced_integer` consumes no randomness, but advances the prefix cursor during replay. A forced choice still occupies a slot in the choice sequence, so later replay must remain aligned with the original execution.

### User-facing operations

```mojo
def draw[S: Strategy](mut self, strategy: S, label: StringSlice = "") raises -> S.Value
def assume(mut self, condition: Bool) raises
def note(mut self, message: String)
def target(mut self, score: Float64, label: StringSlice = "")
```

`draw` records the value’s `Writable` representation with its label for counterexample reports.

`target` guides generation toward higher scores. It keeps the highest finite score in one execution (ignoring NaN and infinity). `label` is a reporting category for future use and does not affect choices. The runner keeps the choice sequence with the highest score from a `VALID` execution. In the latter half of generation (after half of `max_examples` executions are `VALID`), it explores by replaying mutations of that sequence. Each non-`forced` choice has a 0.1 probability of being replaced with a uniform value in `0..=max_value`; at least one choice is mutated. Forced choices are preserved. Runs that do not call `target` follow the existing generation path and preserve reproducibility (the same seed produces the same report).

### States

```text
          ┌──────────── property completes normally ────────────► VALID
RUNNING ──┼──────────── `assume` fails / too many `filter` rejections ──► INVALID
          ├──────────── choice limit exceeded ────────────────► OVERRUN
          └──────────── property raises ──────────────► INTERESTING
```

- `assume` and `OVERRUN` set the state and raise an internal `Error` to stop the property.
- When an exception is caught, the runner classifies it using **`tc.status`, not the message**. If the state is still `RUNNING`, the property itself failed (`INTERESTING`). This avoids collisions with user exception messages.
- For `INTERESTING`, preserve the exception message as the failure description.
