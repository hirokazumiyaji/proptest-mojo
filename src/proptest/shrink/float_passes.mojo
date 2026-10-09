"""Adaptive float simplification pass over choice sequences.

Per `docs/specs/shrinking.md` (`simplify_floats`, M3), float choices use
the lexicographic magnitude encoding from `strategies/floats.mojo`, so a
smaller code is a smaller non-negative magnitude. This pass moves each
non-`forced` `FLOAT` choice down in shortlex order: it tries `0.0`, then
integer truncation toward zero, then small-denominator fractions, and
finally refines with binary search on the lex code. The result is
shortlex-smaller-or-equal to the input.
"""

from std.math import isinf, isnan

from proptest.choice import ChoiceKind, ChoiceSequence
from proptest.strategies.floats import float_to_lex, lex_to_float

comptime SAFE_INT_FLOAT = Float64(9007199254740992.0)


def _denominators() -> List[Int]:
    """Denominators tried simplest-first; 1 is integer truncation."""
    var ds: List[Int] = [1, 2, 3, 4, 5, 8, 10, 16]
    return ds^


def _refine_lex[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence, index: Int) -> ChoiceSequence:
    """Binary search for the smallest interesting lex code at `index`.

    `UInt64(0)` is assumed uninteresting (callers try it first), so the
    loop only probes midpoints strictly below the current best.
    """
    var best = seq.copy()
    var hi = best.nodes[index].value
    var lo = UInt64(0)
    while hi - lo > UInt64(1):
        var mid = (lo + hi) // UInt64(2)
        var cand = best.with_value_at(index, mid)
        if is_interesting(cand.copy()):
            hi = mid
            best = cand^
        else:
            lo = mid
    return best^


def _simplify_one_at[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence, index: Int) -> ChoiceSequence:
    """Simplify the single `FLOAT` choice at `index`, moving only down."""
    var best = seq.copy()
    var current = best.nodes[index].value
    if current == UInt64(0):
        return best^
    var zeroed = best.with_value_at(index, UInt64(0))
    if is_interesting(zeroed.copy()):
        return zeroed^
    var value = lex_to_float(current)
    if isnan(value) or isinf(value) or value >= SAFE_INT_FLOAT:
        return _refine_lex[is_interesting](best^, index)
    for d in _denominators():
        var scaled = value * Float64(d)
        if scaled >= SAFE_INT_FLOAT:
            continue
        var floored = Float64(Int(scaled)) / Float64(d)
        if not (floored < value) or floored < 0.0:
            continue
        var fcode = float_to_lex(floored)
        if fcode >= current or fcode == UInt64(0):
            continue
        var cand = best.with_value_at(index, fcode)
        if is_interesting(cand.copy()):
            best = cand^
            current = fcode
            value = floored
    return _refine_lex[is_interesting](best^, index)


def simplify_floats[
    is_interesting: def(ChoiceSequence) thin -> Bool
](seq: ChoiceSequence) -> ChoiceSequence:
    """Simplify every `FLOAT` choice toward integers and simple fractions.

    For each non-`forced` `FLOAT` node, left to right: tries `0.0`,
    integer truncation, small-denominator fractions, then binary search
    for the smallest interesting lex code. Non-`FLOAT` and `forced`
    nodes are untouched, so the result is shortlex-smaller-or-equal.
    """
    var best = seq.copy()
    var n = len(best)
    for i in range(n):
        if best.nodes[i].forced:
            continue
        if best.nodes[i].kind != ChoiceKind.FLOAT:
            continue
        if best.nodes[i].value == UInt64(0):
            continue
        var updated = _simplify_one_at[is_interesting](best.copy(), i)
        best = updated^
    return best^
