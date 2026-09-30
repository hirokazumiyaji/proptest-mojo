"""Span-based shrink passes over choice sequences.

Per `docs/specs/shrinking.md` (M3), `delete_spans` removes one structural
unit (e.g. a list element), `zero_spans` simplifies one to all zeros,
`sort_spans` reorders each sibling run into ascending order, and
`swap_adjacent_spans` exchanges one adjacent sibling pair. All are
enumeration passes: pure functions returning candidates, with the span
passes taking recorded spans alongside the sequence. Deletion and
zeroing emit deepest-span-first; the reorder passes emit runs
deepest-first so nested collections normalize before their parents.
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
    var start_idx: Int
    var count: Int
    var depth: Int
    var start_pos: Int


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


def _is_reorderable(span: Span, n: Int) -> Bool:
    """Whether `span` covers an exact non-empty block of a length-`n` sequence.
    """
    if span.discarded:
        return False
    if span.start < 0 or span.start >= n:
        return False
    if span.end <= span.start or span.end > n:
        return False
    return True


def _valid_spans_sorted(spans: List[Span], n: Int) -> List[Span]:
    """Valid reorderable spans de-duplicated and sorted by start position."""
    var out = List[Span]()
    for i in range(len(spans)):
        var span = spans[i].copy()
        if not _is_reorderable(span.copy(), n):
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


def _collect_sibling_runs(sorted: List[Span]) -> List[_SiblingRun]:
    """Maximal adjacent runs sharing one label and depth.

    Siblings of one collection are laid out consecutively, so only
    blocks with `prev.end == next.start` belong to one run. Gaps mean
    different parents and must not be reordered across.
    """
    var runs = List[_SiblingRun]()
    if len(sorted) == 0:
        return runs^
    var run_start = 0
    var run_label = sorted[0].label
    var run_depth = sorted[0].depth
    var prev_end = sorted[0].end
    for i in range(1, len(sorted)):
        var span = sorted[i].copy()
        if (
            span.start == prev_end
            and span.label == run_label
            and span.depth == run_depth
        ):
            prev_end = span.end
            continue
        var count = i - run_start
        if count >= 2:
            runs.append(
                _SiblingRun(
                    run_start, count, run_depth, sorted[run_start].start
                )
            )
        run_start = i
        run_label = span.label
        run_depth = span.depth
        prev_end = span.end
    var tail = len(sorted) - run_start
    if tail >= 2:
        runs.append(
            _SiblingRun(run_start, tail, run_depth, sorted[run_start].start)
        )
    return runs^


def _order_run_indices(runs: List[_SiblingRun]) -> List[Int]:
    """Run indices deepest-first, ties broken leftmost-first."""
    var order = List[Int]()
    for i in range(len(runs)):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_depth = runs[key].depth
        var key_start = runs[key].start_pos
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var before: Bool
            if key_depth != runs[cur].depth:
                before = key_depth > runs[cur].depth
            else:
                before = key_start < runs[cur].start_pos
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
    for i in range(run.count):
        order.append(i)
    for i in range(1, len(order)):
        var key = order[i]
        var key_idx = run.start_idx + key
        var key_start = sorted[key_idx].start
        var key_end = sorted[key_idx].end
        var j = i - 1
        while j >= 0:
            var cur = order[j]
            var cur_idx = run.start_idx + cur
            var cur_start = sorted[cur_idx].start
            var cur_end = sorted[cur_idx].end
            if not _block_less(
                values.copy(), key_start, key_end, cur_start, cur_end
            ):
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
    var run_start = sorted[run.start_idx].start
    var run_end = sorted[run.start_idx + run.count - 1].end
    var replacement = List[ChoiceNode]()
    for k in range(len(order)):
        var block = sorted[run.start_idx + order[k]].copy()
        for i in range(block.start, block.end):
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
    seq: ChoiceSequence, spans: List[Span]
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
    var order = _ordered_indices(spans.copy())
    var seen_starts = List[Int]()
    var seen_ends = List[Int]()
    for k in range(len(order)):
        var span = spans[order[k]].copy()
        if span.discarded:
            continue
        if span.start < 0 or span.start >= n:
            continue
        var end = span.end
        if end > n:
            end = n
        if end <= span.start:
            continue
        var duplicate = False
        for s in range(len(seen_starts)):
            if seen_starts[s] == span.start and seen_ends[s] == end:
                duplicate = True
                break
        if duplicate:
            continue
        seen_starts.append(span.start)
        seen_ends.append(end)
        var cand = seq.deleted(span.start, end)
        if len(cand) == 0:
            continue
        out.append(cand^)
    return out^


def zero_spans(seq: ChoiceSequence, spans: List[Span]) -> List[ChoiceSequence]:
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
    var order = _ordered_indices(spans.copy())
    var seen_starts = List[Int]()
    var seen_ends = List[Int]()
    for k in range(len(order)):
        var span = spans[order[k]].copy()
        if span.discarded:
            continue
        if span.start < 0 or span.start >= n:
            continue
        var end = span.end
        if end > n:
            end = n
        if end <= span.start:
            continue
        var duplicate = False
        for s in range(len(seen_starts)):
            if seen_starts[s] == span.start and seen_ends[s] == end:
                duplicate = True
                break
        if duplicate:
            continue
        seen_starts.append(span.start)
        seen_ends.append(end)
        var cand = seq.zeroed(span.start, end)
        if not is_shortlex_smaller(cand, seq):
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
    var sorted = _valid_spans_sorted(spans.copy(), n)
    var runs = _collect_sibling_runs(sorted.copy())
    var order = _order_run_indices(runs.copy())
    var values = seq.values()
    for k in range(len(order)):
        var run = runs[order[k]].copy()
        var perm = _run_sort_order(values.copy(), sorted.copy(), run.copy())
        if _is_identity(perm.copy()):
            continue
        var cand = _splice_run(seq.copy(), sorted.copy(), run^, perm^)
        if not is_shortlex_smaller(cand.copy(), seq.copy()):
            continue
        var duplicate = False
        for s in range(len(out)):
            if out[s].copy() == cand.copy():
                duplicate = True
                break
        if duplicate:
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
    var sorted = _valid_spans_sorted(spans.copy(), n)
    var runs = _collect_sibling_runs(sorted.copy())
    var order = _order_run_indices(runs.copy())
    for k in range(len(order)):
        var run = runs[order[k]].copy()
        for j in range(run.count - 1):
            var a = sorted[run.start_idx + j].copy()
            var b = sorted[run.start_idx + j + 1].copy()
            var cand = _splice_swap(seq.copy(), a.copy(), b.copy())
            if not is_shortlex_smaller(cand.copy(), seq.copy()):
                continue
            var duplicate = False
            for s in range(len(out)):
                if out[s].copy() == cand.copy():
                    duplicate = True
                    break
            if duplicate:
                continue
            out.append(cand^)
    return out^
