# State-machine testing

Use state-machine testing to check stateful systems such as containers, connections, and files against a model. Implement the `StateMachine` trait with the system under test and its model, then call `run_state_machine` from a property.

The runner generates an operation sequence, applies each rule to the machine, and checks invariants after every operation. Each operation has its own span, so shrinking can remove operations as well as simplify the values drawn by a rule.

```mojo
trait StateMachine(Movable, Deinitable):
    def num_rules(self) -> Int:
        ...

    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        ...

    def check_invariants(self) raises:
        ...
```

Rules are numbered from `0` to `num_rules() - 1`. Draw rule arguments with `tc.draw`, express preconditions with `tc.assume`, and raise an error when the implementation disagrees with the model. Add details with `tc.note` so the counterexample report explains what happened.

```mojo
def stack_property(mut tc: TestCase) raises:
    var machine = run_state_machine(StackMachine(), tc, max_ops=16)
```

See [`tests/test_stateful.mojo`](../../tests/test_stateful.mojo) for a complete implementation. Keep `max_ops` modest while developing a property; shorter sequences are easier to inspect and shrink.

`tc.target` remains planned. See the feature matrix in [Specs: Overview](../specs/overview.md) for its status.
