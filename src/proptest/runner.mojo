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
from std.time import perf_counter_ns

from proptest.choice import ChoiceSequence
from proptest.database import ExampleDatabase, sha256_hex
from proptest.encoding import decode_sequence, encode_sequence
from proptest.prng import Xoshiro256StarStar, derive
from proptest.shrink.shrinker import Evaluation, shrink_with
from proptest.testcase import (
    ASSUME_INTERRUPT,
    DEFAULT_MAX_CHOICES,
    OVERRUN_INTERRUPT,
    Status,
    TestCase,
)

comptime DEFAULT_MAX_EXAMPLES = 100
comptime DEFAULT_MAX_SHRINK_EVALUATIONS = 5000
comptime DEFAULT_DATABASE_DIR = ".proptest-mojo"
comptime SEED_ENV_VAR = "PROPTEST_SEED"
comptime MAX_EXAMPLES_ENV_VAR = "PROPTEST_MAX_EXAMPLES"
comptime TARGET_MUTATION_PROBABILITY = 0.1


@fieldwise_init
struct Verbosity(Equatable, TrivialRegisterPassable, Writable):
    """How much of the generation loop `for_all` reports.

    `QUIET` and `NORMAL` stay silent on success; the distinction is
    reserved for future replay/database notices. `VERBOSE` prints every
    example as it runs, so a passing run still shows what was tried.
    """

    var value: UInt8

    comptime QUIET = Verbosity(0)
    comptime NORMAL = Verbosity(1)
    comptime VERBOSE = Verbosity(2)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def write_to(self, mut writer: Some[Writer]):
        if self == Self.QUIET:
            writer.write("QUIET")
        elif self == Self.NORMAL:
            writer.write("NORMAL")
        else:
            writer.write("VERBOSE")


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
    var verbosity: Verbosity
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
        verbosity: Verbosity = Verbosity.NORMAL,
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
        self.verbosity = verbosity
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
        return UInt64(abs(perf_counter_ns()))

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
            ", verbosity=",
            self.verbosity,
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
    simplest choice; attempt `i >= 1` draws from `derive(seed, i)`,
    except the second half of generation replays a targeted mutant of
    the highest-`target` valid sequence when one exists. A run with no
    failure raises nothing. The first `INTERESTING` execution is
    shrunk with `shrink_with`, replayed to collect draw records, and
    reported as an `Error` carrying the records, notes, the failure
    message, the seed, and the replay string. When `settings.name` is
    set, saved counterexamples replay before generation and the shrunk
    result is persisted. When `settings.replay` is set, only those choices
    run once: a reproduced failure is reported as-is with no generation or
    shrinking, while a run that no longer fails raises instead of searching
    for a new counterexample. Executions rejected by `assume` (or an
    unsatisfiable `filter`, which rejects the same way) are skipped; too many
    rejections or overruns fail the run with a health-check `Error`
    naming the rejection rate. `VERBOSE` settings print every example
    as it runs.
    """
    if settings.replay is not None:
        _replay_only(prop, settings, String(settings.replay.value()))
        return
    var seed = settings.effective_seed()
    var max_examples = settings.effective_max_examples()
    var db = ExampleDatabase(settings.database_dir.copy(), settings.name.copy())
    var replays_run = _replay_database(prop, settings, seed, db)
    var verbose = settings.verbosity == Verbosity.VERBOSE

    var valid_count = 0
    var examples_run = replays_run
    var invalid_count = 0
    var overrun_count = 0
    var attempt = UInt64(0)
    var has_best = False
    var best_score = 0.0
    var best_seq = ChoiceSequence()
    while valid_count < max_examples:
        var tc: TestCase
        if has_best and valid_count * 2 >= max_examples:
            tc = _mutated_test_case(
                best_seq, seed, attempt, settings.max_choices
            )
        else:
            tc = _fresh_test_case(settings.max_choices, seed, attempt)
        var raised = False
        var message = String("")
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        examples_run += 1
        attempt += 1
        if tc.status == Status.RUNNING:
            tc.status = Status.INTERESTING if raised else Status.VALID
        if verbose:
            print(
                _format_example_line(
                    examples_run,
                    tc.status,
                    tc.draw_labels.copy(),
                    tc.draw_values.copy(),
                )
            )
        if tc.status == Status.INVALID:
            invalid_count += 1
            if invalid_count > 10 * max_examples:
                raise Error(
                    _too_many_rejects_message(
                        examples_run, invalid_count, valid_count
                    )
                )
            continue
        if tc.status == Status.OVERRUN:
            overrun_count += 1
            if overrun_count * 5 > examples_run:
                raise Error(
                    _too_many_overruns_message(
                        examples_run,
                        overrun_count,
                        valid_count,
                        settings.max_choices,
                    )
                )
            continue
        # Rechecked after a VALID attempt too: overruns that happened
        # while `examples_run < 10` would otherwise escape the ratio
        # check entirely when the last required valid example completes
        # the loop, silently passing a run that mostly overran.
        if (
            examples_run >= 10
            and overrun_count > 0
            and overrun_count * 5 > examples_run
        ):
            raise Error(
                _too_many_overruns_message(
                    examples_run,
                    overrun_count,
                    valid_count,
                    settings.max_choices,
                )
            )
        if not raised:
            valid_count += 1
            if tc.has_target and (not has_best or tc.target_score > best_score):
                has_best = True
                best_score = tc.target_score
                best_seq = tc.choices.copy()
            continue
        if not _shrink_and_raise(
            prop, settings, seed, examples_run, tc.choices.copy(), message, db
        ):
            continue


def _replay_database[
    P: def(mut TestCase) raises -> None
](prop: P, settings: Settings, seed: UInt64, db: ExampleDatabase) raises -> Int:
    """Replay saved counterexamples before generation (spec phase 1).

    The first replay that still fails short-circuits to shrinking and
    reporting. Replays that no longer fail are stale, so their files are
    deleted. Returns the number of database replay executions performed.
    """
    var saved = db.load()
    var replays_run = 0
    for i in range(len(saved)):
        var entry = saved[i].copy()
        var token = entry.replay.copy()
        var saved_seq = ChoiceSequence()
        try:
            saved_seq = decode_sequence(token)
        except:
            db.remove_file(entry.filename.copy())
            continue
        if len(saved_seq) > settings.max_choices:
            db.remove_file(entry.filename.copy())
            continue
        var tc = TestCase.replaying(saved_seq.copy(), settings.max_choices)
        var raised = False
        var message = String("")
        replays_run += 1
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        if not raised:
            db.remove_file(entry.filename.copy())
            continue
        if message == ASSUME_INTERRUPT or message == OVERRUN_INTERRUPT:
            db.remove_file(entry.filename.copy())
            continue
        if not _shrink_and_raise(
            prop,
            settings,
            seed,
            replays_run,
            tc.choices.copy(),
            message,
            db,
            entry.filename.copy(),
        ):
            continue
    return replays_run


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
    entry_file: String = "",
) raises -> Bool:
    """Shrink `failing`, persist the best replay, and raise the report.

    Shared by the database-replay and generation paths so both persist
    to the example database and report identically. Re-verifies that the
    reported replay is INTERESTING before saving or reporting; if a flaky
    failure disappears, prunes any stale database entry and returns False.
    """

    def evaluate(
        candidate: ChoiceSequence,
    ) raises {imm prop, imm settings} -> Evaluation:
        var tc = TestCase.replaying(candidate.copy(), settings.max_choices)
        var raised = False
        var message = String("")
        try:
            prop(tc)
        except e:
            raised = True
            message = String(e)
        var is_failure = (
            raised
            and message != ASSUME_INTERRUPT
            and message != OVERRUN_INTERRUPT
        )
        return Evaluation(is_failure, tc.choices.copy())

    var shrink_result = shrink_with(
        evaluate, failing.copy(), settings.max_shrink_evaluations
    )
    var report_tc = TestCase.replaying(
        shrink_result.best.copy(), settings.max_choices
    )
    var report_raised = False
    var replay_message = failure_message.copy()
    try:
        prop(report_tc)
    except e:
        report_raised = True
        replay_message = String(e)

    var report_failed = (
        report_raised
        and replay_message != ASSUME_INTERRUPT
        and replay_message != OVERRUN_INTERRUPT
    )

    if not report_failed:
        report_tc = TestCase.replaying(failing.copy(), settings.max_choices)
        report_raised = False
        replay_message = failure_message.copy()
        try:
            prop(report_tc)
        except e:
            report_raised = True
            replay_message = String(e)
        report_failed = (
            report_raised
            and replay_message != ASSUME_INTERRUPT
            and replay_message != OVERRUN_INTERRUPT
        )

    if not report_failed:
        if entry_file.byte_length() > 0:
            db.remove_file(entry_file.copy())
        return False

    var replay_token = encode_sequence(report_tc.choices.copy())
    if entry_file.byte_length() > 0 and entry_file != sha256_hex(replay_token):
        db.remove_file(entry_file.copy())
    db.save(replay_token)
    raise Error(
        _format_report(
            examples_run,
            shrink_result.evaluations,
            report_tc.draw_labels.copy(),
            report_tc.draw_values.copy(),
            report_tc.notes.copy(),
            replay_message^,
            Optional[UInt64](seed),
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
    """Attempt zero replays the empty prefix; later attempts drive generation.

    `attempt` doubles as the example index so `TestCase.size_scale`
    ramps collection lengths; replay paths ignore it.
    """
    if attempt == UInt64(0):
        return TestCase.replaying(ChoiceSequence(), max_choices, attempt)
    return TestCase.generating(derive(seed, attempt), max_choices, attempt)


def _mutated_test_case(
    best: ChoiceSequence,
    seed: UInt64,
    attempt: UInt64,
    max_choices: Int,
) raises -> TestCase:
    """Replay a targeted mutant of `best`, falling back when not mutable."""
    if len(best) == 0:
        return _fresh_test_case(max_choices, seed, attempt)
    var prng = derive(seed, attempt)
    var mutated = _mutate_target_sequence(best, prng^)
    return TestCase.replaying(mutated^, max_choices, attempt)


def _mutate_target_sequence(
    best: ChoiceSequence, var prng: Xoshiro256StarStar
) raises -> ChoiceSequence:
    """Copy `best` with mutable choices uniformly re-rolled.

    Each non-forced choice with `max_value > 0` is re-rolled with
    probability `TARGET_MUTATION_PROBABILITY`. One such choice is
    picked up front and re-rolled unconditionally so mutants explore
    even when no coin lands. Forced and zero-range choices are
    preserved.
    """
    var mutable_indices = List[Int]()
    for i in range(len(best)):
        var node = best[i]
        if not node.forced and node.max_value != UInt64(0):
            mutable_indices.append(i)
    var mandatory_idx = -1
    if len(mutable_indices) > 0:
        mandatory_idx = mutable_indices[
            Int(prng.next_below(UInt64(len(mutable_indices))))
        ]
    var out = ChoiceSequence()
    for i in range(len(best)):
        var node = best[i]
        if node.forced or node.max_value == UInt64(0):
            out.append(node^)
            continue
        var mutate = (i == mandatory_idx) or (
            prng.next_float64() < TARGET_MUTATION_PROBABILITY
        )
        if mutate:
            node.value = prng.next_at_most(node.max_value)
        out.append(node^)
    return out^


def _draw_label(labels: List[String], i: Int) -> String:
    """`labels[i]` with the `draw #i+1` fallback for an empty entry."""
    var label = String(labels[i])
    if label.byte_length() == 0:
        label = "draw #" + String(i + 1)
    return label^


def _format_example_line(
    index: Int,
    status: Status,
    labels: List[String],
    values: List[String],
) -> String:
    """Render one generation-loop execution for `VERBOSE` output."""
    var out = String("example ") + String(index) + ": " + String(status)
    if len(labels) > 0:
        out += " ("
        for i in range(len(labels)):
            if i > 0:
                out += ", "
            out += _draw_label(labels, i)
            out += " = "
            out += values[i]
        out += ")"
    return out^


def _health_check_message(
    examples_run: Int,
    bad_count: Int,
    valid_count: Int,
    reason: String,
    rate_label: String,
    strict_diagnosis: String,
) -> String:
    """Shared skeleton for health-check failure messages.

    With no valid execution at all, the diagnosis is the inability to
    generate a satisfying input rather than mere strictness.
    """
    var rate = 0
    if examples_run > 0:
        rate = bad_count * 100 // examples_run
    var out = String("gave up after ") + String(examples_run) + " examples"
    if valid_count == 0:
        out += " without a single valid execution"
    out += " (" + String(bad_count) + " " + reason + ", "
    out += String(rate) + "% " + rate_label + " rate)"
    if valid_count == 0:
        out += ": unable to generate input satisfying the condition"
    else:
        out += ": " + strict_diagnosis
    return out^


def _too_many_rejects_message(
    examples_run: Int, invalid_count: Int, valid_count: Int
) -> String:
    """Health-check failure naming the rejection rate."""
    return _health_check_message(
        examples_run,
        invalid_count,
        valid_count,
        "rejected by assume/filter",
        "rejection",
        "assume/filter condition too strict",
    )


def _too_many_overruns_message(
    examples_run: Int, overrun_count: Int, valid_count: Int, max_choices: Int
) -> String:
    """Health-check failure for runs exceeding the choice budget."""
    return _health_check_message(
        examples_run,
        overrun_count,
        valid_count,
        "overran max_choices=" + String(max_choices),
        "overrun",
        "generated data too large",
    )


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
        out += "  "
        out += _draw_label(labels, i)
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
