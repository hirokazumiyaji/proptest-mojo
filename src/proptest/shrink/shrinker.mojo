"""Shrink loop: fixed-point application of passes with cache and budget.

Per `docs/specs/shrinking.md`, candidates are evaluated by the runner
(injected here as a comptime thin function). The loop adopts the
actually-consumed choices, caches by value column, and stops at a
fixed point or when `max_evaluations` is reached.
"""

from std.io import Writer

from proptest.choice import (
    ChoiceKind,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)
from proptest.shrink.passes import delete_chunks, zero_chunks
from proptest.shrink.span_passes import (
    delete_spans,
    sort_spans,
    swap_adjacent_spans,
    zero_spans,
)


def _clip_spans(spans: List[Span], max_len: Int) -> List[Span]:
    """Clip span bounds so all returned spans lie strictly within 0..max_len."""
    var out = List[Span]()
    for i in range(len(spans)):
        var s = spans[i].copy()
        if s.start < 0 or s.start >= max_len:
            continue
        var end = s.end
        if end > max_len:
            end = max_len
        if end <= s.start:
            continue
        out.append(Span(s.start, end, s.label, s.depth, s.discarded))
    return out^


struct Evaluation(Copyable, Movable, Writable):
    """Outcome of running one candidate sequence."""

    var is_interesting: Bool
    var consumed: ChoiceSequence
    var spans: List[Span]

    def __init__(
        out self,
        is_interesting: Bool,
        var consumed: ChoiceSequence,
    ):
        self.is_interesting = is_interesting
        self.consumed = consumed^
        self.spans = List[Span]()

    def __init__(
        out self,
        is_interesting: Bool,
        var consumed: ChoiceSequence,
        var spans: List[Span],
    ):
        self.is_interesting = is_interesting
        self.spans = _clip_spans(spans, len(consumed))
        self.consumed = consumed^

    def write_to(self, mut writer: Some[Writer]):
        writer.write("Evaluation(interesting=", self.is_interesting, ", ")
        writer.write(self.consumed)
        writer.write(")")


struct ShrinkResult(Copyable, Movable, Writable):
    """Best sequence found plus loop accounting."""

    var best: ChoiceSequence
    var spans: List[Span]
    var evaluations: Int
    var hit_budget: Bool

    def __init__(
        out self,
        var best: ChoiceSequence,
        evaluations: Int,
        hit_budget: Bool,
    ):
        self.best = best^
        self.spans = List[Span]()
        self.evaluations = evaluations
        self.hit_budget = hit_budget

    def __init__(
        out self,
        var best: ChoiceSequence,
        var spans: List[Span],
        evaluations: Int,
        hit_budget: Bool,
    ):
        self.best = best^
        self.spans = spans^
        self.evaluations = evaluations
        self.hit_budget = hit_budget

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
    var sequence: ChoiceSequence
    var fingerprint: UInt64
    var secondary_fingerprint: UInt64
    var length: Int
    var is_interesting: Bool
    var consumed: ChoiceSequence
    var spans: List[Span]


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


def _fingerprints(sequence: ChoiceSequence) -> Tuple[UInt64, UInt64]:
    var first = UInt64(14695981039346656037)
    var second = UInt64(7809847782465536322)
    for i in range(len(sequence)):
        var node = sequence.nodes[i].copy()
        var forced = UInt64(0)
        if node.forced:
            forced = UInt64(1)
        first = (first ^ UInt64(node.kind.value)) * UInt64(1099511628211)
        first = (first ^ node.value) * UInt64(1099511628211)
        first = (first ^ node.max_value) * UInt64(1099511628211)
        first = (first ^ forced) * UInt64(1099511628211)
        second = (second ^ UInt64(node.kind.value)) * UInt64(
            14029467366897019727
        )
        second = (second ^ node.value) * UInt64(14029467366897019727)
        second = (second ^ node.max_value) * UInt64(14029467366897019727)
        second = (second ^ forced) * UInt64(14029467366897019727)
    return (first, second)


def _cache_slot(
    fingerprint: UInt64,
    secondary_fingerprint: UInt64,
    length: Int,
    capacity: Int,
) -> Int:
    var key = fingerprint ^ secondary_fingerprint ^ UInt64(length)
    key = (key ^ (key >> 33)) * UInt64(0xFF51AFD7ED558CCD)
    key = (key ^ (key >> 33)) * UInt64(0xC4CEB9FE1A85EC53)
    key = key ^ (key >> 33)
    return Int(key % UInt64(capacity))


def _lookup(
    entries: List[_CacheEntry], slots: List[Int], sequence: ChoiceSequence
) -> Int:
    var (fingerprint, secondary_fingerprint) = _fingerprints(sequence)
    var slot = _cache_slot(
        fingerprint, secondary_fingerprint, len(sequence), len(slots)
    )
    while slots[slot] >= 0:
        var i = slots[slot]
        if (
            entries[i].fingerprint == fingerprint
            and entries[i].secondary_fingerprint == secondary_fingerprint
            and entries[i].length == len(sequence)
            and entries[i].sequence == sequence
        ):
            return i
        slot += 1
        if slot == len(slots):
            slot = 0
    return -1


def _append_cache_entry(
    mut entries: List[_CacheEntry],
    mut slots: List[Int],
    sequence: ChoiceSequence,
    is_interesting: Bool,
    consumed: ChoiceSequence,
    spans: List[Span],
):
    var (fingerprint, secondary_fingerprint) = _fingerprints(sequence)
    var cached_consumed = ChoiceSequence()
    var cached_spans = List[Span]()
    if is_interesting:
        cached_consumed = consumed.copy()
        cached_spans = _clip_spans(spans, len(consumed))
    entries.append(
        _CacheEntry(
            sequence.copy(),
            fingerprint,
            secondary_fingerprint,
            len(sequence),
            is_interesting,
            cached_consumed^,
            cached_spans^,
        )
    )
    var slot = _cache_slot(
        fingerprint, secondary_fingerprint, len(sequence), len(slots)
    )
    while slots[slot] >= 0:
        slot += 1
        if slot == len(slots):
            slot = 0
    slots[slot] = len(entries) - 1


def _empty_cache_slots(max_evaluations: Int) -> List[Int]:
    var capacity = 1
    while capacity < max_evaluations * 2:
        capacity *= 2
    var slots = List[Int]()
    for _ in range(capacity):
        slots.append(-1)
    return slots^


def shrink[
    evaluate: def(ChoiceSequence) thin -> Evaluation
](initial: ChoiceSequence, max_evaluations: Int) -> ShrinkResult:
    return shrink[evaluate](initial, List[Span](), max_evaluations)


def shrink[
    evaluate: def(ChoiceSequence) thin -> Evaluation
](
    initial: ChoiceSequence,
    initial_spans: List[Span],
    max_evaluations: Int,
) -> ShrinkResult:
    """Apply passes to a fixed point, caching evaluations.

    `evaluate` runs one candidate in replay mode and reports whether it
    is interesting plus the actually-consumed prefix, which is what gets
    adopted. A zero budget returns the input unchanged.
    """
    var best = initial.copy()
    if max_evaluations <= 0:
        return ShrinkResult(
            best^, _clip_spans(initial_spans, len(best)), 0, False
        )

    var best_spans = _clip_spans(initial_spans, len(best))
    var entries = List[_CacheEntry]()
    var slots = _empty_cache_slots(max_evaluations)
    var evaluations = 0
    var hit_budget = False

    while True:
        var improved = False

        # Candidates are walked one bounded page at a time. Cache hits
        # cost no evaluation, so they must not consume the cap: paging
        # makes a page of hits advance `fetched` and simply fetch the
        # next one, instead of hiding later uncached candidates behind a
        # cached prefix and reporting a fixed point with budget left.
        var fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var removals = delete_chunks(best.copy(), page, fetched)
            var index = 0
            while index < len(removals):
                var cand = removals[index].copy()
                index += 1
                fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
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

        # Candidates are walked one bounded page at a time. Cache hits
        # cost no evaluation, so they must not consume the cap: paging
        # makes a page of hits advance `fetched` and simply fetch the
        # next one, instead of hiding later uncached candidates behind a
        # cached prefix and reporting a fixed point with budget left.
        var zeroed_count = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var zeroings = zero_chunks(best.copy(), page, zeroed_count)
            var index = 0
            while index < len(zeroings):
                var cand = zeroings[index].copy()
                index += 1
                zeroed_count += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
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
            if best.nodes[i].forced:
                continue
            if best.nodes[i].value == UInt64(0):
                continue
            var current = best.nodes[i].value
            var trial = best.with_value_at(i, UInt64(0))
            var idx = _lookup(entries, slots, trial)
            var zero_interesting = False
            var zero_consumed = trial.copy()
            var zero_spans = best_spans.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
                zero_spans = entries[idx].spans.copy()
            else:
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                evaluations += 1
                var result = evaluate(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                zero_spans = result.spans.copy()
                _append_cache_entry(
                    entries,
                    slots,
                    trial,
                    zero_interesting,
                    zero_consumed,
                    zero_spans,
                )
            if zero_interesting and is_shortlex_smaller(zero_consumed, best):
                best = zero_consumed^
                best_spans = zero_spans^
                improved = True
                break
            elif zero_interesting and zero_consumed == best:
                best_spans = zero_spans^
            if hit_budget:
                break
            var candidate = UInt64(1)
            var changed = False
            while candidate < current:
                var probe = best.with_value_at(i, candidate)
                var pidx = _lookup(entries, slots, probe)
                var p_interesting = False
                var p_consumed = probe.copy()
                var p_spans = best_spans.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var presult = evaluate(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    p_spans = presult.spans.copy()
                    _append_cache_entry(
                        entries,
                        slots,
                        probe,
                        p_interesting,
                        p_consumed,
                        p_spans,
                    )
                if p_interesting and is_shortlex_smaller(p_consumed, best):
                    best = p_consumed^
                    best_spans = p_spans^
                    changed = True
                    break
                elif p_interesting and p_consumed == best:
                    best_spans = p_spans^
                    break
                candidate += UInt64(1)
            if hit_budget:
                break
            if changed:
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # delete_spans
        var span_removals = delete_spans(best.copy(), best_spans.copy())
        for j in range(len(span_removals)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_removals[j].copy()
            if _lookup(entries, slots, cand) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            _append_cache_entry(
                entries, slots, cand, interesting, consumed, cspans
            )
            if interesting and is_shortlex_smaller(consumed, best):
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # zero_spans
        var span_zeroings = zero_spans(best.copy(), best_spans.copy())
        for j in range(len(span_zeroings)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_zeroings[j].copy()
            if _lookup(entries, slots, cand) >= 0:
                continue
            evaluations += 1
            var result = evaluate(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            _append_cache_entry(
                entries, slots, cand, interesting, consumed, cspans
            )
            if interesting and is_shortlex_smaller(consumed, best):
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # sort_spans
        var sort_fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var span_sorts = sort_spans(
                best.copy(), best_spans.copy(), page, sort_fetched
            )
            var index = 0
            while index < len(span_sorts):
                var cand = span_sorts[index].copy()
                index += 1
                sort_fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(span_sorts) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # swap_adjacent_spans
        var swap_fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var span_swaps = swap_adjacent_spans(
                best.copy(), best_spans.copy(), page, swap_fetched
            )
            var index = 0
            while index < len(span_swaps):
                var cand = span_swaps[index].copy()
                index += 1
                swap_fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = evaluate(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(span_swaps) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # lower_duplicates: lower same-valued choices together
        var seen_dups = List[UInt64]()
        for i in range(n):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            if best.nodes[i].forced:
                continue
            var v = best.nodes[i].value
            if v == UInt64(0):
                continue
            var already = False
            for k in range(len(seen_dups)):
                if seen_dups[k] == v:
                    already = True
                    break
            if already:
                continue
            seen_dups.append(v)
            var group = List[Int]()
            for k in range(n):
                if best.nodes[k].forced:
                    continue
                if best.nodes[k].value == v:
                    group.append(k)
            if len(group) < 2:
                continue
            var cand0 = best.copy()
            for g in range(len(group)):
                cand0 = cand0.with_value_at(group[g], UInt64(0))
            var idx0 = _lookup(entries, slots, cand0)
            var c0_int: Bool
            var c0_cons: ChoiceSequence
            var c0_spans: List[Span]
            if idx0 >= 0:
                c0_int = entries[idx0].is_interesting
                c0_cons = entries[idx0].consumed.copy()
                c0_spans = entries[idx0].spans.copy()
            else:
                evaluations += 1
                var res = evaluate(cand0^)
                c0_int = res.is_interesting
                c0_cons = res.consumed.copy()
                c0_spans = res.spans.copy()
                _append_cache_entry(
                    entries, slots, cand0, c0_int, c0_cons, c0_spans
                )
            if c0_int and is_shortlex_smaller(c0_cons, best):
                best = c0_cons^
                best_spans = c0_spans^
                improved = True
                break
            elif c0_int and c0_cons == best:
                best_spans = c0_spans^
            var lo = UInt64(0)
            var hi = v
            var dup_changed = False
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.copy()
                for g in range(len(group)):
                    probe = probe.with_value_at(group[g], mid)
                var pidx = _lookup(entries, slots, probe)
                var p_int: Bool
                var p_cons: ChoiceSequence
                var p_spans: List[Span]
                if pidx >= 0:
                    p_int = entries[pidx].is_interesting
                    p_cons = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    evaluations += 1
                    var res = evaluate(probe^)
                    p_int = res.is_interesting
                    p_cons = res.consumed.copy()
                    p_spans = res.spans.copy()
                    _append_cache_entry(
                        entries, slots, probe, p_int, p_cons, p_spans
                    )
                if p_int:
                    hi = mid
                    if is_shortlex_smaller(p_cons, best):
                        best = p_cons^
                        best_spans = p_spans^
                        dup_changed = True
                    elif p_cons == best:
                        best_spans = p_spans^
                else:
                    lo = mid
            if hit_budget:
                break
            if dup_changed:
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # redistribute: move value from earlier integer choice to later one
        var redist_changed = False
        for i in range(n):
            if redist_changed or evaluations >= max_evaluations:
                break
            if best.nodes[i].forced or best.nodes[i].kind != ChoiceKind.INTEGER:
                continue
            var a = best.nodes[i].value
            if a == UInt64(0):
                continue
            for j in range(i + 1, n):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                if (
                    best.nodes[j].forced
                    or best.nodes[j].kind != ChoiceKind.INTEGER
                ):
                    continue
                var b = best.nodes[j].value
                var max_j = best.nodes[j].max_value
                if b >= max_j:
                    continue

                var j_maxed = best.with_value_at(j, max_j)
                var probe0 = j_maxed.with_value_at(i, UInt64(0))
                var idx0 = _lookup(entries, slots, probe0)
                var p0_int: Bool
                var p0_cons: ChoiceSequence
                var p0_spans: List[Span]
                if idx0 >= 0:
                    p0_int = entries[idx0].is_interesting
                    p0_cons = entries[idx0].consumed.copy()
                    p0_spans = entries[idx0].spans.copy()
                else:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var res = evaluate(probe0^)
                    p0_int = res.is_interesting
                    p0_cons = res.consumed.copy()
                    p0_spans = res.spans.copy()
                    _append_cache_entry(
                        entries, slots, probe0, p0_int, p0_cons, p0_spans
                    )

                var target_i = UInt64(0)
                var found_target_i = False
                if p0_int:
                    target_i = UInt64(0)
                    found_target_i = True
                else:
                    var lo_i = UInt64(0)
                    var hi_i = a
                    while hi_i - lo_i > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid_i = lo_i + (hi_i - lo_i) // UInt64(2)
                        var probe_i = j_maxed.with_value_at(i, mid_i)
                        var idx_i = _lookup(entries, slots, probe_i)
                        var pi_int: Bool
                        var pi_cons: ChoiceSequence
                        var pi_spans: List[Span]
                        if idx_i >= 0:
                            pi_int = entries[idx_i].is_interesting
                            pi_cons = entries[idx_i].consumed.copy()
                            pi_spans = entries[idx_i].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = evaluate(probe_i^)
                            pi_int = res.is_interesting
                            pi_cons = res.consumed.copy()
                            pi_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                probe_i,
                                pi_int,
                                pi_cons,
                                pi_spans,
                            )
                        if pi_int:
                            hi_i = mid_i
                        else:
                            lo_i = mid_i
                    if hit_budget:
                        break
                    if hi_i < a:
                        target_i = hi_i
                        found_target_i = True

                if found_target_i:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    var base_seq = best.with_value_at(i, target_i)
                    var probe_j0 = base_seq.with_value_at(j, UInt64(0))
                    var idx_j0 = _lookup(entries, slots, probe_j0)
                    var pj0_int: Bool
                    var pj0_cons: ChoiceSequence
                    var pj0_spans: List[Span]
                    if idx_j0 >= 0:
                        pj0_int = entries[idx_j0].is_interesting
                        pj0_cons = entries[idx_j0].consumed.copy()
                        pj0_spans = entries[idx_j0].spans.copy()
                    else:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var res = evaluate(probe_j0^)
                        pj0_int = res.is_interesting
                        pj0_cons = res.consumed.copy()
                        pj0_spans = res.spans.copy()
                        _append_cache_entry(
                            entries,
                            slots,
                            probe_j0,
                            pj0_int,
                            pj0_cons,
                            pj0_spans,
                        )

                    if pj0_int and is_shortlex_smaller(pj0_cons, best):
                        best = pj0_cons^
                        best_spans = pj0_spans^
                        redist_changed = True
                        improved = True
                        break
                    elif pj0_int and pj0_cons == best:
                        best_spans = pj0_spans^

                    var lo_j = UInt64(0)
                    var hi_j = max_j
                    var best_j_cand = ChoiceSequence()
                    var best_j_spans = List[Span]()
                    var had_j_cand = False
                    while hi_j - lo_j > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid_j = lo_j + (hi_j - lo_j) // UInt64(2)
                        var probe_j = base_seq.with_value_at(j, mid_j)
                        var idx_j = _lookup(entries, slots, probe_j)
                        var pj_int: Bool
                        var pj_cons: ChoiceSequence
                        var pj_spans: List[Span]
                        if idx_j >= 0:
                            pj_int = entries[idx_j].is_interesting
                            pj_cons = entries[idx_j].consumed.copy()
                            pj_spans = entries[idx_j].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = evaluate(probe_j^)
                            pj_int = res.is_interesting
                            pj_cons = res.consumed.copy()
                            pj_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                probe_j,
                                pj_int,
                                pj_cons,
                                pj_spans,
                            )
                        if pj_int:
                            hi_j = mid_j
                            if is_shortlex_smaller(pj_cons, best):
                                best_j_cand = pj_cons^
                                best_j_spans = pj_spans^
                                had_j_cand = True
                            elif pj_cons == best:
                                best_j_spans = pj_spans^
                        else:
                            lo_j = mid_j
                    if had_j_cand:
                        best = best_j_cand^
                        best_spans = best_j_spans^
                        redist_changed = True
                        improved = True
                        break
                    else:
                        var cand_h = base_seq.with_value_at(j, hi_j)
                        var idx_h = _lookup(entries, slots, cand_h)
                        var ph_int: Bool
                        var ph_cons: ChoiceSequence
                        var ph_spans: List[Span]
                        if idx_h >= 0:
                            ph_int = entries[idx_h].is_interesting
                            ph_cons = entries[idx_h].consumed.copy()
                            ph_spans = entries[idx_h].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = evaluate(cand_h^)
                            ph_int = res.is_interesting
                            ph_cons = res.consumed.copy()
                            ph_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                cand_h,
                                ph_int,
                                ph_cons,
                                ph_spans,
                            )
                        if ph_int and is_shortlex_smaller(ph_cons, best):
                            best = ph_cons^
                            best_spans = ph_spans^
                            redist_changed = True
                            improved = True
                            break
                        elif ph_int and ph_cons == best:
                            best_spans = ph_spans^
                    if hit_budget:
                        break
        if hit_budget:
            break
        if not improved:
            break

    return ShrinkResult(best^, best_spans^, evaluations, hit_budget)


def shrink_with[
    E: def(ChoiceSequence) raises -> Evaluation
](
    eval_fn: E, initial: ChoiceSequence, max_evaluations: Int
) raises -> ShrinkResult:
    return shrink_with(eval_fn, initial, List[Span](), max_evaluations)


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
    if max_evaluations <= 0:
        return ShrinkResult(
            best^, _clip_spans(initial_spans, len(best)), 0, False
        )

    var best_spans = _clip_spans(initial_spans, len(best))
    var entries = List[_CacheEntry]()
    var slots = _empty_cache_slots(max_evaluations)
    var evaluations = 0
    var hit_budget = False

    while True:
        var improved = False

        # Candidates are walked one bounded page at a time. Cache hits
        # cost no evaluation, so they must not consume the cap: paging
        # makes a page of hits advance `fetched` and simply fetch the
        # next one, instead of hiding later uncached candidates behind a
        # cached prefix and reporting a fixed point with budget left.
        var fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var removals = delete_chunks(best.copy(), page, fetched)
            var index = 0
            while index < len(removals):
                var cand = removals[index].copy()
                index += 1
                fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
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

        # Candidates are walked one bounded page at a time. Cache hits
        # cost no evaluation, so they must not consume the cap: paging
        # makes a page of hits advance `fetched` and simply fetch the
        # next one, instead of hiding later uncached candidates behind a
        # cached prefix and reporting a fixed point with budget left.
        var zeroed_count = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var zeroings = zero_chunks(best.copy(), page, zeroed_count)
            var index = 0
            while index < len(zeroings):
                var cand = zeroings[index].copy()
                index += 1
                zeroed_count += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
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
            if best.nodes[i].forced:
                continue
            if best.nodes[i].value == UInt64(0):
                continue
            var current = best.nodes[i].value
            var trial = best.with_value_at(i, UInt64(0))
            var idx = _lookup(entries, slots, trial)
            var zero_interesting = False
            var zero_consumed = trial.copy()
            var zero_spans = best_spans.copy()
            if idx >= 0:
                zero_interesting = entries[idx].is_interesting
                zero_consumed = entries[idx].consumed.copy()
                zero_spans = entries[idx].spans.copy()
            else:
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                evaluations += 1
                var result = eval_fn(trial^)
                zero_interesting = result.is_interesting
                zero_consumed = result.consumed.copy()
                zero_spans = result.spans.copy()
                _append_cache_entry(
                    entries,
                    slots,
                    trial,
                    zero_interesting,
                    zero_consumed,
                    zero_spans,
                )
            if zero_interesting and is_shortlex_smaller(zero_consumed, best):
                best = zero_consumed^
                best_spans = zero_spans^
                improved = True
                break
            elif zero_interesting and zero_consumed == best:
                best_spans = zero_spans^
            if hit_budget:
                break
            var candidate = UInt64(1)
            var changed = False
            while candidate < current:
                var probe = best.with_value_at(i, candidate)
                var pidx = _lookup(entries, slots, probe)
                var p_interesting = False
                var p_consumed = probe.copy()
                var p_spans = best_spans.copy()
                if pidx >= 0:
                    p_interesting = entries[pidx].is_interesting
                    p_consumed = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var presult = eval_fn(probe^)
                    p_interesting = presult.is_interesting
                    p_consumed = presult.consumed.copy()
                    p_spans = presult.spans.copy()
                    _append_cache_entry(
                        entries,
                        slots,
                        probe,
                        p_interesting,
                        p_consumed,
                        p_spans,
                    )
                if p_interesting and is_shortlex_smaller(p_consumed, best):
                    best = p_consumed^
                    best_spans = p_spans^
                    changed = True
                    break
                elif p_interesting and p_consumed == best:
                    best_spans = p_spans^
                    break
                candidate += UInt64(1)
            if hit_budget:
                break
            if changed:
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # delete_spans
        var span_removals = delete_spans(best.copy(), best_spans.copy())
        for j in range(len(span_removals)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_removals[j].copy()
            if _lookup(entries, slots, cand) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            _append_cache_entry(
                entries, slots, cand, interesting, consumed, cspans
            )
            if interesting and is_shortlex_smaller(consumed, best):
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # zero_spans
        var span_zeroings = zero_spans(best.copy(), best_spans.copy())
        for j in range(len(span_zeroings)):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var cand = span_zeroings[j].copy()
            if _lookup(entries, slots, cand) >= 0:
                continue
            evaluations += 1
            var result = eval_fn(cand^)
            var interesting = result.is_interesting
            var consumed = result.consumed.copy()
            var cspans = result.spans.copy()
            _append_cache_entry(
                entries, slots, cand, interesting, consumed, cspans
            )
            if interesting and is_shortlex_smaller(consumed, best):
                best = consumed^
                best_spans = cspans^
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # sort_spans
        var sort_fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var span_sorts = sort_spans(
                best.copy(), best_spans.copy(), page, sort_fetched
            )
            var index = 0
            while index < len(span_sorts):
                var cand = span_sorts[index].copy()
                index += 1
                sort_fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(span_sorts) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # swap_adjacent_spans
        var swap_fetched = 0
        while True:
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            var page = _page_size(max_evaluations - evaluations)
            var span_swaps = swap_adjacent_spans(
                best.copy(), best_spans.copy(), page, swap_fetched
            )
            var index = 0
            while index < len(span_swaps):
                var cand = span_swaps[index].copy()
                index += 1
                swap_fetched += 1
                if _lookup(entries, slots, cand) >= 0:
                    continue
                evaluations += 1
                var result = eval_fn(cand^)
                var interesting = result.is_interesting
                var consumed = result.consumed.copy()
                var cspans = result.spans.copy()
                _append_cache_entry(
                    entries, slots, cand, interesting, consumed, cspans
                )
                if interesting and is_shortlex_smaller(consumed, best):
                    best = consumed^
                    best_spans = cspans^
                    improved = True
                    break
            if improved or hit_budget:
                break
            if len(span_swaps) < page:
                break
        if hit_budget:
            break
        if improved:
            continue

        # lower_duplicates: lower same-valued choices together
        var seen_dups = List[UInt64]()
        for i in range(n):
            if evaluations >= max_evaluations:
                hit_budget = True
                break
            if best.nodes[i].forced:
                continue
            var v = best.nodes[i].value
            if v == UInt64(0):
                continue
            var already = False
            for k in range(len(seen_dups)):
                if seen_dups[k] == v:
                    already = True
                    break
            if already:
                continue
            seen_dups.append(v)
            var group = List[Int]()
            for k in range(n):
                if best.nodes[k].forced:
                    continue
                if best.nodes[k].value == v:
                    group.append(k)
            if len(group) < 2:
                continue
            var cand0 = best.copy()
            for g in range(len(group)):
                cand0 = cand0.with_value_at(group[g], UInt64(0))
            var idx0 = _lookup(entries, slots, cand0)
            var c0_int: Bool
            var c0_cons: ChoiceSequence
            var c0_spans: List[Span]
            if idx0 >= 0:
                c0_int = entries[idx0].is_interesting
                c0_cons = entries[idx0].consumed.copy()
                c0_spans = entries[idx0].spans.copy()
            else:
                evaluations += 1
                var res = eval_fn(cand0^)
                c0_int = res.is_interesting
                c0_cons = res.consumed.copy()
                c0_spans = res.spans.copy()
                _append_cache_entry(
                    entries, slots, cand0, c0_int, c0_cons, c0_spans
                )
            if c0_int and is_shortlex_smaller(c0_cons, best):
                best = c0_cons^
                best_spans = c0_spans^
                improved = True
                break
            elif c0_int and c0_cons == best:
                best_spans = c0_spans^
            var lo = UInt64(0)
            var hi = v
            var dup_changed = False
            while hi - lo > UInt64(1):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                var mid = lo + (hi - lo) // UInt64(2)
                var probe = best.copy()
                for g in range(len(group)):
                    probe = probe.with_value_at(group[g], mid)
                var pidx = _lookup(entries, slots, probe)
                var p_int: Bool
                var p_cons: ChoiceSequence
                var p_spans: List[Span]
                if pidx >= 0:
                    p_int = entries[pidx].is_interesting
                    p_cons = entries[pidx].consumed.copy()
                    p_spans = entries[pidx].spans.copy()
                else:
                    evaluations += 1
                    var res = eval_fn(probe^)
                    p_int = res.is_interesting
                    p_cons = res.consumed.copy()
                    p_spans = res.spans.copy()
                    _append_cache_entry(
                        entries, slots, probe, p_int, p_cons, p_spans
                    )
                if p_int:
                    hi = mid
                    if is_shortlex_smaller(p_cons, best):
                        best = p_cons^
                        best_spans = p_spans^
                        dup_changed = True
                    elif p_cons == best:
                        best_spans = p_spans^
                else:
                    lo = mid
            if hit_budget:
                break
            if dup_changed:
                improved = True
                break
        if hit_budget:
            break
        if improved:
            continue

        # redistribute: move value from earlier integer choice to later one
        var redist_changed = False
        for i in range(n):
            if redist_changed or evaluations >= max_evaluations:
                break
            if best.nodes[i].forced or best.nodes[i].kind != ChoiceKind.INTEGER:
                continue
            var a = best.nodes[i].value
            if a == UInt64(0):
                continue
            for j in range(i + 1, n):
                if evaluations >= max_evaluations:
                    hit_budget = True
                    break
                if (
                    best.nodes[j].forced
                    or best.nodes[j].kind != ChoiceKind.INTEGER
                ):
                    continue
                var b = best.nodes[j].value
                var max_j = best.nodes[j].max_value
                if b >= max_j:
                    continue

                var j_maxed = best.with_value_at(j, max_j)
                var probe0 = j_maxed.with_value_at(i, UInt64(0))
                var idx0 = _lookup(entries, slots, probe0)
                var p0_int: Bool
                var p0_cons: ChoiceSequence
                var p0_spans: List[Span]
                if idx0 >= 0:
                    p0_int = entries[idx0].is_interesting
                    p0_cons = entries[idx0].consumed.copy()
                    p0_spans = entries[idx0].spans.copy()
                else:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    evaluations += 1
                    var res = eval_fn(probe0^)
                    p0_int = res.is_interesting
                    p0_cons = res.consumed.copy()
                    p0_spans = res.spans.copy()
                    _append_cache_entry(
                        entries, slots, probe0, p0_int, p0_cons, p0_spans
                    )

                var target_i = UInt64(0)
                var found_target_i = False
                if p0_int:
                    target_i = UInt64(0)
                    found_target_i = True
                else:
                    var lo_i = UInt64(0)
                    var hi_i = a
                    while hi_i - lo_i > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid_i = lo_i + (hi_i - lo_i) // UInt64(2)
                        var probe_i = j_maxed.with_value_at(i, mid_i)
                        var idx_i = _lookup(entries, slots, probe_i)
                        var pi_int: Bool
                        var pi_cons: ChoiceSequence
                        var pi_spans: List[Span]
                        if idx_i >= 0:
                            pi_int = entries[idx_i].is_interesting
                            pi_cons = entries[idx_i].consumed.copy()
                            pi_spans = entries[idx_i].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = eval_fn(probe_i^)
                            pi_int = res.is_interesting
                            pi_cons = res.consumed.copy()
                            pi_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                probe_i,
                                pi_int,
                                pi_cons,
                                pi_spans,
                            )
                        if pi_int:
                            hi_i = mid_i
                        else:
                            lo_i = mid_i
                    if hit_budget:
                        break
                    if hi_i < a:
                        target_i = hi_i
                        found_target_i = True

                if found_target_i:
                    if evaluations >= max_evaluations:
                        hit_budget = True
                        break
                    var base_seq = best.with_value_at(i, target_i)
                    var probe_j0 = base_seq.with_value_at(j, UInt64(0))
                    var idx_j0 = _lookup(entries, slots, probe_j0)
                    var pj0_int: Bool
                    var pj0_cons: ChoiceSequence
                    var pj0_spans: List[Span]
                    if idx_j0 >= 0:
                        pj0_int = entries[idx_j0].is_interesting
                        pj0_cons = entries[idx_j0].consumed.copy()
                        pj0_spans = entries[idx_j0].spans.copy()
                    else:
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        evaluations += 1
                        var res = eval_fn(probe_j0^)
                        pj0_int = res.is_interesting
                        pj0_cons = res.consumed.copy()
                        pj0_spans = res.spans.copy()
                        _append_cache_entry(
                            entries,
                            slots,
                            probe_j0,
                            pj0_int,
                            pj0_cons,
                            pj0_spans,
                        )

                    if pj0_int and is_shortlex_smaller(pj0_cons, best):
                        best = pj0_cons^
                        best_spans = pj0_spans^
                        redist_changed = True
                        improved = True
                        break
                    elif pj0_int and pj0_cons == best:
                        best_spans = pj0_spans^

                    var lo_j = UInt64(0)
                    var hi_j = max_j
                    var best_j_cand = ChoiceSequence()
                    var best_j_spans = List[Span]()
                    var had_j_cand = False
                    while hi_j - lo_j > UInt64(1):
                        if evaluations >= max_evaluations:
                            hit_budget = True
                            break
                        var mid_j = lo_j + (hi_j - lo_j) // UInt64(2)
                        var probe_j = base_seq.with_value_at(j, mid_j)
                        var idx_j = _lookup(entries, slots, probe_j)
                        var pj_int: Bool
                        var pj_cons: ChoiceSequence
                        var pj_spans: List[Span]
                        if idx_j >= 0:
                            pj_int = entries[idx_j].is_interesting
                            pj_cons = entries[idx_j].consumed.copy()
                            pj_spans = entries[idx_j].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = eval_fn(probe_j^)
                            pj_int = res.is_interesting
                            pj_cons = res.consumed.copy()
                            pj_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                probe_j,
                                pj_int,
                                pj_cons,
                                pj_spans,
                            )
                        if pj_int:
                            hi_j = mid_j
                            if is_shortlex_smaller(pj_cons, best):
                                best_j_cand = pj_cons^
                                best_j_spans = pj_spans^
                                had_j_cand = True
                            elif pj_cons == best:
                                best_j_spans = pj_spans^
                        else:
                            lo_j = mid_j
                    if had_j_cand:
                        best = best_j_cand^
                        best_spans = best_j_spans^
                        redist_changed = True
                        improved = True
                        break
                    else:
                        var cand_h = base_seq.with_value_at(j, hi_j)
                        var idx_h = _lookup(entries, slots, cand_h)
                        var ph_int: Bool
                        var ph_cons: ChoiceSequence
                        var ph_spans: List[Span]
                        if idx_h >= 0:
                            ph_int = entries[idx_h].is_interesting
                            ph_cons = entries[idx_h].consumed.copy()
                            ph_spans = entries[idx_h].spans.copy()
                        else:
                            if evaluations >= max_evaluations:
                                hit_budget = True
                                break
                            evaluations += 1
                            var res = eval_fn(cand_h^)
                            ph_int = res.is_interesting
                            ph_cons = res.consumed.copy()
                            ph_spans = res.spans.copy()
                            _append_cache_entry(
                                entries,
                                slots,
                                cand_h,
                                ph_int,
                                ph_cons,
                                ph_spans,
                            )
                        if ph_int and is_shortlex_smaller(ph_cons, best):
                            best = ph_cons^
                            best_spans = ph_spans^
                            redist_changed = True
                            improved = True
                            break
                        elif ph_int and ph_cons == best:
                            best_spans = ph_spans^
                    if hit_budget:
                        break
        if hit_budget:
            break
        if not improved:
            break

    return ShrinkResult(best^, best_spans^, evaluations, hit_budget)
