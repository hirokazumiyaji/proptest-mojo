"""Shrink passes and loop."""

from proptest.shrink.adaptive import lower_duplicates, redistribute
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
