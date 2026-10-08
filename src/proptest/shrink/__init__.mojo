"""Shrink passes and loop."""

from proptest.shrink.adaptive import lower_duplicates, redistribute
from proptest.shrink.float_passes import simplify_floats
from proptest.shrink.passes import (
    delete_chunks,
    minimize_individual,
    zero_chunks,
)
from proptest.shrink.shrinker import (
    Evaluation,
    ShrinkResult,
    shrink,
    shrink_with,
)
from proptest.shrink.span_passes import (
    delete_spans,
    sort_spans,
    swap_adjacent_spans,
    zero_spans,
)
