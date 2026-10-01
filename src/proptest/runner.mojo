"""Generation phase and counterexample reporting for property tests.

Implements `docs/specs/runner.md` (ADR-0004, ADR-0006, ADR-0008).

`for_all` runs a `def(mut TestCase) raises -> None` property against
derived examples, shrinks the first failure, and raises the replayed
counterexample as an `Error`. Executions are classified by `tc.status`,
never by the exception message, so user messages cannot collide with
control flow.
"""

from std.io import Writer
from std.os import getenv
from std.time import monotonic

from proptest.choice import ChoiceSequence
from proptest.prng import derive
from proptest.shrink.shrinker import Evaluation, shrink_with
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase

comptime DEFAULT_MAX_EXAMPLES = 100
comptime DEFAULT_MAX_SHRINK_EVALUATIONS = 5000
comptime SEED_ENV_VAR = "PROPTEST_SEED"
comptime MAX_EXAMPLES_ENV_VAR = "PROPTEST_MAX_EXAMPLES"


struct Settings(Copyable, Movable, Writable):
    """Immutable run parameters for `for_all`.

    A `None` seed resolves to `PROPTEST_SEED` when set, else to a
    time-derived seed. A default `max_examples` resolves to
    `PROPTEST_MAX_EXAMPLES` when set, so CI can raise the count without
    code changes; any explicitly different value wins over the
    environment.
    """

    var max_examples: Int
    var seed: Optional[UInt64]
    var max_choices: Int
    var max_shrink_evaluations: Int

    def __init__(
        out self,
        max_examples: Int = DEFAULT_MAX_EXAMPLES,
        seed: Optional[UInt64] = None,
        max_choices: Int = DEFAULT_MAX_CHOICES,
        max_shrink_evaluations: Int = DEFAULT_MAX_SHRINK_EVALUATIONS,
    ):
        self.max_examples = max_examples
        self.seed = seed.copy()
        self.max_choices = max_choices
        self.max_shrink_evaluations = max_shrink_evaluations

    def effective_seed(self) raises -> UInt64:
        """Explicit seed, else `PROPTEST_SEED`, else time-derived."""
        if self.seed is not None:
            return self.seed.value()
        var from_env = getenv(SEED_ENV_VAR)
        if from_env.byte_length() > 0:
            try:
                return UInt64(Int(from_env))
            except:
                raise Error(
                    "PROPTEST_SEED is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
        return UInt64(abs(Int(monotonic())))

    def effective_max_examples(self) raises -> Int:
        """Explicit count, else `PROPTEST_MAX_EXAMPLES` over the default."""
        if self.max_examples != DEFAULT_MAX_EXAMPLES:
            return self.max_examples
        var from_env = getenv(MAX_EXAMPLES_ENV_VAR)
        if from_env.byte_length() > 0:
            try:
                var parsed = Int(from_env)
                if parsed > 0:
                    return parsed
            except:
                raise Error(
                    "PROPTEST_MAX_EXAMPLES is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
        return self.max_examples

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Settings(max_examples=", self.max_examples, ", seed=")
        if self.seed is None:
            writer.write("None")
        else:
            writer.write(self.seed.value())
        writer.write(
            ", max_choices=",
            self.max_choices,
            ", max_shrink_evaluations=",
            self.max_shrink_evaluations,
            ")",
        )


def for_all[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings = Settings()) raises:
    """Run `prop` against generated examples, raising the counterexample.

    Attempt zero replays the empty prefix, so every draw sees the
    simplest choice; attempt `i >= 1` draws from `derive(seed, i)`. A
    run with no failure raises nothing. The first `INTERESTING`
    execution is shrunk with `shrink_with`, replayed to collect draw
    records, and reported as an `Error` carrying the records, notes,
    the failure message, and the seed.
    """
    var seed = settings.effective_seed()
    var max_examples = settings.effective_max_examples()

    def evaluate(
        candidate: ChoiceSequence,
    ) raises {imm prop, imm settings} -> Evaluation:
        var tc = TestCase.replaying(candidate.copy(), settings.max_choices)
        var raised = False
        try:
            prop(tc)
        except:
            raised = True
        return Evaluation(
            raised and tc.status == Status.RUNNING, tc.choices.copy()
        )

    var valid_count = 0
    var examples_run = 0
    var invalid_count = 0
    var overrun_count = 0
    var attempt = UInt64(0)
    while valid_count < max_examples:
        var tc = _fresh_test_case(settings.max_choices, seed, attempt)
        var raised = False
        var message = String("")
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        examples_run += 1
        attempt += 1
        if tc.status == Status.INVALID:
            invalid_count += 1
            if invalid_count > 10 * max_examples:
                raise Error(
                    "gave up after "
                    + String(examples_run)
                    + " examples ("
                    + String(invalid_count)
                    + " rejected by assume): condition too strict"
                )
            continue
        if tc.status == Status.OVERRUN:
            overrun_count += 1
            if examples_run >= 10 and overrun_count * 5 > examples_run:
                raise Error(
                    "gave up after "
                    + String(examples_run)
                    + " examples ("
                    + String(overrun_count)
                    + " overran max_choices="
                    + String(settings.max_choices)
                    + "): generated data too large (raise max_choices)"
                )
            continue
        if not raised:
            valid_count += 1
            continue
        var shrink_result = shrink_with(
            evaluate, tc.choices.copy(), settings.max_shrink_evaluations
        )
        var report_tc = TestCase.replaying(
            shrink_result.best.copy(), settings.max_choices
        )
        try:
            prop(report_tc)
        except e:
            message = String(e)
        raise Error(
            _format_report(
                examples_run,
                shrink_result.evaluations,
                report_tc.draw_labels.copy(),
                report_tc.draw_values.copy(),
                report_tc.notes.copy(),
                message,
                seed,
                shrink_result.hit_budget,
            )
        )


def _fresh_test_case(
    max_choices: Int, seed: UInt64, attempt: UInt64
) -> TestCase:
    """Attempt zero replays the empty prefix; later attempts drive generation.

    `attempt` doubles as the example index so `TestCase.size_scale`
    ramps collection lengths; replay paths ignore it.
    """
    if attempt == UInt64(0):
        return TestCase.replaying(ChoiceSequence(), max_choices, attempt)
    return TestCase.generating(derive(seed, attempt), max_choices, attempt)


def _format_report(
    examples_run: Int,
    shrink_evaluations: Int,
    labels: List[String],
    values: List[String],
    notes: List[String],
    message: String,
    seed: UInt64,
    hit_budget: Bool,
) -> String:
    """Render the replayed counterexample as the raised `Error` text."""
    var out = String("Falsifying example (after ")
    out += String(examples_run)
    out += " examples, "
    out += String(shrink_evaluations)
    out += " shrink evaluations):\n"
    for i in range(len(labels)):
        var label = String(labels[i])
        if label.byte_length() == 0:
            label = "draw #" + String(i + 1)
        out += "  "
        out += label
        out += " = "
        out += values[i]
        out += "\n"
    for i in range(len(notes)):
        out += "  note: "
        out += notes[i]
        out += "\n"
    out += "Error: "
    out += message
    out += "\nSeed: "
    out += String(seed)
    if hit_budget:
        out += "\nShrink budget exhausted; counterexample may not be minimal"
    return out^
