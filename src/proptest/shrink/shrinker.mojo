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


def _fingerprints(values: List[UInt64]) -> (UInt64, UInt64):
    var first = UInt64(14695981039346656037)
    var second = UInt64(7809847782465536322)
    for value in values:
        first = (first ^ value) * UInt64(1099511628211)
        second = (second ^ (value + UInt64(0x9E3779B97F4A7C15))) * UInt64(
            14029467366897019727
        )
    return (first, second)


def _lookup(entries: List[_CacheEntry], values: List[UInt64]) -> Int:
    var (fingerprint, secondary_fingerprint) = _fingerprints(values)
    for i in range(len(entries)):
        if (
            entries[i].fingerprint == fingerprint
            and entries[i].secondary_fingerprint == secondary_fingerprint
            and entries[i].length == len(values)
        ):
            return i
    return -1


# Candidates are materialized in fixed-size batches rather than up to
# the whole remaining budget: each candidate copies the entire sequence, so
# the default 5,000-evaluation budget would retain tens of millions of
# `ChoiceNode`s before the first one is evaluated.
comptime CANDIDATE_BATCH = 64


def _page_size(remaining: Int) -> Int:
    """Candidates to materialize in one page, capped by what is left."""
    if remaining < CANDIDATE_BATCH:
        return remaining
    return CANDIDATE_BATCH


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

        # Candidates are materialized one bounded batch at a time. The
        # batch is refetched when it held only cache hits: those cost no
        # evaluation, so they must not count against the budget or hide a
        # later candidate that would have been adopted.
        var fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            # Only the next page is materialized. The enumeration is
            # deterministic, so skipping `fetched` already-consumed
            # candidates costs no copies, and a cumulative `limit` would
            # rebuild an ever-growing prefix: at the default 5,000
            # evaluation budget that means ~5,000 whole-sequence copies
            # alive at once for a near-maximal example.
            var page = _page_size(max_evaluations - evaluations)
            var removals = delete_chunks(best.copy(), page, fetched)
            var index = 0
            while index < len(removals):
                var cand = removals[index].copy()
                index += 1
                fetched += 1
                var key = cand.values()
                if _lookup(entries, key) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cached_consumed = ChoiceSequence()
                if interesting:
                    cached_consumed = consumed.copy()
                var (fingerprint, secondary_fingerprint) = _fingerprints(key)
                entries.append(
                    _CacheEntry(
                        fingerprint,
                        secondary_fingerprint,
                        len(key),
                        interesting,
                        cached_consumed^
                    )
                )
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

        var zeroed_count = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            # Only the next page is materialized. The enumeration is
            # deterministic, so skipping `zeroed_count` already-consumed
            # candidates costs no copies, and a cumulative `limit` would
            # rebuild an ever-growing prefix: at the default 5,000
            # evaluation budget that means ~5,000 whole-sequence copies
            # alive at once for a near-maximal example.
            var page = _page_size(max_evaluations - evaluations)
            var zeroings = zero_chunks(best.copy(), page, zeroed_count)
            var index = 0
            while index < len(zeroings):
                var cand = zeroings[index].copy()
                index += 1
                zeroed_count += 1
                var key = cand.values()
                if _lookup(entries, key) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cached_consumed = ChoiceSequence()
                if interesting:
                    cached_consumed = consumed.copy()
                var (fingerprint, secondary_fingerprint) = _fingerprints(key)
                entries.append(
                    _CacheEntry(
                        fingerprint,
                        secondary_fingerprint,
                        len(key),
                        interesting,
                        cached_consumed^
                    )
                )
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
            var key = trial.values()
            var idx = _lookup(entries, key)
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
                var cached_consumed = ChoiceSequence()
                if zero_interesting:
                    cached_consumed = zero_consumed.copy()
                var (fingerprint, secondary_fingerprint) = _fingerprints(key)
                entries.append(
                    _CacheEntry(
                        fingerprint,
                        secondary_fingerprint,
                        len(key),
                        zero_interesting,
                        cached_consumed^
                    )
                )
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
                var pkey = probe.values()
                var pidx = _lookup(entries, pkey)
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
                    var cached_consumed = ChoiceSequence()
                    if p_interesting:
                        cached_consumed = p_consumed.copy()
                    var (fingerprint, secondary_fingerprint) = _fingerprints(pkey)
                    entries.append(
                        _CacheEntry(
                            fingerprint,
                            secondary_fingerprint,
                            len(pkey),
                            p_interesting,
                            cached_consumed^
                        )
                    )
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
