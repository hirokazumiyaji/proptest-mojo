"""Basic shrink passes over choice sequences.

Per `docs/specs/shrinking.md`, enumeration passes are pure functions
returning candidates simplest-first, while adaptive passes take a pure
`is_interesting` predicate as a comptime thin function (ADR-0005).

Every candidate is strictly shortlex-smaller than the input, and
`forced` choices are never changed.

The enumeration passes materialize candidates eagerly, and each candidate
copies the whole sequence, so a caller must pass the `limit` it can
actually evaluate. The shrink loop (added on the branch that owns
`shrinker.mojo`) passes its remaining evaluation budget; without that,
a near-maximal sequence would build tens of thousands of full copies
before the first one is looked at.
"""

from proptest.choice import (
    ChoiceSequence,
)


def _chunk_sizes() -> List[Int]:
    """Chunk lengths tried by the enumeration passes, simplest-first."""
    var sizes = List[Int]()
    sizes.append(8)
    sizes.append(4)
    sizes.append(2)
    sizes.append(1)
    return sizes^


def delete_chunks(seq: ChoiceSequence, limit: Int = -1) -> List[ChoiceSequence]:
    """Contiguous-block deletions, simplest-first.

    Tries chunk lengths 8, 4, 2, 1 at every start position and orders
    the surviving candidates by their resulting shortlex value. Deletion
    always shortens the sequence, hence every candidate is
    shortlex-smaller. Empty results, and chunks that would drop any
    `forced` node, are skipped.

    `limit` caps how many candidates are materialized (`-1` for all).
    Each candidate copies the whole sequence, so a caller that will
    evaluate at most `k` of them should pass `k`: materializing every
    deletion of a near-maximal sequence needs gigabytes before the first
    one is even looked at.
    """
    var values = seq.values()
    var n = len(seq)
    var group_sizes = List[Int]()
    var group_starts = List[List[Int]]()
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            if limit >= 0 and len(out) >= limit:
                return out^
            var has_forced = False
            for k in range(start, start + removed):
                if seq.nodes[k].forced:
                    has_forced = True
                    break
            if has_forced:
                continue
            if removed == 0 or removed == n:
                continue
            var gi = -1
            for i in range(len(group_sizes)):
                if group_sizes[i] == removed:
                    gi = i
                    break
            if gi < 0:
                group_sizes.append(removed)
                group_starts.append(List[Int]())
                gi = len(group_sizes) - 1
            group_starts[gi].append(start)

    var out = List[ChoiceSequence]()
    var skipped = 0
    for i in range(len(group_sizes)):
        # A group dropping `r` nodes has length `n - r`; shortlex is
        # length-first, so emit the shortest groups first.
        if group_sizes[i] == 0 or group_sizes[i] == n:
            continue
        var ordered = _deletion_order(
            values.copy(), group_starts[i].copy(), group_sizes[i]
        )
        for k in range(len(ordered)):
            # `offset`/`limit` cut the ordered sequence, so the page is
            # the simplest candidates not already consumed. Materializing
            # the skipped ones just to drop them would cost a full
            # sequence copy each.
            if skipped < offset:
                skipped += 1
                continue
            if limit >= 0 and len(out) >= limit:
                return out^
            var start = ordered[k]
            out.append(seq.deleted(start, start + group_sizes[i])^)
    return out^


def zero_chunks(seq: ChoiceSequence, limit: Int = -1) -> List[ChoiceSequence]:
    """Contiguous-block zeroings, simplest-first.

    Same chunk lengths and positions as `delete_chunks`, likewise
    ordered by the resulting shortlex value rather than by chunk size:
    chunk order alone puts size-8 zeroings ahead of the shortlex-smaller
    size-4 zeroings, and the shrink loop commits to the first
    interesting candidate. `forced` nodes keep their value via
    `ChoiceSequence.zeroed`, so chunks that would leave the sequence
    unchanged are skipped: only strictly shortlex-smaller candidates are
    returned.

    `limit` and `offset` page the ordered candidates exactly as in
    `delete_chunks`.
    """
    # `forced` nodes are never zeroed, so ordering must treat them as
    # already-zero: otherwise a candidate is compared as if it had changed
    # them and the order disagrees with the emitted sequences.
    var values = _effective_values(seq)
    var n = len(seq)
    var runs = _zero_runs(values)
    var starts = List[Int]()
    var ends = List[Int]()
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            if limit >= 0 and len(out) >= limit:
                return out^
            var cand = seq.zeroed(start, start + size)
            if not is_shortlex_smaller(cand, seq):
                continue
            starts.append(start)
            ends.append(end)
    var out = List[ChoiceSequence]()
    var ordered = _zeroing_order(
        values.copy(), runs.copy(), starts.copy(), ends.copy(), n
    )
    # `ordered` indexes the local copies, so re-derive from them rather
    # than the (now transferred) originals. `limit` truncates only after
    # the order is fixed, so the result is the simplest-first prefix
    # rather than the first windows in generation order.
    for i in range(offset, len(ordered)):
        if limit >= 0 and len(out) >= limit:
            break
        var k = ordered[i]
        out.append(seq.zeroed(starts[k], ends[k]))
    return out^


def _changes_value(
    values: List[UInt64], runs: List[Int], start: Int, end: Int
) -> Bool:
    """Whether zeroing `[start, end)` would change `values` at all.

    `forced` nodes read as zero (see `_effective_values`), so a window
    over already-zero values produces the input unchanged and must be
    skipped: such a candidate is not strictly shortlex-smaller.
    """
    var i = start
    while i < end:
        var skipped = runs[i]
        # `runs[i] == 0` means `values[i]` is non-zero: zeroing it changes
        # the candidate. Otherwise jump past the whole zero run.
        if skipped == 0:
            return True
        if i + skipped >= end:
            return False
        i += skipped
    return False


def minimize_individual[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence) -> ChoiceSequence:
    """Minimize each choice value in place, left to right.

    For each non-`forced` index, tries values from 0 upward. Failure
    predicates are arbitrary, so a passing value cannot rule out smaller
    values. The working sequence only moves down in shortlex order.
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
        var candidate_value = UInt64(1)
        while candidate_value < current:
            var cand = best.with_value_at(i, candidate_value)
            if is_interesting(cand.copy()):
                best = cand^
                break
            candidate_value += UInt64(1)
    return best^
