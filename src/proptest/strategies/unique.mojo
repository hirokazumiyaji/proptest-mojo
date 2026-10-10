"""Unique collections: distinct-element lists and list-backed dicts.

Implements the `unique_lists` and `dicts` rows of `docs/specs/strategies.md`
(ADR-0003, ADR-0005, ADR-0008).

`std.Dict` cannot be returned by value from a generic `draw` in this
compiler version (its move constructor needs `KeyElement` evidence the
caller cannot supply for an associated type), so `dicts` draws `DictList`,
a list of pairs with unique keys and `Writable` rendering.

Like `lists`, each entry draws a continue flag inside its own span, so
span deletion removes one entry. A duplicate candidate is drawn inside a
nested attempt span recorded as `discarded`. An entry that finds no fresh
key within `_MAX_DUPLICATE_ATTEMPTS` tries ends the collection early, or
marks the example `INVALID` below `min_size`. Smaller choices yield
shorter collections of simpler elements.
"""

from std.io import Writer
from std.math import max

from proptest.strategies.collections import _default_average_size
from proptest.strategies.combinators import _truncate_draw_records
from proptest.strategy import Strategy, kind_label
from proptest.testcase import TestCase

comptime _UNIQUE_ELEMENT_LABEL = UInt64(0x756E6971456C656D)
comptime _UNIQUE_ATTEMPT_LABEL = UInt64(0x756E697154727921)
comptime _DICT_ENTRY_LABEL = UInt64(0x64696374456E7472)
comptime _DICT_ATTEMPT_LABEL = UInt64(0x6469637454727921)
comptime _MAX_DUPLICATE_ATTEMPTS = 32


@fieldwise_init
struct DictEntry[
    K: Copyable & Equatable & Writable & Deinitable,
    V: Copyable & Writable & Deinitable,
](Copyable, Deinitable, Movable, Writable):
    """One key/value pair stored in a `DictList`."""

    var key: Self.K
    var value: Self.V

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.key, ": ", self.value)


@fieldwise_init
struct DictList[
    K: Copyable & Equatable & Writable & Deinitable,
    V: Copyable & Writable & Deinitable,
](Copyable, Deinitable, Movable, Sized, Writable):
    """List of pairs with unique keys, drawn by `dicts`.

    Keys stay unique by construction, so lookup is a linear scan. This
    keeps the value type generic over any `Equatable` key without the
    `KeyElement` evidence `std.Dict` demands.
    """

    var entries: List[DictEntry[Self.K, Self.V]]

    def __init__(out self):
        self.entries = List[DictEntry[Self.K, Self.V]]()

    def __len__(self) -> Int:
        return len(self.entries)

    def _find(self, key: Self.K) -> Int:
        """Index of the entry under `key`, or `-1` when absent."""
        for i in range(len(self.entries)):
            if self.entries[i].key == key:
                return i
        return -1

    def contains(self, key: Self.K) -> Bool:
        """Whether `key` is already present."""
        return self._find(key) >= 0

    def __getitem__(self, key: Self.K) raises -> Self.V:
        """Copy of the value stored under `key`; raises when absent."""
        var i = self._find(key)
        if i < 0:
            raise Error("DictList: key not found")
        return self.entries[i].value.copy()

    def keys(self) -> List[Self.K]:
        """Keys in insertion order."""
        var out = List[Self.K]()
        for i in range(len(self.entries)):
            out.append(self.entries[i].key.copy())
        return out^

    def values(self) -> List[Self.V]:
        """Values in insertion order."""
        var out = List[Self.V]()
        for i in range(len(self.entries)):
            out.append(self.entries[i].value.copy())
        return out^

    def write_to(self, mut writer: Some[Writer]):
        writer.write("{")
        for i in range(len(self.entries)):
            if i > 0:
                writer.write(", ")
            writer.write(self.entries[i])
        writer.write("}")


@fieldwise_init
struct UniqueListOf[E: Strategy](Strategy) where conforms_to(
    E.Value, Equatable
):
    """Lists of distinct `elements` with length in `[min_size, max_size]`."""

    comptime Value = List[Self.E.Value]
    var elements: Self.E
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def span_label(self) -> UInt64:
        return kind_label("unique_lists")

    def draw(
        self, mut tc: TestCase
    ) raises -> List[Self.E.Value] where conforms_to(Self.E.Value, Equatable):
        if self.min_size < 0:
            raise Error("unique_lists: min_size must be >= 0")
        if self.max_size < self.min_size:
            raise Error("unique_lists: max_size must be >= min_size")
        var out = List[Self.E.Value]()
        var p_continue: Float64 = 0.0
        var optional_average = max(
            self.average_size - Float64(self.min_size), 0.0
        )
        if optional_average > 0.0:
            p_continue = optional_average / (1.0 + optional_average)
        while True:
            var cont: Bool
            tc.start_span(_UNIQUE_ELEMENT_LABEL)
            try:
                if len(out) >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif len(out) < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
            except e:
                tc.stop_span(discard=True)
                raise e
            if not cont:
                tc.stop_span(discard=True)
                break

            var placed = False
            for _attempt in range(_MAX_DUPLICATE_ATTEMPTS):
                var labels = len(tc.draw_labels)
                var values = len(tc.draw_values)
                tc.start_span(_UNIQUE_ATTEMPT_LABEL)
                try:
                    var candidate = self.elements.draw(tc)
                    var duplicate = False
                    for i in range(len(out)):
                        if out[i] == candidate:
                            duplicate = True
                            break
                    if duplicate:
                        tc.stop_span(discard=True)
                        _truncate_draw_records(tc, labels, values)
                        continue
                    tc.stop_span()
                    out.append(candidate^)
                    placed = True
                    break
                except e:
                    tc.stop_span(discard=True)
                    _truncate_draw_records(tc, labels, values)
                    tc.stop_span(discard=True)
                    raise e

            if placed:
                tc.stop_span()
            else:
                tc.stop_span(discard=True)
                if len(out) >= self.min_size:
                    break
                tc.assume(False)
        return out^


def unique_lists[
    E: Strategy
](
    var elements: E,
    min_size: Int = 0,
    max_size: Int = 32,
    average_size: Float64 = -1.0,
) raises -> UniqueListOf[E] where conforms_to(E.Value, Equatable):
    """Strategy drawing `List[E.Value]` with distinct elements.

    Length stays in `[min_size, max_size]`. Duplicate candidates are
    retried inside `discarded` attempt spans, at most
    `_MAX_DUPLICATE_ATTEMPTS` per element; an unsatisfiable `min_size`
    marks the example `INVALID`. A negative `average_size` selects the
    spec default. Raises when the bounds are empty.
    """
    if min_size < 0:
        raise Error("unique_lists: min_size must be >= 0")
    if max_size < min_size:
        raise Error("unique_lists: max_size must be >= min_size")
    var avg = average_size
    if avg < 0.0:
        avg = _default_average_size(min_size, max_size)
    return UniqueListOf[E](elements^, min_size, max_size, avg)


@fieldwise_init
struct DictOf[K: Strategy, V: Strategy](Strategy) where conforms_to(
    K.Value, Equatable
):
    """`DictList` of `keys` to `values` with size in `[min_size, max_size]`."""

    comptime Value = DictList[Self.K.Value, Self.V.Value]
    var keys: Self.K
    var values: Self.V
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def span_label(self) -> UInt64:
        return kind_label("dict_of")

    def draw(
        self, mut tc: TestCase
    ) raises -> DictList[Self.K.Value, Self.V.Value] where conforms_to(
        Self.K.Value, Equatable
    ):
        if self.min_size < 0:
            raise Error("dicts: min_size must be >= 0")
        if self.max_size < self.min_size:
            raise Error("dicts: max_size must be >= min_size")
        var out = DictList[Self.K.Value, Self.V.Value]()
        var p_continue: Float64 = 0.0
        var optional_average = max(
            self.average_size - Float64(self.min_size), 0.0
        )
        if optional_average > 0.0:
            p_continue = optional_average / (1.0 + optional_average)
        while True:
            var cont: Bool
            tc.start_span(_DICT_ENTRY_LABEL)
            try:
                if len(out) >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif len(out) < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
            except e:
                tc.stop_span(discard=True)
                raise e
            if not cont:
                tc.stop_span(discard=True)
                break

            var placed = False
            for _attempt in range(_MAX_DUPLICATE_ATTEMPTS):
                var labels = len(tc.draw_labels)
                var values = len(tc.draw_values)
                tc.start_span(_DICT_ATTEMPT_LABEL)
                try:
                    var key = self.keys.draw(tc)
                    if out.contains(key):
                        tc.stop_span(discard=True)
                        _truncate_draw_records(tc, labels, values)
                        continue
                    var value = self.values.draw(tc)
                    out.entries.append(
                        DictEntry[Self.K.Value, Self.V.Value](key^, value^)
                    )
                    tc.stop_span()
                    placed = True
                    break
                except e:
                    tc.stop_span(discard=True)
                    _truncate_draw_records(tc, labels, values)
                    tc.stop_span(discard=True)
                    raise e

            if placed:
                tc.stop_span()
            else:
                tc.stop_span(discard=True)
                if len(out) >= self.min_size:
                    break
                tc.assume(False)
        return out^


def dicts[
    K: Strategy, V: Strategy
](
    var keys: K,
    var values: V,
    min_size: Int = 0,
    max_size: Int = 32,
    average_size: Float64 = -1.0,
) raises -> DictOf[K, V] where conforms_to(K.Value, Equatable):
    """Strategy drawing `DictList[K.Value, V.Value]` with distinct keys.

    Size stays in `[min_size, max_size]`. A value is drawn only for an
    accepted key, so rejected keys cost no value choices. Duplicate keys
    are retried inside `discarded` attempt spans, at most
    `_MAX_DUPLICATE_ATTEMPTS` per entry; an unsatisfiable `min_size`
    marks the example `INVALID`. A negative `average_size` selects the
    spec default. Raises when the bounds are empty.
    """
    if min_size < 0:
        raise Error("dicts: min_size must be >= 0")
    if max_size < min_size:
        raise Error("dicts: max_size must be >= min_size")
    var avg = average_size
    if avg < 0.0:
        avg = _default_average_size(min_size, max_size)
    return DictOf[K, V](keys^, values^, min_size, max_size, avg)
