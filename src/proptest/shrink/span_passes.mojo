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
