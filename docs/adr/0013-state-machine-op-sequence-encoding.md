# ADR-0013: Test state machines with a `StateMachine` trait and encoded operation sequences

- Status: Accepted
- Date: 2026-09-30
- Related: Issue #28, the state machine testing section of [specs/strategies.md](../specs/strategies.md)

## Context

We needed a way to generate operation sequences and verify invariants, similar to Hypothesis's `RuleBasedStateMachine` or `proptest-state-machine`. Constraints:

- A property is a `def(mut TestCase) raises` closure (ADR-0004), so operation selection must also be represented by a sequence of choices. Otherwise, shrinking and replay cannot be based on the choice sequence alone.
- Each user has a different set of rules, so the abstraction must work with static dispatch (ADR-0003). Capturing closures cannot be stored in structs (ADR-0005).
- The shrinking loop currently only supports chunk deletion, zeroing, and individual minimization (M1). Span passes exist as pure functions but are not connected to the loop (M3). Operation sequences must shrink effectively with the current loop.

## Decision

- Introduce a `StateMachine` trait (`Movable`, `Deinitable`). The implementation struct holds the SUT and model as fields and provides three methods: `num_rules` (rule count), `run_rule` (draw arguments with `tc.draw`, apply preconditions with `tc.assume`, and apply the rule to both), and `check_invariants` (compare both).
- Centralize sequence execution in `run_state_machine(machine, tc, max_ops=32)`. Draw the operation count first with `integers(0, max_ops)`, then repeat "choose a rule number → `run_rule` → `check_invariants`" that many times. Wrap each operation in one span and record `step i: rule r` with `tc.note`.
- Draw the operation count first. Shrinking the count always removes operations from the end, and each operation occupies a contiguous region of choices, allowing chunk deletion to remove operations in the middle. Per-operation spans can be used directly by a future `delete_spans` pass.

## Alternatives Considered

- Register rules in a table of comptime functions: each rule may have different argument types, so a heterogeneous set cannot use static dispatch. A single method branching on the rule number is simpler.
- Generate operations with a continue-flag pattern like `lists`: the flag, rule, and arguments would require at least three choices per operation, which aligns poorly with current chunk widths (8, 4, 2, 1) and provides no control for removing operations from the end. Drawing the count first fits the current shrink loop better.
- Implement after connecting span passes to the shrink loop: that is M3 work and would conflict with parallel PRs changing the shared core. It is outside this issue's scope; record spans now so they are ready for future integration.

## Consequences

- A buggy stack shrinks to three operations, `push(0), push(1), pop` (the provable minimum), confirmed across 15 seeds.
- With three or more choices per operation, current chunk deletion may not remove an entire operation. Keep arguments to one `integers` draw to work around this; connecting `delete_spans` (M3) will address it.
- Left-to-right individual minimization may stop at a local minimum such as `(1, 0)`; a future M3 pass equivalent to `lower_duplicates` should address this. Tests should assert properties independent of operation order.
