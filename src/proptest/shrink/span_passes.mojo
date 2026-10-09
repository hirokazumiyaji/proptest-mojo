"""Span-based shrink passes over choice sequences.

Per `docs/specs/shrinking.md` (M3), `delete_spans` removes one structural
unit (e.g. a list element), `zero_spans` simplifies one to all zeros,
`sort_spans` reorders each sibling run into ascending order, and
`swap_adjacent_spans` exchanges one adjacent sibling pair. Sibling runs
share label, depth, and choice adjacency, and ignore enclosing or nested
spans that interleave them in global order. All are enumeration passes:
pure functions returning candidates, with the span passes taking recorded
spans alongside the sequence. Deletion and zeroing emit deepest-span-first;
the reorder passes emit runs deepest-first so nested collections normalize
before their parents.
Every candidate is strictly shortlex-smaller than the input. `forced`
values are preserved (`ChoiceSequence.zeroed` for zeroing, whole-node
moves for reordering); `discarded` and empty spans yield no candidates.
"""

from proptest.choice import (
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)


@fieldwise_init
struct _SiblingRun(Copyable, Movable):
    """Indices into the sorted span list for one sibling run.

    Indices need not be contiguous in that list: enclosing and nested
    spans may sit between siblings in `(start, end)` order.
    """

    var indices: List[Int]

    def count(self) -> Int:
        return len(self.indices)


def _ordered_indices(spans: List[Span]) -> List[Int]:
    """Indices of `spans` sorted deepest-first, ties broken leftmost-first."""
    var order = List[Int]()
    for i in range(len(spans)):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_depth = spans[key].depth
        var key_start = spans[key].start
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var before: Bool
            if key_depth != spans[cur].depth:
                before = key_depth > spans[cur].depth
            else:
                before = key_start < spans[cur].start
            if not before:
                break
            order[j + 1] = cur
            j -= 1
        order[j + 1] = key
    return order^


@fieldwise_init
struct _SpanRanges(Movable):
    var starts: List[Int]
    var ends: List[Int]


def _valid_span_ranges(n: Int, spans: List[Span]) -> _SpanRanges:
    """Deepest-first, deduped, bounds-clipped `[start, end)` pairs.

    Discarded, empty, and out-of-range spans drop out here so each pass
    only has to apply its own progress check.
    """
    var starts = List[Int]()
    var ends = List[Int]()
    var order = _ordered_indices(spans)
    for k in range(len(order)):
        var idx = order[k]
        if spans[idx].discarded:
            continue
        var start = spans[idx].start
        if start < 0 or start >= n:
            continue
        var end = spans[idx].end
        if end > n:
            end = n
        if end <= start:
            continue
        var duplicate = False
        for s in range(len(starts)):
            if starts[s] == start and ends[s] == end:
                duplicate = True
                break
        if duplicate:
            continue
        starts.append(start)
        ends.append(end)
    return _SpanRanges(starts^, ends^)


def _valid_spans_sorted(spans: List[Span], n: Int) -> List[Span]:
    """Reorderable spans de-duplicated and sorted by `(start, end)`.

    Start-ties break shorter-end-first so a parent span sorts before its
    children. Sibling grouping skips those enclosing and nested spans
    rather than requiring siblings to be consecutive in this list.
    Reordering splices whole `[start, end)` blocks, so `end > n` spans
    are rejected outright rather than clipped: a clipped block would no
    longer align with any recorded sibling boundary.
    """
    var out = List[Span]()
    for i in range(len(spans)):
        var span = spans[i].copy()
        if span.discarded:
            continue
        if span.start < 0 or span.start >= n:
            continue
        if span.end <= span.start or span.end > n:
            continue
        var duplicate = False
        for s in range(len(out)):
            if out[s].start == span.start and out[s].end == span.end:
                duplicate = True
                break
        if duplicate:
            continue
        out.append(span^)
    for i in range(1, len(out)):
        var key = out[i].copy()
        var j = i - 1
        while j >= 0:
            var cur_start = out[j].start
            var cur_end = out[j].end
            var before: Bool
            if key.start != cur_start:
                before = key.start < cur_start
            else:
                before = key.end < cur_end
            if not before:
                break
            out[j + 1] = out[j].copy()
            j -= 1
        out[j + 1] = key^
    return out^


def _immediate_parent_idx(sorted: List[Span], idx: Int) -> Int:
    """Index of the deepest proper container of `sorted[idx]`, or `-1`.

    A proper container strictly encloses the span. Matching parents keeps
    choice-adjacent same-label blocks from different composites apart.
    """
    var best = -1
    var best_depth = -1
    var child_start = sorted[idx].start
    var child_end = sorted[idx].end
    for i in range(len(sorted)):
        if i == idx:
            continue
        var start = sorted[i].start
        var end = sorted[i].end
        if start > child_start or end < child_end:
            continue
        if start == child_start and end == child_end:
            continue
        if sorted[i].depth > best_depth:
            best_depth = sorted[i].depth
            best = i
    return best


def _collect_sibling_runs(sorted: List[Span]) -> List[_SiblingRun]:
    """Maximal adjacent runs sharing one label, depth, and parent.

    Siblings are choice-adjacent (`prev.end == next.start`) with the same
    label, depth, and immediate parent. Enclosing and nested spans that
    interleave them in `(start, end)` order are skipped. A gap, a used
    boundary span, a different label/depth, or a different parent ends
    the run.
    """
    var runs = List[_SiblingRun]()
    if len(sorted) == 0:
        return runs^
    var used = List[Bool]()
    for _ in range(len(sorted)):
        used.append(False)
    for i in range(len(sorted)):
        if used[i]:
            continue
        var indices = List[Int]()
        indices.append(i)
        var run_label = sorted[i].label
        var run_depth = sorted[i].depth
        var run_parent = _immediate_parent_idx(sorted, i)
        var prev_end = sorted[i].end
        for j in range(i + 1, len(sorted)):
            var start = sorted[j].start
            if start > prev_end:
                break
            if start < prev_end:
                # Nested or overlapping span inside the current block.
                continue
            # `start == prev_end`: keep used spans visible so an earlier
            # sibling run at this boundary still separates parents.
            if used[j]:
                break
            if (
                sorted[j].label == run_label
                and sorted[j].depth == run_depth
                and _immediate_parent_idx(sorted, j) == run_parent
            ):
                indices.append(j)
                prev_end = sorted[j].end
                continue
            # Another span claims this boundary: parent/peer separator.
            break
        if len(indices) >= 2:
            for k in range(len(indices)):
                used[indices[k]] = True
            runs.append(_SiblingRun(indices^))
        else:
            used[i] = True
    return runs^


def _order_run_indices(
    runs: List[_SiblingRun], sorted: List[Span]
) -> List[Int]:
    """Run indices deepest-first, ties broken leftmost-first."""
    var order = List[Int]()
    for i in range(len(runs)):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_first = runs[key].indices[0]
        var key_depth = sorted[key_first].depth
        var key_start = sorted[key_first].start
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var cur_first = runs[cur].indices[0]
            var cur_depth = sorted[cur_first].depth
            var cur_start = sorted[cur_first].start
            var before: Bool
            if key_depth != cur_depth:
                before = key_depth > cur_depth
            else:
                before = key_start < cur_start
            if not before:
                break
            order[j + 1] = cur
            j -= 1
        order[j + 1] = key
    return order^


def _block_less(
    values: List[UInt64], a_start: Int, a_end: Int, b_start: Int, b_end: Int
) -> Bool:
    """Lexicographic less on two value slices, shorter winning on a prefix."""
    var i = a_start
    var j = b_start
    while i < a_end and j < b_end:
        if values[i] != values[j]:
            return values[i] < values[j]
        i += 1
        j += 1
    return (a_end - a_start) < (b_end - b_start)


def _run_sort_order(
    values: List[UInt64], sorted: List[Span], run: _SiblingRun
) -> List[Int]:
    """Permutation sorting one run's blocks ascending, keeping ties stable."""
    var order = List[Int]()
    for i in range(run.count()):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_idx = run.indices[key]
        var key_start = sorted[key_idx].start
        var key_end = sorted[key_idx].end
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var cur_idx = run.indices[cur]
            var cur_start = sorted[cur_idx].start
            var cur_end = sorted[cur_idx].end
            if not _block_less(values, key_start, key_end, cur_start, cur_end):
                break
            order[j + 1] = cur
            j -= 1
        order[j + 1] = key
    return order^


def _is_identity(order: List[Int]) -> Bool:
    """Whether a permutation leaves every position in place."""
    for i in range(len(order)):
        if order[i] != i:
            return False
    return True


def _splice_run(
    seq: ChoiceSequence, sorted: List[Span], run: _SiblingRun, order: List[Int]
) -> ChoiceSequence:
    """One candidate with a run's blocks permuted by `order`."""
    var first = run.indices[0]
    var last = run.indices[run.count() - 1]
    var run_start = sorted[first].start
    var run_end = sorted[last].end
    var replacement = List[ChoiceNode]()
    for k in range(len(order)):
        var block = run.indices[order[k]]
        var block_start = sorted[block].start
        var block_end = sorted[block].end
        for i in range(block_start, block_end):
            replacement.append(seq.nodes[i].copy())
    return seq.replaced_range(run_start, run_end, replacement^)


def _splice_swap(seq: ChoiceSequence, a: Span, b: Span) -> ChoiceSequence:
    """One candidate with adjacent blocks `a` and `b` exchanged."""
    var replacement = List[ChoiceNode]()
    for i in range(b.start, b.end):
        replacement.append(seq.nodes[i].copy())
    for i in range(a.start, a.end):
        replacement.append(seq.nodes[i].copy())
    return seq.replaced_range(a.start, b.end, replacement^)


def delete_spans(
    seq: ChoiceSequence,
    spans: List[Span],
    limit: Int = -1,
    offset: Int = 0,
) -> List[ChoiceSequence]:
    """Single-span deletions, deepest-first.

    Each non-`discarded`, non-empty span contributes one candidate with
    its `[start, end)` range removed. Deletion always shortens the
    sequence, hence every candidate is shortlex-smaller. Empty results
    and duplicate ranges are skipped.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var ranges = _valid_span_ranges(n, spans)
    var skipped = 0
    for i in range(len(ranges.starts)):
        if limit >= 0 and len(out) >= limit:
            return out^
        var cand = seq.deleted(ranges.starts[i], ranges.ends[i])
        if len(cand) == 0:
            continue
        if skipped < offset:
            skipped += 1
            continue
        out.append(cand^)
    return out^


def zero_spans(
    seq: ChoiceSequence,
    spans: List[Span],
    limit: Int = -1,
    offset: Int = 0,
) -> List[ChoiceSequence]:
    """Single-span zeroings, deepest-first.

    Each non-`discarded`, non-empty span contributes one candidate with
    the values in its `[start, end)` range set to 0. `forced` nodes keep
    their value via `ChoiceSequence.zeroed`, so spans that would leave
    the sequence unchanged are skipped: only strictly shortlex-smaller
    candidates are returned.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var ranges = _valid_span_ranges(n, spans)
    var skipped = 0
    for i in range(len(ranges.starts)):
        if limit >= 0 and len(out) >= limit:
            return out^
        var cand = seq.zeroed(ranges.starts[i], ranges.ends[i])
        if not is_shortlex_smaller(cand, seq):
            continue
        if skipped < offset:
            skipped += 1
            continue
        out.append(cand^)
    return out^


def sort_spans(seq: ChoiceSequence, spans: List[Span]) -> List[ChoiceSequence]:
    """Fully-sorted candidates, one per sibling run, deepest-first.

    Each maximal run of adjacent spans sharing one label and depth
    contributes the candidate with its blocks in ascending
    lexicographic order. Reordering preserves the length, so only
    strictly shortlex-smaller candidates are returned; already-sorted
    runs contribute nothing. Whole `ChoiceNode`s move, hence `forced`
    values survive at their new positions.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var sorted = _valid_spans_sorted(spans, n)
    var runs = _collect_sibling_runs(sorted)
    var order = _order_run_indices(runs, sorted)
    var values = seq.values()
    for k in range(len(order)):
        var run = runs[order[k]].copy()
        var perm = _run_sort_order(values, sorted, run)
        if _is_identity(perm):
            continue
        var cand = _splice_run(seq, sorted, run, perm^)
        if not is_shortlex_smaller(cand, seq):
            continue
        out.append(cand^)
    return out^


def swap_adjacent_spans(
    seq: ChoiceSequence, spans: List[Span]
) -> List[ChoiceSequence]:
    """Adjacent-swap candidates, deepest-run-first then leftmost-first.

    Each adjacent pair within a sibling run contributes the candidate
    with its two blocks exchanged, so partially-ordered inputs descend
    one bubble-sort step at a time. Reordering preserves the length, so
    only strictly shortlex-smaller candidates are returned; swaps of
    equal blocks or uphill swaps contribute nothing.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var sorted = _valid_spans_sorted(spans, n)
    var runs = _collect_sibling_runs(sorted)
    var order = _order_run_indices(runs, sorted)
    for k in range(len(order)):
        var run = runs[order[k]].copy()
        for j in range(run.count() - 1):
            var cand = _splice_swap(
                seq,
                sorted[run.indices[j]],
                sorted[run.indices[j + 1]],
            )
            if not is_shortlex_smaller(cand, seq):
                continue
            out.append(cand^)
    return out^
