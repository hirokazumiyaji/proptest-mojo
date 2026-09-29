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
    var values: List[UInt64]
    var is_interesting: Bool
    var consumed: ChoiceSequence


def _values_equal(a: List[UInt64], b: List[UInt64]) -> Bool:
    if len(a) != len(b):
        return False
    for i in range(len(a)):
        if a[i] != b[i]:
            return False
    return True


def _lookup(entries: List[_CacheEntry], values: List[UInt64]) -> Int:
    for i in range(len(entries)):
        if _values_equal(entries[i].values, values):
            return i
    return -1


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
    entries.append(_CacheEntry(best.values(), False, best.copy()))
    var evaluations = 0
    var hit_budget = False

    while True:
        var improved = False

        var removals = delete_chunks(best.copy())
        for j in range(len(removals)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = removals[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            entries.append(_CacheEntry(key^, interesting, consumed.copy()))
            if interesting:
                best = consumed^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var zeroings = zero_chunks(best.copy())
        for j in range(len(zeroings)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = zeroings[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            entries.append(_CacheEntry(key^, interesting, consumed.copy()))
            if interesting:
                best = consumed^
                improved = True
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
                entries.append(
                    _CacheEntry(key^, zero_interesting, zero_consumed.copy())
                )
            if zero_interesting:
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
                var mid = (lo + hi) // UInt64(2)
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
                    entries.append(
                        _CacheEntry(pkey^, p_interesting, p_consumed.copy())
                    )
                if p_interesting:
                    hi = mid
                    best = p_consumed^
                    changed = True
                else:
                    lo = mid
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
