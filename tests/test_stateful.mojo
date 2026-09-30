from proptest import Settings, Status, TestCase, for_all, integers
from proptest import run_state_machine
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.stateful import StateMachine
from std.testing import TestSuite, assert_equal, assert_true


struct BuggyStack(Movable):
    var items: List[Int]

    def __init__(out self):
        self.items = List[Int]()

    def push(mut self, value: Int):
        self.items.append(value)

    def pop(mut self) raises -> Int:
        if len(self.items) == 0:
            raise Error("pop from empty stack")
        # BUG: removes the last element like a stack but returns the
        # front like a queue, so results diverge once two elements
        # are stored.
        var front = self.items[0]
        var rest = List[Int]()
        for i in range(len(self.items) - 1):
            rest.append(self.items[i])
        self.items = rest^
        return front


struct StackMachine(StateMachine):
    var sut: BuggyStack
    var model: List[Int]

    def __init__(out self):
        self.sut = BuggyStack()
        self.model = List[Int]()

    def num_rules(self) -> Int:
        return 2

    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        if rule == 0:
            var value = tc.draw(integers(0, 10), "push.value")
            tc.note("push(" + String(value) + ")")
            self.sut.push(value)
            self.model.append(value)
        elif rule == 1:
            tc.assume(len(self.model) > 0)
            var got = self.sut.pop()
            var want = self.model.pop()
            tc.note("pop() -> " + String(got))
            if got != want:
                raise Error(
                    "pop mismatch: got "
                    + String(got)
                    + ", want "
                    + String(want)
                )
        else:
            raise Error("unknown rule: " + String(rule))

    def check_invariants(self) raises:
        if len(self.sut.items) != len(self.model):
            raise Error(
                "size mismatch: sut has "
                + String(len(self.sut.items))
                + ", model has "
                + String(len(self.model))
            )
        for i in range(len(self.model)):
            if self.sut.items[i] != self.model[i]:
                raise Error("content mismatch at index " + String(i))


struct ZeroRuleMachine(StateMachine):
    def __init__(out self):
        pass

    def num_rules(self) -> Int:
        return 0

    def run_rule(mut self, mut tc: TestCase, rule: Int) raises:
        raise Error("must not run")

    def check_invariants(self) raises:
        pass


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _stack_prop(mut tc: TestCase) raises:
    _ = run_state_machine(StackMachine(), tc)


def test_all_zero_runs_zero_ops() raises:
    var tc = _empty()
    var done = run_state_machine(StackMachine(), tc)
    assert_equal(len(done.model), 0)
    assert_equal(len(done.sut.items), 0)
    assert_equal(len(tc.choices), 1)


def test_max_ops_zero_runs_nothing() raises:
    var tc = _generating(UInt64(7))
    var done = run_state_machine(StackMachine(), tc, 0)
    assert_equal(len(done.model), 0)
    assert_equal(len(tc.choices), 1)


def test_negative_max_ops_raise() raises:
    var tc = _empty()
    var raised = False
    try:
        _ = run_state_machine(StackMachine(), tc, -1)
    except:
        raised = True
    assert_true(raised, msg="negative max_ops must raise")


def test_zero_rules_raise() raises:
    var tc = _empty()
    var raised = False
    try:
        _ = run_state_machine(ZeroRuleMachine(), tc)
    except:
        raised = True
    assert_true(raised, msg="zero rules must raise")


def test_pop_on_empty_is_invalid() raises:
    var prefix = ChoiceSequence()
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(32), Bool(False))
    )
    prefix.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(1), UInt64(1), Bool(False))
    )
    var tc = TestCase.replaying(prefix^)
    try:
        _ = run_state_machine(StackMachine(), tc)
    except:
        pass
    assert_true(tc.status == Status.INVALID, msg="pop on empty must be INVALID")


def test_check_invariants_catches_divergence() raises:
    var benign = StackMachine()
    benign.check_invariants()
    var diverged = StackMachine()
    diverged.sut.push(1)
    diverged.model.append(2)
    var raised = False
    try:
        diverged.check_invariants()
    except:
        raised = True
    assert_true(raised, msg="diverged state must raise")


def test_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(11))
    try:
        _ = run_state_machine(StackMachine(), a)
    except:
        pass
    var b = _generating(UInt64(11))
    try:
        _ = run_state_machine(StackMachine(), b)
    except:
        pass
    assert_equal(a.choices, b.choices)


def test_buggy_stack_shrinks_to_push_push_pop() raises:
    var report = String("")
    try:
        for_all(_stack_prop, Settings(seed=UInt64(1), max_examples=100))
    except e:
        report = String(e)
    assert_true(("ops = 3" in report), msg="three operations, got: " + report)
    # The push pair always minimizes to {0, 1}, but left-to-right
    # minimization may leave either order, so assert both without order.
    assert_true(("push(0)" in report), msg="minimal push value: " + report)
    assert_true(("push(1)" in report), msg="distinct push value: " + report)
    assert_true(("pop() -> " in report), msg="failing pop reported: " + report)
    assert_true(("pop mismatch" in report), msg="mismatch message: " + report)
    assert_true(not ("step 3:" in report), msg="exactly three steps: " + report)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
