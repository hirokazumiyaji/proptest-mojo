"""Basic shrink passes over choice sequences.

Per `docs/specs/shrinking.md`, enumeration passes are pure functions
returning candidates simplest-first, while adaptive passes take a pure
`is_interesting` predicate as a comptime thin function (ADR-0005).

Every candidate is strictly shortlex-smaller than the input, and
`forced` choices are never changed.
"""

from proptest.choice import (
    ChoiceSequence,
    is_shortlex_smaller,
)


def _chunk_sizes() -> List[Int]:
    """Chunk lengths tried by the enumeration passes, simplest-first."""
    var sizes = List[Int]()
    sizes.append(8)
    sizes.append(4)
    sizes.append(2)
    sizes.append(1)
    return sizes^


def delete_chunks(
    seq: ChoiceSequence, limit: Int = -1, offset: Int = 0
) -> List[ChoiceSequence]:
    """Contiguous-block deletions, simplest-first.

    Tries chunk lengths 8, 4, 2, 1 at every start position. Deletion
    always shortens the sequence, hence every candidate is
    shortlex-smaller. Empty results, and chunks that would drop any
    `forced` node, are skipped.

    `limit` caps how many candidates are materialized (`-1` for all).
    Each candidate copies the whole sequence, so a caller that will
    evaluate at most `k` of them should pass `k`: materializing every
    deletion of a near-maximal sequence needs gigabytes before the first
    one is even looked at.
    """
    var out = List[ChoiceSequence]()
    var skipped = 0
    var n = len(seq)
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            if limit >= 0 and len(out) >= limit:
                return out^
            var has_forced = False
            for k in range(start, start + size):
                if seq.nodes[k].forced:
                    has_forced = True
                    break
            if has_forced:
                continue
            var cand = seq.deleted(start, start + size)
            if len(cand) == 0:
                continue
            if skipped < offset:
                skipped += 1
                continue
            out.append(cand^)
    return out^


def zero_chunks(
    seq: ChoiceSequence, limit: Int = -1, offset: Int = 0
) -> List[ChoiceSequence]:
    """Contiguous-block zeroings, simplest-first.

    Same chunk sizes and positions as `delete_chunks`. `forced`
    nodes keep their value via `ChoiceSequence.zeroed`, so chunks
    that would leave the sequence unchanged are skipped: only
    strictly shortlex-smaller candidates are returned.
    """
    var out = List[ChoiceSequence]()
    var skipped = 0
    var n = len(seq)
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            if limit >= 0 and len(out) >= limit:
                return out^
            var cand = seq.zeroed(start, start + size)
            if not is_shortlex_smaller(cand, seq):
                continue
            if skipped < offset:
                skipped += 1
                continue
            out.append(cand^)
    return out^


def minimize_individual[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence) -> ChoiceSequence:
    """Minimize each choice value in place, left to right.

    For each non-`forced` index, tries 0 first and falls back to
    binary search for the smallest interesting value. The working
    sequence only ever moves down in shortlex order, so the result
    is shortlex-smaller-or-equal to the input.
    """
    var best = seq.copy()
    var n = len(best)
    for i in range(n):
        if best.nodes[i].forced:
            continue
        var current = best.nodes[i].value
        if current == UInt64(0):
            continue
        var zeroed = best.with_value_at(i, UInt64(0))
        if is_interesting(zeroed.copy()):
            best = zeroed^
            continue
        var lo = UInt64(0)
        var hi = current
        while hi - lo > UInt64(1):
            var mid = lo + (hi - lo) // UInt64(2)
            var cand = best.with_value_at(i, mid)
            if is_interesting(cand.copy()):
                hi = mid
                best = cand^
            else:
                lo = mid
    return best^
