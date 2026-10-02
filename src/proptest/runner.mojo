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
from proptest.database import ExampleDatabase
from proptest.encoding import decode_sequence, encode_sequence
from proptest.prng import derive
from proptest.shrink.shrinker import Evaluation, shrink_with
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase

comptime DEFAULT_MAX_EXAMPLES = 100
comptime DEFAULT_MAX_SHRINK_EVALUATIONS = 5000
comptime DEFAULT_DATABASE_DIR = ".proptest-mojo"
comptime SEED_ENV_VAR = "PROPTEST_SEED"
comptime MAX_EXAMPLES_ENV_VAR = "PROPTEST_MAX_EXAMPLES"


struct Settings(Copyable, Movable, Writable):
    """Immutable run parameters for `for_all`.

    A `None` seed resolves to `PROPTEST_SEED` when set, else to a
    time-derived seed. A default `max_examples` resolves to
    `PROPTEST_MAX_EXAMPLES` when set, so CI can raise the count without
    code changes; any explicitly different value wins over the
    environment. An empty `name` disables the example database; a
    non-empty one persists shrunken counterexamples under
    `database_dir` and replays them before generation.
    """

    var max_examples: Int
    var seed: Optional[UInt64]
    var max_choices: Int
    var max_shrink_evaluations: Int
    var replay: Optional[String]
    var name: String
    var database_dir: String

    # Tracked separately from `max_examples`: an explicit
    # `Settings(max_examples=100)` must still beat `PROPTEST_MAX_EXAMPLES`,
    # so equality with the default cannot stand in for "supplied".
    var max_examples_set: Bool

    def __init__(
        out self,
        max_examples: Optional[Int] = None,
        seed: Optional[UInt64] = None,
        max_choices: Int = DEFAULT_MAX_CHOICES,
        max_shrink_evaluations: Int = DEFAULT_MAX_SHRINK_EVALUATIONS,
        replay: Optional[String] = None,
        name: String = "",
        database_dir: String = DEFAULT_DATABASE_DIR,
    ):
        self.max_examples_set = max_examples is not None
        self.max_examples = (
            max_examples.value() if max_examples
            is not None else DEFAULT_MAX_EXAMPLES
        )
        self.seed = seed.copy()
        self.max_choices = max_choices
        self.max_shrink_evaluations = max_shrink_evaluations
        self.replay = replay.copy()
        self.name = name.copy()
        self.database_dir = database_dir.copy()

    def effective_seed(self) raises -> UInt64:
        """Explicit seed, else `PROPTEST_SEED`, else time-derived."""
        if self.seed is not None:
            return self.seed.value()
        var from_env = getenv(SEED_ENV_VAR)
        if from_env.byte_length() > 0:
            # Parsed digit by digit: routing through signed `Int`
            # rejects valid seeds above `Int.MAX`, which is half the
            # domain `Settings.seed` and the reports accept.
            var ok = False
            var parsed = UInt64(0)
            ok, parsed = _parse_u64(from_env)
            if not ok:
                raise Error(
                    "PROPTEST_SEED is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
            return parsed
        return UInt64(abs(Int(monotonic())))

    def effective_max_examples(self) raises -> Int:
        """Explicit count, else `PROPTEST_MAX_EXAMPLES` over the default."""
        if self.max_examples_set:
            if self.max_examples <= 0:
                raise Error("Settings: max_examples must be positive")
            return self.max_examples
        var from_env = getenv(MAX_EXAMPLES_ENV_VAR)
        if from_env.byte_length() > 0:
            var parsed = 0
            try:
                parsed = Int(from_env)
            except:
                raise Error(
                    "PROPTEST_MAX_EXAMPLES is not a valid integer: '"
                    + String(from_env)
                    + "'"
                )
            if parsed <= 0:
                raise Error(
                    "PROPTEST_MAX_EXAMPLES must be positive: '"
                    + String(from_env)
                    + "'"
                )
            return parsed
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
        )
        if self.replay is not None:
            writer.write(', replay="', self.replay.value(), '"')
        if self.name.byte_length() > 0:
            writer.write(', name="', self.name, '"')
        if self.database_dir != DEFAULT_DATABASE_DIR:
            writer.write(', database_dir="', self.database_dir, '"')
        writer.write(")")


comptime U64_MAX = UInt64(0xFFFFFFFFFFFFFFFF)


def _parse_u64(text: String) -> Tuple[Bool, UInt64]:
    """Parse a decimal string into a `UInt64`.

    Returns `(False, 0)` for a non-numeric or out-of-range value.
    Accumulating in `UInt64` keeps the whole `0..=UInt64.MAX` domain
    reachable; a signed `Int` accumulator would reject the upper half of
    it before the seed could be reported or replayed.
    """
    var digits = text.as_bytes()
    if len(digits) == 0:
        return (False, UInt64(0))
    var acc = UInt64(0)
    for b in digits:
        if b < 48 or b > 57:
            return (False, UInt64(0))
        var digit = UInt64(b - 48)
        if acc > (U64_MAX - digit) // UInt64(10):
            return (False, UInt64(0))
        acc = acc * UInt64(10) + digit
    return (True, acc)


def for_all[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings = Settings()) raises:
    """Run `prop` against generated examples, raising the counterexample.

    Attempt zero replays the empty prefix, so every draw sees the
    simplest choice; attempt `i >= 1` draws from `derive(seed, i)`. A
    run with no failure raises nothing. The first `INTERESTING`
    execution is shrunk with `shrink_with`, replayed to collect draw
    records, and reported as an `Error` carrying the records, notes,
    the failure message, the seed, and the replay string. When
    `settings.name` is set, saved counterexamples replay before
    generation and the shrunk result is persisted. When
    `settings.replay` is set, only those choices run once: a reproduced
    failure is reported as-is with no generation or shrinking, while a
    run that no longer fails raises instead of searching for a new
    counterexample.
    """
    if settings.replay is not None:
        _replay_only(prop, settings, String(settings.replay.value()))
        return
    var seed = settings.effective_seed()
    var max_examples = settings.effective_max_examples()
    var db = ExampleDatabase(settings.database_dir.copy(), settings.name.copy())
    _replay_database(prop, settings, seed, db)

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
        _shrink_and_raise(
            prop, settings, seed, examples_run, tc.choices.copy(), message, db
        )


def _replay_database[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings, seed: UInt64, db: ExampleDatabase) raises:
    """Replay saved counterexamples before generation (spec phase 1).

    The first replay that still fails short-circuits to shrinking and
    reporting. Replays that no longer fail are stale, so their files are
    deleted.
    """
    var saved = db.load()
    for i in range(len(saved)):
        var entry = saved[i].copy()
        var token = entry.replay.copy()
        var prefix = ChoiceSequence()
        try:
            prefix = decode_sequence(token)
        except:
            db.remove_file(entry.filename.copy())
            continue
        var tc = TestCase.replaying(prefix^, settings.max_choices)
        var raised = False
        var message = String("")
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        if raised and tc.status == Status.RUNNING:
            _shrink_and_raise(
                prop, settings, seed, i + 1, tc.choices.copy(), message, db
            )
        else:
            db.remove_file(entry.filename.copy())


def _shrink_and_raise[
    P: def(mut TestCase) raises -> None
](
    prop: P,
    settings: Settings,
    seed: UInt64,
    examples_run: Int,
    failing: ChoiceSequence,
    failure_message: String,
    db: ExampleDatabase,
) raises:
    """Shrink `failing`, persist the best replay, and raise the report.

    Shared by the database-replay and generation paths so both persist
    to the example database and report identically.
    """

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

    var shrink_result = shrink_with(
        evaluate, failing.copy(), settings.max_shrink_evaluations
    )
    var report_tc = TestCase.replaying(
        shrink_result.best.copy(), settings.max_choices
    )
    var replay_message = failure_message.copy()
    try:
        prop(report_tc)
    except e:
        replay_message = String(e)
    var replay_token = encode_sequence(report_tc.choices.copy())
    db.save(replay_token)
    raise Error(
        _format_report(
            examples_run,
            shrink_result.evaluations,
            report_tc.draw_labels.copy(),
            report_tc.draw_values.copy(),
            report_tc.notes.copy(),
            replay_message^,
            seed,
            shrink_result.hit_budget,
            replay_token^,
        )
    )


def _replay_only[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings, replay_token: String) raises:
    """Run recorded choices once, reporting a reproduced failure as-is.

    Generation and shrinking are skipped. A run that no longer fails
    raises instead of searching for a new counterexample.
    """
    var prefix: ChoiceSequence
    try:
        prefix = decode_sequence(replay_token)
    except e:
        raise Error("invalid replay string: " + String(e))
    var tc = TestCase.replaying(prefix^, settings.max_choices)
    var raised = False
    var message = String("")
    try:
        prop(tc)
    except e:
        raised = True
        message = String(e)
    if not raised or tc.status != Status.RUNNING:
        raise Error(
            "replay did not reproduce a failure (status="
            + String(tc.status)
            + ")"
        )
    raise Error(
        _format_report(
            1,
            0,
            tc.draw_labels.copy(),
            tc.draw_values.copy(),
            tc.notes.copy(),
            message,
            None,
            False,
            replay_token,
        )
    )


def _fresh_test_case(
    max_choices: Int, seed: UInt64, attempt: UInt64
) -> TestCase:
    """Attempt zero replays the empty prefix (all-zero choices)."""
    if attempt == UInt64(0):
        return TestCase.replaying(ChoiceSequence(), max_choices)
    return TestCase.generating(derive(seed, attempt), max_choices)


def _format_report(
    examples_run: Int,
    shrink_evaluations: Int,
    labels: List[String],
    values: List[String],
    notes: List[String],
    message: String,
    seed: Optional[UInt64],
    hit_budget: Bool,
    replay_token: String,
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
    if seed is not None:
        out += "\nSeed: "
        out += String(seed.value())
    if hit_budget:
        out += "\nShrink budget exhausted; counterexample may not be minimal"
    out += '\nReproduce with: Settings(replay="'
    out += replay_token
    out += '")'
    return out^
