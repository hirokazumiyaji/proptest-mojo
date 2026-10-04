"""The Strategy trait: deterministic value generation from a TestCase.

Implements the `Strategy` section of `docs/specs/strategies.md`
(ADR-0003, ADR-0005, ADR-0008).

A Strategy is an immutable value describing how to build one value from
the choices recorded in a `TestCase`. Generation is deterministic in the
recorded choices alone, so shrinking and replay only need the choice
sequence. Combinators are free functions (not trait methods) because the
compiler cannot express dependent function parameters in default methods.
"""

from proptest.testcase import TestCase


trait Strategy(Copyable, Deinitable):
    """Immutable recipe turning recorded choices into a value.

    Every implementation follows these conventions: determinism in the
    choice sequence alone, smaller choices yield simpler values (all-zero
    choices draw the simplest value), `draw` never mutates `self`, and
    each draw happens inside the span opened by `TestCase.draw`.
    """

    comptime Value: Copyable & Writable & Deinitable

    def span_label(self) -> UInt64:
        """Structural span label identifying the strategy kind.

        `TestCase.draw` records this label on the span it opens, and the
        shrink passes reorder blocks that share a label. It must depend on
        the strategy kind alone: reusing a *reporting* label for two
        different strategies would let a pass swap structurally
        incompatible blocks.

        Required rather than defaulted: a shared default would give every
        strategy that omits it the same label, and two such strategies as
        sibling draws would again look interchangeable. Implement it as
        `kind_label("<kind>")`. A combinator may propagate its wrapped
        strategy's label only when it preserves the choice structure; a
        structure-changing combinator needs its own label.
        """
        ...

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        ...


def kind_label(kind: StringSlice) -> UInt64:
    """FNV-1a hash of a strategy kind name, used as a span label."""
    var hash = UInt64(14695981039346656037)
    for b in kind.as_bytes():
        hash = (hash ^ UInt64(b)) * UInt64(1099511628211)
    return hash
