from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase
from std.testing import TestSuite, assert_equal, assert_true


def _node(value: UInt64, max_value: UInt64) -> ChoiceNode:
    return ChoiceNode(ChoiceKind.INTEGER, value, max_value, Bool(False))


def _generating(seed: UInt64 = UInt64(1)) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _prop_rejects(mut tc: TestCase) raises:
    tc.assume(False)


def _prop_fails(mut tc: TestCase) raises:
    _ = tc.draw_integer(UInt64(10))
    raise Error("boom")


def test_status_constants_are_distinct() raises:
    var all = List[Status]()
    all.append(Status.RUNNING)
    all.append(Status.VALID)
    all.append(Status.INVALID)
    all.append(Status.OVERRUN)
    all.append(Status.INTERESTING)
    for i in range(len(all)):
        for j in range(len(all)):
            assert_equal(all[i] == all[j], i == j)
    assert_equal(Status.RUNNING, Status(0))
    assert_equal(Status.VALID, Status(1))
    assert_equal(Status.INVALID, Status(2))
    assert_equal(Status.OVERRUN, Status(3))
    assert_equal(Status.INTERESTING, Status(4))


def test_status_writable_renders_each_state() raises:
    assert_equal(String(Status.RUNNING), "RUNNING")
    assert_equal(String(Status.VALID), "VALID")
    assert_equal(String(Status.INVALID), "INVALID")
    assert_equal(String(Status.OVERRUN), "OVERRUN")
    assert_equal(String(Status.INTERESTING), "INTERESTING")


def test_generating_draw_integer_records_choices() raises:
    var tc = _generating()
    assert_equal(tc.status, Status.RUNNING)
    var total = UInt64(0)
    for _ in range(8):
        var v = tc.draw_integer(UInt64(100))
        assert_true(v <= UInt64(100), msg="draw must honor max_value")
        total += v
    assert_true(total > 0, msg="draws must not be degenerate")
    assert_equal(len(tc), 8)
    assert_equal(len(tc.choices), 8)
    for i in range(len(tc.choices)):
        var node = tc.choices[i]
        assert_equal(node.kind, ChoiceKind.INTEGER)
        assert_equal(node.max_value, UInt64(100))
        assert_equal(node.forced, False)


def test_generating_is_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(7))
    var b = _generating(UInt64(7))
    for _ in range(8):
        assert_equal(a.draw_integer(UInt64(1000)), b.draw_integer(UInt64(1000)))
        assert_equal(a.draw_boolean(), b.draw_boolean())
    assert_equal(a.choices, b.choices)


def test_draw_integer_full_range_does_not_raise() raises:
    var tc = _generating()
    _ = tc.draw_integer(UInt64(0xFFFFFFFFFFFFFFFF))
    _ = tc.draw_integer(UInt64(0))
    assert_equal(len(tc), 2)
    assert_equal(tc.choices[1].value, UInt64(0))


def test_replay_reproduces_prefix() raises:
    var gen = _generating(UInt64(3))
    for _ in range(4):
        _ = gen.draw_integer(UInt64(50))
    var tc = TestCase.replaying(gen.choices.copy())
    for i in range(4):
        assert_equal(tc.draw_integer(UInt64(50)), gen.choices[i].value)
    assert_equal(tc.choices, gen.choices)


def test_replay_clamps_prefix_value_to_current_max() raises:
    var prefix = ChoiceSequence()
    prefix.append(_node(UInt64(100), UInt64(100)))
    var tc = TestCase.replaying(prefix^)
    assert_equal(tc.draw_integer(UInt64(10)), UInt64(10))
    assert_equal(tc.choices[0].value, UInt64(10))


def test_replay_exhaustion_returns_zero() raises:
    var prefix = ChoiceSequence()
    prefix.append(_node(UInt64(9), UInt64(100)))
    var tc = TestCase.replaying(prefix^)
    assert_equal(tc.draw_integer(UInt64(100)), UInt64(9))
    assert_equal(tc.draw_integer(UInt64(100)), UInt64(0))
    assert_equal(tc.draw_boolean(), False)
    assert_equal(tc.choices.values()[1], UInt64(0))
    assert_equal(tc.choices.values()[2], UInt64(0))


def test_replay_records_consumed_choices() raises:
    var prefix = ChoiceSequence()
    prefix.append(_node(UInt64(4), UInt64(10)))
    var tc = TestCase.replaying(prefix^)
    _ = tc.draw_integer(UInt64(10))
    _ = tc.draw_integer(UInt64(10))
    assert_equal(len(tc.choices), 2)
    assert_equal(tc.choices[0].value, UInt64(4))
    assert_equal(tc.choices[1].value, UInt64(0))


def test_forced_integer_skips_randomness_and_shrinking() raises:
    var a = _generating(UInt64(11))
    _ = a.forced_integer(UInt64(9), UInt64(100))
    var first = a.draw_integer(UInt64(100))
    var b = _generating(UInt64(11))
    assert_equal(b.draw_integer(UInt64(100)), first)
    assert_equal(a.choices[0].forced, True)
    assert_equal(a.choices[0].value, UInt64(9))
    assert_equal(a.choices[1].forced, False)


def test_forced_integer_clamps_to_max() raises:
    var tc = _generating()
    assert_equal(tc.forced_integer(UInt64(999), UInt64(10)), UInt64(10))
    assert_equal(tc.choices[0].value, UInt64(10))


def test_draw_boolean_bias_shapes_generation_only() raises:
    var always_true = _generating()
    var always_false = _generating()
    for _ in range(8):
        assert_equal(always_true.draw_boolean(1.0), True)
        assert_equal(always_false.draw_boolean(0.0), False)
    for i in range(8):
        assert_equal(always_true.choices[i].kind, ChoiceKind.BOOLEAN)
        assert_equal(always_true.choices[i].max_value, UInt64(1))

    var replay = TestCase.replaying(always_true.choices.copy())
    for _ in range(8):
        assert_equal(replay.draw_boolean(0.0), True)


def test_spans_record_nested_intervals() raises:
    var tc = _generating()
    tc.start_span(UInt64(7))
    _ = tc.draw_integer(UInt64(10))
    tc.start_span(UInt64(8))
    _ = tc.draw_integer(UInt64(10))
    tc.stop_span()
    _ = tc.draw_integer(UInt64(10))
    tc.stop_span()
    assert_equal(len(tc.spans), 2)
    assert_equal(tc.spans[0].start, 1)
    assert_equal(tc.spans[0].end, 2)
    assert_equal(tc.spans[0].label, UInt64(8))
    assert_equal(tc.spans[0].depth, 1)
    assert_equal(tc.spans[0].discarded, False)
    assert_equal(tc.spans[1].start, 0)
    assert_equal(tc.spans[1].end, 3)
    assert_equal(tc.spans[1].label, UInt64(7))
    assert_equal(tc.spans[1].depth, 0)


def test_stop_span_marks_discard_and_ignores_empty_stack() raises:
    var tc = _generating()
    tc.stop_span()
    assert_equal(len(tc.spans), 0)
    tc.start_span(UInt64(1))
    _ = tc.draw_integer(UInt64(5))
    tc.stop_span(discard=True)
    assert_equal(len(tc.spans), 1)
    assert_equal(tc.spans[0].discarded, True)


def test_assume_true_continues_false_marks_invalid() raises:
    var tc = _generating()
    tc.assume(True)
    assert_equal(tc.status, Status.RUNNING)
    var raised = False
    try:
        tc.assume(False)
    except:
        raised = True
    assert_true(raised, msg="assume(False) must interrupt the property")
    assert_equal(tc.status, Status.INVALID)


def test_overrun_sets_status_and_raises() raises:
    var tc = TestCase.generating(derive(UInt64(1), UInt64(0)), 3)
    _ = tc.draw_integer(UInt64(10))
    _ = tc.draw_boolean()
    _ = tc.forced_integer(UInt64(1), UInt64(10))
    assert_equal(tc.status, Status.RUNNING)
    var raised = False
    try:
        _ = tc.draw_integer(UInt64(10))
    except:
        raised = True
    assert_true(raised, msg="drawing past max_choices must interrupt")
    assert_equal(tc.status, Status.OVERRUN)
    assert_equal(len(tc.choices), 3)


def test_runner_classifies_via_status_not_message() raises:
    var rejected = _generating()
    try:
        _prop_rejects(rejected)
    except:
        pass
    assert_equal(rejected.status, Status.INVALID)

    var failed = _generating()
    try:
        _prop_fails(failed)
    except:
        pass
    assert_equal(
        failed.status,
        Status.RUNNING,
        msg="untouched status means the property itself failed",
    )


def test_note_records_messages_in_order() raises:
    var tc = _generating()
    tc.note(String("first"))
    tc.note(String("second"))
    assert_equal(len(tc.notes), 2)
    assert_equal(tc.notes[0], String("first"))
    assert_equal(tc.notes[1], String("second"))


def test_default_max_choices_matches_spec() raises:
    assert_equal(DEFAULT_MAX_CHOICES, 8192)
    var tc = _generating()
    assert_equal(tc.max_choices, 8192)


def test_writable_renders_summary() raises:
    var tc = _generating()
    _ = tc.draw_integer(UInt64(5))
    tc.note(String("n"))
    var text = String(tc)
    assert_equal(text, "TestCase(status=RUNNING, choices=1, spans=0, notes=1)")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
