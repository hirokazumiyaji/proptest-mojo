"""Shrink loop: fixed-point application of passes with cache and budget.

Per `docs/specs/shrinking.md`, candidates are evaluated by the runner
(injected here as a comptime thin function). The loop adopts the
actually-consumed choices, caches by value column, and stops at a
fixed point or when `max_evaluations` is reached.
"""

from std.io import Writer

from proptest.choice import ChoiceSequence, is_shortlex_smaller
from proptest.shrink.passes import delete_chunks, zero_chunks


@fieldwise_init
struct Evaluation(Copyable, Movable, Writable):
    """Outcome of running one candidate sequence."""

    var is_interesting: Bool
    var consumed: ChoiceSequence

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Evaluation(interesting=", self.is_interesting, ", ")
        writer.write(self.consumed)
        writer.write(")")


@fieldwise_init
struct ShrinkResult(Copyable, Movable, Writable):
    """Best sequence found plus loop accounting."""

    var best: ChoiceSequence
    var evaluations: Int
    var hit_budget: Bool

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "ShrinkResult(",
            self.best,
            ", evaluations=",
            self.evaluations,
            ", hit_budget=",
            self.hit_budget,
            ")",
        )


@fieldwise_init
struct _CacheEntry(Copyable, Movable):
    var fingerprint: UInt64
    var secondary_fingerprint: UInt64
    var length: Int
    var is_interesting: Bool
    var consumed: ChoiceSequence


# Candidates are materialized in fixed-size batches rather than up to
# the whole remaining budget: each candidate copies the entire sequence, so
# the default 5,000-evaluation budget would retain tens of millions of
# `ChoiceNode`s before the first one is evaluated.
comptime CANDIDATE_BATCH = 64


def _batch_size(remaining: Int) -> Int:
    """Candidates to materialize at once, capped by what is left."""
    if remaining < CANDIDATE_BATCH:
        return remaining
    return CANDIDATE_BATCH


def _fingerprints(sequence: ChoiceSequence) -> (UInt64, UInt64):
    var first = UInt64(14695981039346656037)
    var second = UInt64(7809847782465536322)
    for i in range(len(sequence)):
        var node = sequence.nodes[i]
        var forced = UInt64(0)
        if node.forced:
            forced = UInt64(1)
        first = (first ^ UInt64(node.kind.value)) * UInt64(1099511628211)
        first = (first ^ node.value) * UInt64(1099511628211)
        first = (first ^ node.max_value) * UInt64(1099511628211)
        first = (first ^ forced) * UInt64(1099511628211)
        second = (second ^ UInt64(node.kind.value)) * UInt64(14029467366897019727)
        second = (second ^ node.value) * UInt64(14029467366897019727)
        second = (second ^ node.max_value) * UInt64(14029467366897019727)
        second = (second ^ forced) * UInt64(14029467366897019727)
    return (first, second)


def _lookup(entries: List[_CacheEntry], sequence: ChoiceSequence) -> Int:
    var (fingerprint, secondary_fingerprint) = _fingerprints(sequence)
    for i in range(len(entries)):
        if (
            entries[i].fingerprint == fingerprint
            and entries[i].secondary_fingerprint == secondary_fingerprint
            and entries[i].length == len(sequence)
        ):
            return i
    return -1


def _append_cache_entry(
    mut entries: List[_CacheEntry],
    sequence: ChoiceSequence,
    is_interesting: Bool,
    consumed: ChoiceSequence,
):
    var (fingerprint, secondary_fingerprint) = _fingerprints(sequence)
    var cached_consumed = ChoiceSequence()
    if is_interesting:
        cached_consumed = consumed.copy()
    entries.append(
        _CacheEntry(
            fingerprint,
            secondary_fingerprint,
            len(sequence),
            is_interesting,
            cached_consumed^
        )
    )


def shrink[
    evaluate: def(ChoiceSequence) thin -> Evaluation
](initial: ChoiceSequence, max_evaluations: Int) -> ShrinkResult:
    """Apply passes to a fixed point, caching evaluations.

    `evaluate` runs one candidate in replay mode and reports whether it
    is interesting plus the actually-consumed prefix, which is what gets
    adopted. A zero budget returns the input unchanged.
    """
    var best = initial.copy()
    if max_evaluations <= 0:
        return ShrinkResult(best^, 0, False)

    var entries = List[_CacheEntry]()
    var evaluations = 0
    var hit_budget = False

    while True:
        var improved = False

        # Cache hits cost no evaluation, so they must not consume the
        # materialization cap: refetch with a larger limit when the batch
        # held only hits, otherwise a cached prefix hides later uncached
        # candidates and the run reports a fixed point with budget
        # remaining.
        var fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _batch_size(max_evaluations - evaluations)
            var removals = delete_chunks(best.copy(), page, fetched)
            var index = 0
            while index < len(removals):
                var cand = removals[index].copy()
                index += 1
                fetched += 1
                if _lookup(entries, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                _append_cache_entry(entries, cand, interesting, consumed)
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(removals) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # Cache hits cost no evaluation, so they must not consume the
        # materialization cap: refetch with a larger limit when the batch
        # held only hits, otherwise a cached prefix hides later uncached
        # candidates and the run reports a fixed point with budget
        # remaining.
        var zeroed_count = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _batch_size(max_evaluations - evaluations)
            var zeroings = zero_chunks(best.copy(), page, zeroed_count)
            var index = 0
            while index < len(zeroings):
                var cand = zeroings[index].copy()
                index += 1
                zeroed_count += 1
                if _lookup(entries, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                _append_cache_entry(entries, cand, interesting, consumed)
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(zeroings) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        var n = len(best)
        for i in range(n):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            if best.nodes[i].forced:
                continue
            if best.nodes[i].value == UInt64(0):
                continue
            var current = best.nodes[i].value
            var trial = best.with_value_at(i, UInt64(0))
            var idx = _lookup(entries, trial)
            var zero_interesting = False
            var zero_consumed = trial.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
            else:
                evaluations += 1
                var result = evaluate(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                _append_cache_entry(entries, trial, zero_interesting, zero_consumed)
            if zero_interesting and is_shortlex_smaller(zero_consumed, best):
                best = zero_consumed^
                improved = True
                break
            var lo = UInt64(0)
            var hi = current
            var changed = False
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.with_value_at(i, mid)
                var pidx = _lookup(entries, probe)
                var p_interesting = False
                var p_consumed = probe.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                else:
                    evaluations += 1
                    var presult = evaluate(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    _append_cache_entry(entries, probe, p_interesting, p_consumed)
                if p_interesting and is_shortlex_smaller(p_consumed, best):
                    hi = mid
                    best = p_consumed^
                    changed = True
                elif not p_interesting:
                    lo = mid
                else:
                    # Interesting but not smaller: the property drew
                    # extra choices, so this probe is unusable and the
                    # interval is exhausted rather than narrowed.
                    break
            if hit_budget:
                break
            if changed:
                improved = True
                break
        if hit_budget:
            break
        if not improved:
            break

    return ShrinkResult(best^, evaluations, hit_budget)


def shrink_with[
    E: def(ChoiceSequence) raises -> Evaluation
](
    eval_fn: E, initial: ChoiceSequence, max_evaluations: Int
) raises -> ShrinkResult:
    """Same loop as `shrink`, with a runtime closure as the evaluator.

    `shrink` takes a comptime thin function, which cannot capture the
    property under test. The runner replays candidates through a
    capturing closure, so it needs this variant. The two loops are
    intentionally identical; a comptime thin parameter cannot be
    forwarded to a runtime generic, so they cannot share one body until
    the compiler allows it.
    """
    var best = initial.copy()
    if max_evaluations <= 0:
        return ShrinkResult(best^, 0, False)

    var entries = List[_CacheEntry]()
    var evaluations = 0
    var hit_budget = False

    while True:
        var improved = False

        # Cache hits cost no evaluation, so they must not consume the
        # materialization cap: refetch with a larger limit when the batch
        # held only hits, otherwise a cached prefix hides later uncached
        # candidates and the run reports a fixed point with budget
        # remaining.
        var fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _batch_size(max_evaluations - evaluations)
            var removals = delete_chunks(best.copy(), page, fetched)
            var index = 0
            while index < len(removals):
                var cand = removals[index].copy()
                index += 1
                fetched += 1
                if _lookup(entries, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                _append_cache_entry(entries, cand, interesting, consumed)
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(removals) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # Cache hits cost no evaluation, so they must not consume the
        # materialization cap: refetch with a larger limit when the batch
        # held only hits, otherwise a cached prefix hides later uncached
        # candidates and the run reports a fixed point with budget
        # remaining.
        var zeroed_count = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _batch_size(max_evaluations - evaluations)
            var zeroings = zero_chunks(best.copy(), page, zeroed_count)
            var index = 0
            while index < len(zeroings):
                var cand = zeroings[index].copy()
                index += 1
                zeroed_count += 1
                if _lookup(entries, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                _append_cache_entry(entries, cand, interesting, consumed)
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(zeroings) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        var n = len(best)
        for i in range(n):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            if best.nodes[i].forced:
                continue
            if best.nodes[i].value == UInt64(0):
                continue
            var current = best.nodes[i].value
            var trial = best.with_value_at(i, UInt64(0))
            var idx = _lookup(entries, trial)
            var zero_interesting = False
            var zero_consumed = trial.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
            else:
                evaluations += 1
                var result = eval_fn(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                _append_cache_entry(entries, trial, zero_interesting, zero_consumed)
            if zero_interesting and is_shortlex_smaller(zero_consumed, best):
                best = zero_consumed^
                improved = True
                break
            var lo = UInt64(0)
            var hi = current
            var changed = False
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.with_value_at(i, mid)
                var pidx = _lookup(entries, probe)
                var p_interesting = False
                var p_consumed = probe.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                else:
                    evaluations += 1
                    var presult = eval_fn(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    _append_cache_entry(entries, probe, p_interesting, p_consumed)
                if p_interesting and is_shortlex_smaller(p_consumed, best):
                    hi = mid
                    best = p_consumed^
                    changed = True
                elif not p_interesting:
                    lo = mid
                else:
                    # Interesting but not smaller: the property drew
                    # extra choices, so this probe is unusable and the
                    # interval is exhausted rather than narrowed.
                    break
            if hit_budget:
                break
            if changed:
                improved = True
                break
        if hit_budget:
            break
        if not improved:
            break

    return ShrinkResult(best^, evaluations, hit_budget)
