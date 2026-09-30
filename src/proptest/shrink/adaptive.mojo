"""Adaptive shrink passes: value redistribution and duplicate lowering.

Per `docs/specs/shrinking.md`, adaptive passes take a pure
`is_interesting` predicate as a comptime thin function (ADR-0005).
They have no side effects beyond the injected predicate, so tests pass
pure predicates directly.

Both passes only move down in shortlex order and never touch `forced`
choices, so repeated application always terminates.
"""

from proptest.choice import ChoiceKind, ChoiceSequence


def redistribute[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence) -> ChoiceSequence:
    """Move value from an earlier integer choice to a later one.

    For each ordered pair `i < j` of non-`forced` integer choices,
    lowers `i` as much as possible while raising `j` only as much as
    needed to stay interesting. Lowering the earlier index always makes
    the sequence shortlex-smaller, no matter how much the later index
    grows, so every adoption is strictly simpler.

    The classic case is a sum predicate: `minimize_individual` alone
    turns `(5, 7)` with `x + y > 10` into `(4, 7)`, while this pass
    finds `(0, 11)`.
    """
    var best = seq.copy()
    if not is_interesting(best.copy()):
        return best^
    while True:
        var improved = False
        var n = len(best)
        for i in range(n):
            if improved:
                break
            if best.nodes[i].forced:
                continue
            if best.nodes[i].kind != ChoiceKind.INTEGER:
                continue
            for j in range(i + 1, n):
                if best.nodes[j].forced:
                    continue
                if best.nodes[j].kind != ChoiceKind.INTEGER:
                    continue
                var a = best.nodes[i].value
                var b = best.nodes[j].value
                var max_j = best.nodes[j].max_value
                if a == UInt64(0):
                    continue
                if b >= max_j:
                    continue
                var tmp0 = best.with_value_at(i, UInt64(0))
                var probe0max = tmp0.with_value_at(j, max_j)
                if is_interesting(probe0max.copy()):
                    var jstar: UInt64
                    var tmp0z = best.with_value_at(i, UInt64(0))
                    var probe0z = tmp0z.with_value_at(j, UInt64(0))
                    if is_interesting(probe0z.copy()):
                        jstar = UInt64(0)
                    else:
                        var lo = UInt64(0)
                        var hi = max_j
                        while hi - lo > UInt64(1):
                            var mid = lo + (hi - lo) // UInt64(2)
                            var tm = best.with_value_at(i, UInt64(0))
                            var pr = tm.with_value_at(j, mid)
                            if is_interesting(pr.copy()):
                                hi = mid
                            else:
                                lo = mid
                        jstar = hi
                    var t0b = best.with_value_at(i, UInt64(0))
                    var cand0 = t0b.with_value_at(j, jstar)
                    best = cand0^
                    improved = True
                    break
                else:
                    var lo = UInt64(0)
                    var hi = a
                    while hi - lo > UInt64(1):
                        var mid = lo + (hi - lo) // UInt64(2)
                        var tm = best.with_value_at(i, mid)
                        var pr = tm.with_value_at(j, max_j)
                        if is_interesting(pr.copy()):
                            hi = mid
                        else:
                            lo = mid
                    if hi < a:
                        var jstar: UInt64
                        var thiz = best.with_value_at(i, hi)
                        var probez = thiz.with_value_at(j, UInt64(0))
                        if is_interesting(probez.copy()):
                            jstar = UInt64(0)
                        else:
                            var lo2 = UInt64(0)
                            var hi2 = max_j
                            while hi2 - lo2 > UInt64(1):
                                var mid2 = lo2 + (hi2 - lo2) // UInt64(2)
                                var tm2 = best.with_value_at(i, hi)
                                var pr2 = tm2.with_value_at(j, mid2)
                                if is_interesting(pr2.copy()):
                                    hi2 = mid2
                                else:
                                    lo2 = mid2
                            jstar = hi2
                        var th = best.with_value_at(i, hi)
                        var candh = th.with_value_at(j, jstar)
                        best = candh^
                        improved = True
                        break
        if not improved:
            break
    return best^


def lower_duplicates[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence) -> ChoiceSequence:
    """Lower same-valued choices together.

    Collects groups of non-`forced` choices sharing one value and lowers
    each group as a whole, trying 0 first and falling back to binary
    search for the smallest interesting value. Lowering a group always
    makes the sequence shortlex-smaller.

    The classic case is an equality predicate: `minimize_individual`
    cannot move `(500, 500)` with `x == y and x > 100` at all, while
    this pass finds `(101, 101)`.
    """
    var best = seq.copy()
    if not is_interesting(best.copy()):
        return best^
    while True:
        var improved = False
        var n = len(best)
        var seen = List[UInt64]()
        for i in range(n):
            if improved:
                break
            if best.nodes[i].forced:
                continue
            var v = best.nodes[i].value
            if v == UInt64(0):
                continue
            var already = False
            for k in range(len(seen)):
                if seen[k] == v:
                    already = True
                    break
            if already:
                continue
            var group = List[Int]()
            for k in range(n):
                if best.nodes[k].forced:
                    continue
                if best.nodes[k].value == v:
                    group.append(k)
            seen.append(v)
            if len(group) < 2:
                continue
            var cand0 = best.copy()
            for g in range(len(group)):
                cand0 = cand0.with_value_at(group[g], UInt64(0))
            if is_interesting(cand0.copy()):
                best = cand0^
                improved = True
                break
            else:
                var lo = UInt64(0)
                var hi = v
                while hi - lo > UInt64(1):
                    var mid = lo + (hi - lo) // UInt64(2)
                    var probe = best.copy()
                    for g in range(len(group)):
                        probe = probe.with_value_at(group[g], mid)
                    if is_interesting(probe.copy()):
                        hi = mid
                    else:
                        lo = mid
                if hi < v:
                    var candh = best.copy()
                    for g in range(len(group)):
                        candh = candh.with_value_at(group[g], hi)
                    best = candh^
                    improved = True
                    break
        if not improved:
            break
    return best^
