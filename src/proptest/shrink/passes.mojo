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


def delete_chunks(seq: ChoiceSequence) -> List[ChoiceSequence]:
    """Contiguous-block deletions, simplest-first.

    Tries chunk lengths 8, 4, 2, 1 at every start position, then orders
    the surviving candidates by their resulting shortlex value rather
    than by chunk size and start position. Deletion always shortens the
    sequence, hence every candidate is shortlex-smaller, but chunk order
    alone does not rank equal-length results: deleting size 8 from
    `[1..10]` yields `[9,10]`, `[1,10]`, `[1,2]`, and the shrink loop
    commits to the first interesting candidate, so it would settle on
    the largest one. Empty results, and chunks that would drop any
    `forced` node, are skipped.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
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
            _insert_shortlex(out, cand^)
    return out^


def _insert_shortlex(
    mut ordered: List[ChoiceSequence], var cand: ChoiceSequence
):
    """Insert `cand` into `ordered` keeping it sorted by shortlex order."""
    var j = len(ordered)
    while j > 0 and is_shortlex_smaller(cand, ordered[j - 1]):
        j -= 1
    ordered.insert(j, cand^)


def zero_chunks(seq: ChoiceSequence) -> List[ChoiceSequence]:
    """Contiguous-block zeroings, simplest-first.

    Same chunk sizes and positions as `delete_chunks`. `forced`
    nodes keep their value via `ChoiceSequence.zeroed`, so chunks
    that would leave the sequence unchanged are skipped: only
    strictly shortlex-smaller candidates are returned.
    """
    var out = List[ChoiceSequence]()
    var n = len(seq)
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            var cand = seq.zeroed(start, start + size)
            if not is_shortlex_smaller(cand, seq):
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
