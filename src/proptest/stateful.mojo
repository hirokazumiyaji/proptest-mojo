"""State machine testing: operation sequences checked against a model.

Implements the stateful section of `docs/specs/strategies.md`
(ADR-0003, ADR-0004, ADR-0010).

A `StateMachine` struct owns both the system under test and its model.
`run_state_machine` draws an operation count, then runs that many rules
chosen from the choice sequence, checking invariants after every step.
Each operation sits in its own span, so operation lists shrink like
collections; minimizing the count choice trims trailing operations.
"""

from proptest.strategies.primitives import integers
from proptest.testcase import TestCase

comptime _STEP_SPAN_LABEL = UInt64(0x53544154454F5053)


trait StateMachine(Deinitable, Movable):
    """System under test plus model, driven one rule at a time.

    Rules are numbered `0 .. num_rules() - 1`. `run_rule` draws its own
    arguments with `tc.draw` and applies them to both sides, so argument
    values shrink like any other generated value. Preconditions use
    `tc.assume`, which skips the example as `INVALID`. `check_invariants`
    compares the two sides and raises on any mismatch.
    """

    def num_rules(self) -> Int:
        ...

    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        ...

    def check_invariants(self) raises:
        ...


def run_state_machine[
    M: StateMachine
](var machine: M, mut tc: TestCase, max_ops: Int = 32) raises -> M:
    """Run `machine` for a generated number of operations, returning it.

    The count comes from `integers(0, max_ops)`, so all-zero choices run
    zero operations and minimizing the count drops trailing operations.
    Every operation draws its rule index inside its own span under the
    label `rule`, notes `step i: rule r` for the report, then runs
    `run_rule` followed by `check_invariants`. Machines note their own
    operation details; rule arguments drawn with `tc.draw` are reported
    under their labels.
    """
    var rules = machine.num_rules()
    if rules <= 0:
        raise Error("run_state_machine: num_rules must be > 0")
    if max_ops < 0:
        raise Error("run_state_machine: max_ops must be >= 0")
    var count = tc.draw(integers(0, max_ops), "ops")
    for step in range(count):
        var depth = len(tc.open_spans)
        tc.start_span(_STEP_SPAN_LABEL)
        try:
            var rule = tc.draw(integers(0, rules - 1), "rule")
            tc.note("step " + String(step) + ": rule " + String(rule))
            machine.run_rule(tc, rule)
            machine.check_invariants()
            tc.stop_span()
        except e:
            # Close every span opened under this step, marking them
            # `discarded` so shrink passes do not reorder them with
            # successful siblings. `run_rule` or `check_invariants` may
            # leave inner spans open, so mirror `TestCase.draw`'s depth
            # loop instead of closing a single span.
            while len(tc.open_spans) > depth:
                tc.stop_span(discard=True)
            raise e
    return machine^
