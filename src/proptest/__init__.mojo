"""Property-based testing library for Pure Mojo."""

from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
    shortlex_compare,
)
from proptest.prng import SplitMix64, Xoshiro256StarStar, derive
from proptest.runner import Settings, for_all
from proptest.shrink.passes import (
    delete_chunks,
    minimize_individual,
    zero_chunks,
)
from proptest.shrink.span_passes import delete_spans, zero_spans
from proptest.shrink.shrinker import (
    Evaluation,
    ShrinkResult,
    shrink,
    shrink_with,
)
from proptest.strategy import Strategy
from proptest.strategies.collections import ListOf, lists
from proptest.strategies.primitives import (
    Booleans,
    Integers,
    Just,
    booleans,
    decode_integer_choice,
    integers,
    just,
)
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase

comptime VERSION = "0.1.0"
