"""Shrink loop: fixed-point application of passes with cache and budget.

Per `docs/specs/shrinking.md`, candidates are evaluated by the runner
(injected here as a comptime thin function). The loop adopts the
actually-consumed choices, caches by value column, and stops at a
fixed point or when `max_evaluations` is reached.

Phases run in spec order, restarting from the top after any adoption:
`delete_chunks`, `zero_chunks`, `minimize_individual`, `delete_spans`,
`zero_spans`, `sort_spans`, `swap_adjacent_spans`, `redistribute`,
`lower_duplicates`.
"""

from std.io import Writer

from proptest.choice import ChoiceKind, ChoiceSequence, Span
from proptest.shrink.passes import delete_chunks, zero_chunks
from proptest.shrink.span_passes import (
    delete_spans,
    sort_spans,
    swap_adjacent_spans,
    zero_spans,
)


@fieldwise_init
struct Evaluation(Copyable, Movable, Writable):
    """Outcome of running one candidate sequence."""

    var is_interesting: Bool
    var consumed: ChoiceSequence
    var spans: List[Span]

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
    var spans: List[Span]


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
](
    initial: ChoiceSequence, initial_spans: List[Span], max_evaluations: Int
) -> ShrinkResult:
    """Apply passes to a fixed point, caching evaluations.

    `evaluate` runs one candidate in replay mode and reports whether it
    is interesting plus the actually-consumed prefix, which is what gets
    adopted. `initial_spans` are the spans recorded alongside `initial`;
    every adoption refreshes them from the evaluation result, so later
    span passes always see current structure. A zero budget returns the
    input unchanged.
    """
    var best = initial.copy()
    var best_spans = initial_spans.copy()
    if max_evaluations <= 0:
        return ShrinkResult(best^, 0, False)

    var entries = List[_CacheEntry]()
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
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
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
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
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
            var zero_spans = best_spans.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
                zero_spans = entries[idx].spans.copy()
            else:
                evaluations += 1
                var result = evaluate(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                zero_spans = result.spans.copy()
                entries.append(
                    _CacheEntry(
                        key^,
                        zero_interesting,
                        zero_consumed.copy(),
                        zero_spans.copy(),
                    )
                )
            if zero_interesting:
                best = zero_consumed^
                best_spans = zero_spans^
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
                var p_spans = best_spans.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    evaluations += 1
                    var presult = evaluate(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    p_spans = presult.spans.copy()
                    entries.append(
                        _CacheEntry(
                            pkey^,
                            p_interesting,
                            p_consumed.copy(),
                            p_spans.copy(),
                        )
                    )
                if p_interesting:
                    hi = mid
                    best = p_consumed^
                    best_spans = p_spans^
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
        if improved:
            continue

        var span_removals = delete_spans(best.copy(), best_spans.copy())
        for j in range(len(span_removals)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_removals[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_zeroings = zero_spans(best.copy(), best_spans.copy())
        for j in range(len(span_zeroings)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_zeroings[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_sorts = sort_spans(best.copy(), best_spans.copy())
        for j in range(len(span_sorts)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_sorts[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_swaps = swap_adjacent_spans(best.copy(), best_spans.copy())
        for j in range(len(span_swaps)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_swaps[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var n_red = len(best)
        for i in range(n_red):
            if hit_budget:
                break
            if improved:
                break
            if best.nodes[i].forced:
                continue
            if best.nodes[i].kind != ChoiceKind.INTEGER:
                continue
            for j in range(i + 1, len(best)):
                if best.nodes[j].forced:
                    continue
                if best.nodes[j].kind != ChoiceKind.INTEGER:
                    continue
                var a = best.nodes[i].value
                var max_j = best.nodes[j].max_value
                if a == UInt64(0):
                    continue
                if best.nodes[j].value >= max_j:
                    continue
                var base0 = best.with_value_at(i, UInt64(0))
                var probe0max = base0.with_value_at(j, max_j)
                var key0 = probe0max.values()
                var idx0 = _lookup(entries, key0)
                if idx0 < 0:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var result = evaluate(probe0max^)
                    idx0 = len(entries)
                    entries.append(
                        _CacheEntry(
                            key0^,
                            result.is_interesting,
                            result.consumed.copy(),
                            result.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                if entries[idx0].is_interesting:
                    var base0z = best.with_value_at(i, UInt64(0))
                    var probe0z = base0z.with_value_at(j, UInt64(0))
                    var key0z = probe0z.values()
                    var idx0z = _lookup(entries, key0z)
                    if idx0z < 0:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var result = evaluate(probe0z^)
                        idx0z = len(entries)
                        entries.append(
                            _CacheEntry(
                                key0z^,
                                result.is_interesting,
                                result.consumed.copy(),
                                result.spans.copy(),
                            )
                        )
                    if hit_budget:
                        break
                    var jstar: UInt64
                    if entries[idx0z].is_interesting:
                        jstar = UInt64(0)
                    else:
                        var lo = UInt64(0)
                        var hi = max_j
                        while hi - lo > UInt64(1):
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            var mid = lo + (hi - lo) // UInt64(2)
                            var tm = best.with_value_at(i, UInt64(0))
                            var pr = tm.with_value_at(j, mid)
                            var pkey = pr.values()
                            var pidx = _lookup(entries, pkey)
                            if pidx < 0:
                                evaluations += 1
                                var presult = evaluate(pr^)
                                pidx = len(entries)
                                entries.append(
                                    _CacheEntry(
                                        pkey^,
                                        presult.is_interesting,
                                        presult.consumed.copy(),
                                        presult.spans.copy(),
                                    )
                                )
                            if hit_budget:
                                break
                            if entries[pidx].is_interesting:
                                hi = mid
                            else:
                                lo = mid
                        if hit_budget:
                            break
                        jstar = hi
                    var fin0 = best.with_value_at(i, UInt64(0))
                    var fincand = fin0.with_value_at(j, jstar)
                    var fkey = fincand.values()
                    var fidx = _lookup(entries, fkey)
                    if fidx < 0:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var result = evaluate(fincand^)
                        fidx = len(entries)
                        entries.append(
                            _CacheEntry(
                                fkey^,
                                result.is_interesting,
                                result.consumed.copy(),
                                result.spans.copy(),
                            )
                        )
                    if hit_budget:
                        break
                    best = entries[fidx].consumed.copy()
                    best_spans = entries[fidx].spans.copy()
                    improved = True
                    break
                else:
                    var lo = UInt64(0)
                    var hi = a
                    while hi - lo > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid = lo + (hi - lo) // UInt64(2)
                        var tm = best.with_value_at(i, mid)
                        var pr = tm.with_value_at(j, max_j)
                        var pkey = pr.values()
                        var pidx = _lookup(entries, pkey)
                        if pidx < 0:
                            evaluations += 1
                            var presult = evaluate(pr^)
                            pidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    pkey^,
                                    presult.is_interesting,
                                    presult.consumed.copy(),
                                    presult.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        if entries[pidx].is_interesting:
                            hi = mid
                        else:
                            lo = mid
                    if hit_budget:
                        break
                    if hi < a:
                        var thiz = best.with_value_at(i, hi)
                        var probez = thiz.with_value_at(j, UInt64(0))
                        var zkey = probez.values()
                        var zidx = _lookup(entries, zkey)
                        if zidx < 0:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var result = evaluate(probez^)
                            zidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    zkey^,
                                    result.is_interesting,
                                    result.consumed.copy(),
                                    result.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        var jstar: UInt64
                        if entries[zidx].is_interesting:
                            jstar = UInt64(0)
                        else:
                            var lo2 = UInt64(0)
                            var hi2 = max_j
                            while hi2 - lo2 > UInt64(1):
                                if evaluations >= max_evaluations:
                                    hit_budget = True
                                    break
                                var mid2 = lo2 + (hi2 - lo2) // UInt64(2)
                                var tm2 = best.with_value_at(i, hi)
                                var pr2 = tm2.with_value_at(j, mid2)
                                var pkey2 = pr2.values()
                                var pidx2 = _lookup(entries, pkey2)
                                if pidx2 < 0:
                                    evaluations += 1
                                    var presult = evaluate(pr2^)
                                    pidx2 = len(entries)
                                    entries.append(
                                        _CacheEntry(
                                            pkey2^,
                                            presult.is_interesting,
                                            presult.consumed.copy(),
                                            presult.spans.copy(),
                                        )
                                    )
                                if hit_budget:
                                    break
                                if entries[pidx2].is_interesting:
                                    hi2 = mid2
                                else:
                                    lo2 = mid2
                            if hit_budget:
                                break
                            jstar = hi2
                        var th = best.with_value_at(i, hi)
                        var candh = th.with_value_at(j, jstar)
                        var hkey = candh.values()
                        var hidx = _lookup(entries, hkey)
                        if hidx < 0:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var result = evaluate(candh^)
                            hidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    hkey^,
                                    result.is_interesting,
                                    result.consumed.copy(),
                                    result.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        best = entries[hidx].consumed.copy()
                        best_spans = entries[hidx].spans.copy()
                        improved = True
                        break
            if hit_budget:
                break
        if hit_budget:
            break
        if improved:
            continue

        var seen = List[UInt64]()
        var n_dup = len(best)
        for i in range(n_dup):
            if hit_budget:
                break
            if improved:
                break
            if best.nodes[i].forced:
                continue
            var v = best.nodes[i].value
            if v == UInt64(0):
                continue
            var already = False
            for k in range(len(seen)):
                if seen[k] == v:
                    already = True
                    break
            if already:
                continue
            var group = List[Int]()
            for k in range(len(best)):
                if best.nodes[k].forced:
                    continue
                if best.nodes[k].value == v:
                    group.append(k)
            seen.append(v)
            if len(group) < 2:
                continue
            var cand0 = best.copy()
            for g in range(len(group)):
                cand0 = cand0.with_value_at(group[g], UInt64(0))
            var key0 = cand0.values()
            var idx0 = _lookup(entries, key0)
            if idx0 < 0:
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                evaluations += 1
                var result = evaluate(cand0^)
                idx0 = len(entries)
                entries.append(
                    _CacheEntry(
                        key0^,
                        result.is_interesting,
                        result.consumed.copy(),
                        result.spans.copy(),
                    )
                )
            if hit_budget:
                break
            if entries[idx0].is_interesting:
                best = entries[idx0].consumed.copy()
                best_spans = entries[idx0].spans.copy()
                improved = True
                break
            var lo = UInt64(0)
            var hi = v
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.copy()
                for g in range(len(group)):
                    probe = probe.with_value_at(group[g], mid)
                var pkey = probe.values()
                var pidx = _lookup(entries, pkey)
                if pidx < 0:
                    evaluations += 1
                    var presult = evaluate(probe^)
                    pidx = len(entries)
                    entries.append(
                        _CacheEntry(
                            pkey^,
                            presult.is_interesting,
                            presult.consumed.copy(),
                            presult.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                if entries[pidx].is_interesting:
                    hi = mid
                else:
                    lo = mid
            if hit_budget:
                break
            if hi < v:
                var candh = best.copy()
                for g in range(len(group)):
                    candh = candh.with_value_at(group[g], hi)
                var hkey = candh.values()
                var hidx = _lookup(entries, hkey)
                if hidx < 0:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var result = evaluate(candh^)
                    hidx = len(entries)
                    entries.append(
                        _CacheEntry(
                            hkey^,
                            result.is_interesting,
                            result.consumed.copy(),
                            result.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                best = entries[hidx].consumed.copy()
                best_spans = entries[hidx].spans.copy()
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
    eval_fn: E,
    initial: ChoiceSequence,
    initial_spans: List[Span],
    max_evaluations: Int,
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
    var best_spans = initial_spans.copy()
    if max_evaluations <= 0:
        return ShrinkResult(best^, 0, False)

    var entries = List[_CacheEntry]()
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
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
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
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
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
            var zero_spans = best_spans.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
                zero_spans = entries[idx].spans.copy()
            else:
                evaluations += 1
                var result = eval_fn(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                zero_spans = result.spans.copy()
                entries.append(
                    _CacheEntry(
                        key^,
                        zero_interesting,
                        zero_consumed.copy(),
                        zero_spans.copy(),
                    )
                )
            if zero_interesting:
                best = zero_consumed^
                best_spans = zero_spans^
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
                var p_spans = best_spans.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    evaluations += 1
                    var presult = eval_fn(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    p_spans = presult.spans.copy()
                    entries.append(
                        _CacheEntry(
                            pkey^,
                            p_interesting,
                            p_consumed.copy(),
                            p_spans.copy(),
                        )
                    )
                if p_interesting:
                    hi = mid
                    best = p_consumed^
                    best_spans = p_spans^
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
        if improved:
            continue

        var span_removals = delete_spans(best.copy(), best_spans.copy())
        for j in range(len(span_removals)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_removals[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_zeroings = zero_spans(best.copy(), best_spans.copy())
        for j in range(len(span_zeroings)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_zeroings[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_sorts = sort_spans(best.copy(), best_spans.copy())
        for j in range(len(span_sorts)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_sorts[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var span_swaps = swap_adjacent_spans(best.copy(), best_spans.copy())
        for j in range(len(span_swaps)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_swaps[j].copy()
            var key = cand.values()
            if _lookup(entries, key) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            entries.append(
                _CacheEntry(key^, interesting, consumed.copy(), cspans.copy())
            )
            if interesting:
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        var n_red = len(best)
        for i in range(n_red):
            if hit_budget:
                break
            if improved:
                break
            if best.nodes[i].forced:
                continue
            if best.nodes[i].kind != ChoiceKind.INTEGER:
                continue
            for j in range(i + 1, len(best)):
                if best.nodes[j].forced:
                    continue
                if best.nodes[j].kind != ChoiceKind.INTEGER:
                    continue
                var a = best.nodes[i].value
                var max_j = best.nodes[j].max_value
                if a == UInt64(0):
                    continue
                if best.nodes[j].value >= max_j:
                    continue
                var base0 = best.with_value_at(i, UInt64(0))
                var probe0max = base0.with_value_at(j, max_j)
                var key0 = probe0max.values()
                var idx0 = _lookup(entries, key0)
                if idx0 < 0:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var result = eval_fn(probe0max^)
                    idx0 = len(entries)
                    entries.append(
                        _CacheEntry(
                            key0^,
                            result.is_interesting,
                            result.consumed.copy(),
                            result.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                if entries[idx0].is_interesting:
                    var base0z = best.with_value_at(i, UInt64(0))
                    var probe0z = base0z.with_value_at(j, UInt64(0))
                    var key0z = probe0z.values()
                    var idx0z = _lookup(entries, key0z)
                    if idx0z < 0:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var result = eval_fn(probe0z^)
                        idx0z = len(entries)
                        entries.append(
                            _CacheEntry(
                                key0z^,
                                result.is_interesting,
                                result.consumed.copy(),
                                result.spans.copy(),
                            )
                        )
                    if hit_budget:
                        break
                    var jstar: UInt64
                    if entries[idx0z].is_interesting:
                        jstar = UInt64(0)
                    else:
                        var lo = UInt64(0)
                        var hi = max_j
                        while hi - lo > UInt64(1):
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            var mid = lo + (hi - lo) // UInt64(2)
                            var tm = best.with_value_at(i, UInt64(0))
                            var pr = tm.with_value_at(j, mid)
                            var pkey = pr.values()
                            var pidx = _lookup(entries, pkey)
                            if pidx < 0:
                                evaluations += 1
                                var presult = eval_fn(pr^)
                                pidx = len(entries)
                                entries.append(
                                    _CacheEntry(
                                        pkey^,
                                        presult.is_interesting,
                                        presult.consumed.copy(),
                                        presult.spans.copy(),
                                    )
                                )
                            if hit_budget:
                                break
                            if entries[pidx].is_interesting:
                                hi = mid
                            else:
                                lo = mid
                        if hit_budget:
                            break
                        jstar = hi
                    var fin0 = best.with_value_at(i, UInt64(0))
                    var fincand = fin0.with_value_at(j, jstar)
                    var fkey = fincand.values()
                    var fidx = _lookup(entries, fkey)
                    if fidx < 0:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var result = eval_fn(fincand^)
                        fidx = len(entries)
                        entries.append(
                            _CacheEntry(
                                fkey^,
                                result.is_interesting,
                                result.consumed.copy(),
                                result.spans.copy(),
                            )
                        )
                    if hit_budget:
                        break
                    best = entries[fidx].consumed.copy()
                    best_spans = entries[fidx].spans.copy()
                    improved = True
                    break
                else:
                    var lo = UInt64(0)
                    var hi = a
                    while hi - lo > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid = lo + (hi - lo) // UInt64(2)
                        var tm = best.with_value_at(i, mid)
                        var pr = tm.with_value_at(j, max_j)
                        var pkey = pr.values()
                        var pidx = _lookup(entries, pkey)
                        if pidx < 0:
                            evaluations += 1
                            var presult = eval_fn(pr^)
                            pidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    pkey^,
                                    presult.is_interesting,
                                    presult.consumed.copy(),
                                    presult.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        if entries[pidx].is_interesting:
                            hi = mid
                        else:
                            lo = mid
                    if hit_budget:
                        break
                    if hi < a:
                        var thiz = best.with_value_at(i, hi)
                        var probez = thiz.with_value_at(j, UInt64(0))
                        var zkey = probez.values()
                        var zidx = _lookup(entries, zkey)
                        if zidx < 0:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var result = eval_fn(probez^)
                            zidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    zkey^,
                                    result.is_interesting,
                                    result.consumed.copy(),
                                    result.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        var jstar: UInt64
                        if entries[zidx].is_interesting:
                            jstar = UInt64(0)
                        else:
                            var lo2 = UInt64(0)
                            var hi2 = max_j
                            while hi2 - lo2 > UInt64(1):
                                if evaluations >= max_evaluations:
                                    hit_budget = True
                                    break
                                var mid2 = lo2 + (hi2 - lo2) // UInt64(2)
                                var tm2 = best.with_value_at(i, hi)
                                var pr2 = tm2.with_value_at(j, mid2)
                                var pkey2 = pr2.values()
                                var pidx2 = _lookup(entries, pkey2)
                                if pidx2 < 0:
                                    evaluations += 1
                                    var presult = eval_fn(pr2^)
                                    pidx2 = len(entries)
                                    entries.append(
                                        _CacheEntry(
                                            pkey2^,
                                            presult.is_interesting,
                                            presult.consumed.copy(),
                                            presult.spans.copy(),
                                        )
                                    )
                                if hit_budget:
                                    break
                                if entries[pidx2].is_interesting:
                                    hi2 = mid2
                                else:
                                    lo2 = mid2
                            if hit_budget:
                                break
                            jstar = hi2
                        var th = best.with_value_at(i, hi)
                        var candh = th.with_value_at(j, jstar)
                        var hkey = candh.values()
                        var hidx = _lookup(entries, hkey)
                        if hidx < 0:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var result = eval_fn(candh^)
                            hidx = len(entries)
                            entries.append(
                                _CacheEntry(
                                    hkey^,
                                    result.is_interesting,
                                    result.consumed.copy(),
                                    result.spans.copy(),
                                )
                            )
                        if hit_budget:
                            break
                        best = entries[hidx].consumed.copy()
                        best_spans = entries[hidx].spans.copy()
                        improved = True
                        break
            if hit_budget:
                break
        if hit_budget:
            break
        if improved:
            continue

        var seen = List[UInt64]()
        var n_dup = len(best)
        for i in range(n_dup):
            if hit_budget:
                break
            if improved:
                break
            if best.nodes[i].forced:
                continue
            var v = best.nodes[i].value
            if v == UInt64(0):
                continue
            var already = False
            for k in range(len(seen)):
                if seen[k] == v:
                    already = True
                    break
            if already:
                continue
            var group = List[Int]()
            for k in range(len(best)):
                if best.nodes[k].forced:
                    continue
                if best.nodes[k].value == v:
                    group.append(k)
            seen.append(v)
            if len(group) < 2:
                continue
            var cand0 = best.copy()
            for g in range(len(group)):
                cand0 = cand0.with_value_at(group[g], UInt64(0))
            var key0 = cand0.values()
            var idx0 = _lookup(entries, key0)
            if idx0 < 0:
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                evaluations += 1
                var result = eval_fn(cand0^)
                idx0 = len(entries)
                entries.append(
                    _CacheEntry(
                        key0^,
                        result.is_interesting,
                        result.consumed.copy(),
                        result.spans.copy(),
                    )
                )
            if hit_budget:
                break
            if entries[idx0].is_interesting:
                best = entries[idx0].consumed.copy()
                best_spans = entries[idx0].spans.copy()
                improved = True
                break
            var lo = UInt64(0)
            var hi = v
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.copy()
                for g in range(len(group)):
                    probe = probe.with_value_at(group[g], mid)
                var pkey = probe.values()
                var pidx = _lookup(entries, pkey)
                if pidx < 0:
                    evaluations += 1
                    var presult = eval_fn(probe^)
                    pidx = len(entries)
                    entries.append(
                        _CacheEntry(
                            pkey^,
                            presult.is_interesting,
                            presult.consumed.copy(),
                            presult.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                if entries[pidx].is_interesting:
                    hi = mid
                else:
                    lo = mid
            if hit_budget:
                break
            if hi < v:
                var candh = best.copy()
                for g in range(len(group)):
                    candh = candh.with_value_at(group[g], hi)
                var hkey = candh.values()
                var hidx = _lookup(entries, hkey)
                if hidx < 0:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var result = eval_fn(candh^)
                    hidx = len(entries)
                    entries.append(
                        _CacheEntry(
                            hkey^,
                            result.is_interesting,
                            result.consumed.copy(),
                            result.spans.copy(),
                        )
                    )
                if hit_budget:
                    break
                best = entries[hidx].consumed.copy()
                best_spans = entries[hidx].spans.copy()
                improved = True
                break
        if hit_budget:
            break
        if not improved:
            break

    return ShrinkResult(best^, evaluations, hit_budget)
