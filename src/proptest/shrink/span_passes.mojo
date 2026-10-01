"""Span-based shrink passes over choice sequences.

Per `docs/specs/shrinking.md` (M3), `delete_spans` removes one structural
unit (e.g. a list element) and `zero_spans` simplifies one to all zeros.
Both are enumeration passes: pure functions returning candidates
deepest-span-first, so nested junk disappears before its parent. `forced`
choices keep their value via `ChoiceSequence.zeroed`; `discarded` and
empty spans yield no candidates.
"""

from proptest.choice import (
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
)


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
    var ranges = _valid_span_ranges(n, spans)
    for i in range(len(ranges.starts)):
        var cand = seq.deleted(ranges.starts[i], ranges.ends[i])
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
    var ranges = _valid_span_ranges(n, spans)
    for i in range(len(ranges.starts)):
        var cand = seq.zeroed(ranges.starts[i], ranges.ends[i])
        if not is_shortlex_smaller(cand, seq):
            continue
        out.append(cand^)
    return out^
