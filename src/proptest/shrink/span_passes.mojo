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


@fieldwise_init
struct _ParentKey(Copyable, Movable):
    """Identity of an immediate parent span, or root when `present` is false."""

    var present: Bool
    var start: Int
    var end: Int
    var depth: Int
    var label: UInt64

    def matches(self, other: Self) -> Bool:
        if self.present != other.present:
            return False
        if not self.present:
            return True
        return (
            self.start == other.start
            and self.end == other.end
            and self.depth == other.depth
            and self.label == other.label
        )


@fieldwise_init
struct _ReorderSpan(Copyable, Movable):
    """A reorderable block plus its pre-dedup immediate parent identity."""

    var span: Span
    var parent: _ParentKey


def _parent_key_of(span: Span) -> _ParentKey:
    return _ParentKey(Bool(True), span.start, span.end, span.depth, span.label)


def _root_parent_key() -> _ParentKey:
    return _ParentKey(Bool(False), 0, 0, 0, UInt64(0))


def _contains_as_parent(parent: Span, child: Span) -> Bool:
    """Whether `parent` is an ancestor container of `child`.

    Strict enclosure counts, and so does an equal-range shallower span:
    zero-choice wrappers such as `just` leave nested composites with the
    same `[start, end)` as their only child.
    """
    if parent.start > child.start or parent.end < child.end:
        return False
    if parent.start == child.start and parent.end == child.end:
        return parent.depth < child.depth
    return True


def _immediate_parent_key(raw: List[Span], idx: Int) -> _ParentKey:
    """Deepest ancestor of `raw[idx]` in the undeduped recording."""
    var best = -1
    var best_depth = -1
    var child = raw[idx].copy()
    for i in range(len(raw)):
        if i == idx:
            continue
        if not _contains_as_parent(raw[i], child):
            continue
        if raw[i].depth > best_depth:
            best_depth = raw[i].depth
            best = i
    if best < 0:
        return _root_parent_key()
    return _parent_key_of(raw[best])


def _in_bounds_span(span: Span, n: Int) -> Bool:
    if span.start < 0 or span.start >= n:
        return False
    if span.end <= span.start or span.end > n:
        return False
    return True


def _valid_spans_sorted(spans: List[Span], n: Int) -> List[_ReorderSpan]:
    """Reorderable spans sorted by `(start, end)`, with recording parents.

    Ancestry uses every in-bounds recorded span, including `discarded`
    parents from rejected filter attempts. Only non-discarded spans become
    reorderable blocks, and equal-range ancestors stay distinct until
    sibling grouping so wrappers such as `tuples(just(_), …)` remain
    reorderable. Start-ties break shorter-end-first, then shallower-first.
    """
    var ancestry = List[Span]()
    for i in range(len(spans)):
        var span = spans[i].copy()
        if not _in_bounds_span(span, n):
            continue
        ancestry.append(span^)
    var out = List[_ReorderSpan]()
    for i in range(len(ancestry)):
        if ancestry[i].discarded:
            continue
        out.append(
            _ReorderSpan(ancestry[i].copy(), _immediate_parent_key(ancestry, i))
        )
    for i in range(1, len(out)):
        var key = out[i].copy()
        var j = i - 1
        while j >= 0:
            var cur_start = out[j].span.start
            var cur_end = out[j].span.end
            var cur_depth = out[j].span.depth
            var before: Bool
            if key.span.start != cur_start:
                before = key.span.start < cur_start
            elif key.span.end != cur_end:
                before = key.span.end < cur_end
            else:
                before = key.span.depth < cur_depth
            if not before:
                break
            out[j + 1] = out[j].copy()
            j -= 1
        out[j + 1] = key^
    return out^


def _collect_sibling_runs(sorted: List[_ReorderSpan]) -> List[_SiblingRun]:
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
        var run_label = sorted[i].span.label
        var run_depth = sorted[i].span.depth
        var run_parent = sorted[i].parent.copy()
        var prev_end = sorted[i].span.end
        for j in range(i + 1, len(sorted)):
            var start = sorted[j].span.start
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
                sorted[j].span.label == run_label
                and sorted[j].span.depth == run_depth
                and sorted[j].parent.matches(run_parent)
            ):
                indices.append(j)
                prev_end = sorted[j].span.end
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
    runs: List[_SiblingRun], sorted: List[_ReorderSpan]
) -> List[Int]:
    """Run indices deepest-first, ties broken leftmost-first."""
    var order = List[Int]()
    for i in range(len(runs)):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_first = runs[key].indices[0]
        var key_depth = sorted[key_first].span.depth
        var key_start = sorted[key_first].span.start
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var cur_first = runs[cur].indices[0]
            var cur_depth = sorted[cur_first].span.depth
            var cur_start = sorted[cur_first].span.start
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
    values: List[UInt64], sorted: List[_ReorderSpan], run: _SiblingRun
) -> List[Int]:
    """Permutation sorting one run's blocks ascending, keeping ties stable."""
    var order = List[Int]()
    for i in range(run.count()):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_idx = run.indices[key]
        var key_start = sorted[key_idx].span.start
        var key_end = sorted[key_idx].span.end
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var cur_idx = run.indices[cur]
            var cur_start = sorted[cur_idx].span.start
            var cur_end = sorted[cur_idx].span.end
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
    seq: ChoiceSequence,
    sorted: List[_ReorderSpan],
    run: _SiblingRun,
    order: List[Int],
) -> ChoiceSequence:
    """One candidate with a run's blocks permuted by `order`."""
    var first = run.indices[0]
    var last = run.indices[run.count() - 1]
    var run_start = sorted[first].span.start
    var run_end = sorted[last].span.end
    var replacement = List[ChoiceNode]()
    for k in range(len(order)):
        var block = run.indices[order[k]]
        var block_start = sorted[block].span.start
        var block_end = sorted[block].span.end
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


def sort_spans(
    seq: ChoiceSequence,
    spans: List[Span],
    limit: Int = -1,
    offset: Int = 0,
) -> List[ChoiceSequence]:
    """Fully-sorted candidates, one per sibling run, deepest-first.

    Each maximal run of adjacent spans sharing one label, depth, and
    immediate parent contributes the candidate with its blocks in
    ascending lexicographic order. Reordering preserves the length, so
    only strictly shortlex-smaller candidates are returned; already-sorted
    runs contribute nothing. Whole `ChoiceNode`s move, hence `forced`
    values survive at their new positions. `limit`/`offset` bound eager
    materialization the same way as the other enumeration passes.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var sorted = _valid_spans_sorted(spans, n)
    var runs = _collect_sibling_runs(sorted)
    var order = _order_run_indices(runs, sorted)
    var values = seq.values()
    var skipped = 0
    for k in range(len(order)):
        if limit >= 0 and len(out) >= limit:
            return out^
        var run = runs[order[k]].copy()
        var perm = _run_sort_order(values, sorted, run)
        if _is_identity(perm):
            continue
        var cand = _splice_run(seq, sorted, run, perm^)
        if not is_shortlex_smaller(cand, seq):
            continue
        if skipped < offset:
            skipped += 1
            continue
        out.append(cand^)
    return out^


def swap_adjacent_spans(
    seq: ChoiceSequence,
    spans: List[Span],
    limit: Int = -1,
    offset: Int = 0,
) -> List[ChoiceSequence]:
    """Adjacent-swap candidates, deepest-run-first then leftmost-first.

    Each adjacent pair within a sibling run contributes the candidate
    with its two blocks exchanged, so partially-ordered inputs descend
    one bubble-sort step at a time. Reordering preserves the length, so
    only strictly shortlex-smaller candidates are returned; swaps of
    equal blocks or uphill swaps contribute nothing. `limit`/`offset`
    bound eager materialization the same way as the other enumeration
    passes.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    if n == 0:
        return out^
    var sorted = _valid_spans_sorted(spans, n)
    var runs = _collect_sibling_runs(sorted)
    var order = _order_run_indices(runs, sorted)
    var skipped = 0
    for k in range(len(order)):
        var run = runs[order[k]].copy()
        for j in range(run.count() - 1):
            if limit >= 0 and len(out) >= limit:
                return out^
            var cand = _splice_swap(
                seq,
                sorted[run.indices[j]].span,
                sorted[run.indices[j + 1]].span,
            )
            if not is_shortlex_smaller(cand, seq):
                continue
            if skipped < offset:
                skipped += 1
                continue
            out.append(cand^)
    return out^
