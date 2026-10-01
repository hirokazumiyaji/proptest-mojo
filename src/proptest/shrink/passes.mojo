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


def _shift_lcp(values: List[UInt64], r: Int) -> List[Int]:
    """`lcp[i]`: common prefix length of `values[i:]` and `values[i + r:]`.

    One backward pass: the match at `i` continues the match at `i + 1`.
    This is what makes candidate ordering cheap; see `_deletion_order`.
    """
    var n = len(values)
    var lcp = List[Int]()
    for _ in range(n):
        lcp.append(0)
    var run = 0
    for i in range(n - r - 1, -1, -1):
        if values[i] == values[i + r]:
            run += 1
            lcp[i] = run
        else:
            run = 0
    return lcp^


def _effective_values(seq: ChoiceSequence) -> List[UInt64]:
    """Values with `forced` nodes reported as zero.

    `ChoiceSequence.zeroed` leaves `forced` nodes alone, so every zeroing
    candidate keeps their values; comparing against 0 makes the order
    agree with the sequences actually emitted.
    """
    var values = seq.values()
    for i in range(len(seq)):
        if seq.nodes[i].forced:
            values[i] = UInt64(0)
    return values^


def _zero_runs(values: List[UInt64]) -> List[Int]:
    """`runs[i]`: number of consecutive zeros starting at `i`."""
    var n = len(values)
    var runs = List[Int]()
    for _ in range(n):
        runs.append(0)
    var run = 0
    for i in range(n - 1, -1, -1):
        if values[i] == UInt64(0):
            run += 1
            runs[i] = run
        else:
            run = 0
    return runs^


def _deletion_order(
    values: List[UInt64], starts: List[Int], r: Int
) -> List[Int]:
    """Order deletion starts by the shortlex value of their candidates.

    Every candidate here drops the same `r` nodes, so all have equal
    length and differ only lexicographically: candidate `start` is
    `values[0:start] ++ values[start + r:]`. Comparing starts `a < b`
    therefore compares `values[a + r:]` against `values[a:]` over
    `[a, b)`, which `lcp[a]` answers in O(1). Ordering a few thousand
    candidates by full sequence comparison instead costs O(n) per
    comparison and makes a long sequence look like a hang.

    Only indices are moved; candidates are materialized afterwards.
    """
    var lcp = _shift_lcp(values, r)
    var order = starts.copy()
    for i in range(1, len(order)):
        var cand = order[i]
        var lo = 0
        var hi = i
        while lo < hi:
            var mid = lo + (hi - lo) // 2
            if _deletion_precedes(values, lcp, r, cand, order[mid]):
                hi = mid
            else:
                lo = mid + 1
        for j in range(i, lo, -1):
            order[j] = order[j - 1]
        order[lo] = cand
    return order^


def _deletion_precedes(
    values: List[UInt64],
    lcp: List[Int],
    r: Int,
    a: Int,
    b: Int,
) -> Bool:
    """Whether the candidate deleting `r` nodes at `a` precedes the one at `b`.

    Symmetric in `a` and `b`, so callers need not pre-order the starts.
    """
    if a == b:
        return False
    var lo_start = a
    var hi_start = b
    if lo_start > hi_start:
        lo_start = b
        hi_start = a
    var shared = lcp[lo_start]
    var gap = hi_start - lo_start
    if shared > gap:
        shared = gap
    if shared == gap:
        # Identical candidates: both tails start at `values[hi_start + r:]`.
        return False
    if values[lo_start + shared + r] < values[lo_start + shared]:
        return lo_start == a
    return hi_start == a


def _zeroing_order(
    values: List[UInt64], starts: List[Int], ends: List[Int], n: Int
) -> List[Int]:
    """Order zeroing starts by the shortlex value of their candidates.

    Candidate `start` blanks `values[start:end]` to zero and keeps the
    full length, so the first differing index against a later start `b`
    is found with `runs` in O(1); the shared region between the two
    blanked windows matches unconditionally.
    """
    var runs = _zero_runs(values)
    var order = List[Int]()
    for i in range(len(starts)):
        order.append(i)
    for i in range(1, len(order)):
        var cand = order[i]
        var lo = 0
        var hi = i
        while lo < hi:
            var mid = lo + (hi - lo) // 2
            if _zeroing_precedes(
                values, runs, starts, ends, n, cand, order[mid]
            ):
                hi = mid
            else:
                lo = mid + 1
        for j in range(i, lo, -1):
            order[j] = order[j - 1]
        order[lo] = cand
    return order^


def _zeroing_precedes(
    values: List[UInt64],
    runs: List[Int],
    starts: List[Int],
    ends: List[Int],
    n: Int,
    ai: Int,
    bi: Int,
) -> Bool:
    """Whether the candidate blanking `starts[ai]:ends[ai]` precedes `bi`.

    A candidate equals `values` with one window replaced by zeros. On the
    region where only the earlier window is blanked the earlier candidate
    holds zeros and the later one holds `values`, so the first non-zero
    in that region decides; between and after the windows the two agree
    except where only the later window is blanked.
    """
    var a = starts[ai]
    var b = starts[bi]
    var wa = ends[ai]
    var wb = ends[bi]
    if a == b:
        if wa == wb:
            return False
        var lo = wa if wa < wb else wb
        var hi = wb if wa < wb else wa
        if lo + runs[lo] < hi:
            # `values[lo:hi]` has a non-zero, kept by whichever candidate
            # blanks the shorter window.
            return wa > wb
        return False

    var first_precedes = True
    if a > b:
        a = b
        wa = wb
        b = starts[ai]
        wb = ends[ai]
        first_precedes = False

    # `[a, min(b, wa))`: this candidate is zero, the other holds values.
    var w = b - a
    if wa - a < w:
        w = wa - a
    var shared = runs[a]
    if shared > w:
        shared = w
    if shared < w:
        return first_precedes

    # Past that region the candidates agree until the later window opens.
    var k = wa if wa > b else b
    while k < wb and values[k] == UInt64(0):
        k += 1
    if k < wb:
        # Only the later candidate zeroes this non-zero, so it is larger.
        return not first_precedes
    return False


def delete_chunks(seq: ChoiceSequence) -> List[ChoiceSequence]:
    """Contiguous-block deletions, simplest-first.

    Tries chunk lengths 8, 4, 2, 1 at every start position and orders
    the surviving candidates by their resulting shortlex value. Deletion
    always shortens the sequence, hence every candidate is
    shortlex-smaller, but neither chunk order nor start order does that
    ranking: deleting size 8 from `[1..10]` yields `[9,10]`, `[1,10]`,
    `[1,2]`, and the shrink loop commits to the first interesting
    candidate, so it would settle on the largest one. Empty results, and
    chunks that would drop any `forced` node, are skipped.

    Candidates dropping the same number of nodes are ordered by index
    (`_deletion_order`); the groups are then emitted shortest first.
    """
    var values = seq.values()
    var n = len(seq)
    var group_sizes = List[Int]()
    var group_starts = List[List[Int]]()
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            var removed = size
            if n - start < removed:
                removed = n - start
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
    for i in range(len(group_sizes)):
        # A group dropping `r` nodes has length `n - r`; shortlex is
        # length-first, so emit the shortest groups first.
        if group_sizes[i] == 0 or group_sizes[i] == n:
            continue
        var ordered = _deletion_order(
            values, group_starts[i].copy(), group_sizes[i]
        )
        for k in range(len(ordered)):
            var start = ordered[k]
            out.append(seq.deleted(start, start + group_sizes[i])^)
    return out^


def zero_chunks(seq: ChoiceSequence) -> List[ChoiceSequence]:
    """Contiguous-block zeroings, simplest-first.

    Same chunk lengths and positions as `delete_chunks`, likewise
    ordered by the resulting shortlex value rather than by chunk size:
    chunk order alone puts size-8 zeroings ahead of the shortlex-smaller
    size-4 zeroings, and the shrink loop commits to the first
    interesting candidate. `forced` nodes keep their value via
    `ChoiceSequence.zeroed`, so chunks that would leave the sequence
    unchanged are skipped: only strictly shortlex-smaller candidates are
    returned.
    """
    # `forced` nodes are never zeroed, so ordering must treat them as
    # already-zero: otherwise a candidate is compared as if it had changed
    # them and the order disagrees with the emitted sequences.
    var values = _effective_values(seq)
    var n = len(seq)
    var starts = List[Int]()
    var ends = List[Int]()
    for size in _chunk_sizes():
        if size > n:
            continue
        for start in range(n - size + 1):
            var end = start + size
            if end > n:
                end = n
            var cand = seq.zeroed(start, end)
            if not is_shortlex_smaller(cand, seq):
                continue
            starts.append(start)
            ends.append(end)
    var out = List[ChoiceSequence]()
    var ordered = _zeroing_order(values, starts.copy(), ends.copy(), n)
    for i in range(len(ordered)):
        var k = ordered[i]
        out.append(seq.zeroed(starts[k], ends[k]))
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
