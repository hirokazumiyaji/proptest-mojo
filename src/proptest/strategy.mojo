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

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        ...
