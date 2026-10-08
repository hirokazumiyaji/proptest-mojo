"""Property-based testing library for Pure Mojo."""

from proptest.choice import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Span,
    is_shortlex_smaller,
    shortlex_compare,
)
from proptest.database import ExampleDatabase
from proptest.encoding import (
    decode_sequence,
    decode_values,
    encode_sequence,
    encode_values,
)
from proptest.prng import SplitMix64, Xoshiro256StarStar, derive
from proptest.runner import (
    DEFAULT_DATABASE_DIR,
    Settings,
    Verbosity,
    for_all,
)
from proptest.shrink.passes import (
    delete_chunks,
    minimize_individual,
    zero_chunks,
)
from proptest.shrink.span_passes import (
    delete_spans,
    sort_spans,
    swap_adjacent_spans,
    zero_spans,
)
from proptest.shrink.shrinker import (
    Evaluation,
    ShrinkResult,
    shrink,
    shrink_with,
)
from proptest.strategy import Strategy
from proptest.strategies.collections import ListOf, lists
from proptest.strategies.choice import (
    OneOf,
    OneOf2,
    SampledFrom,
    one_of,
    one_of2,
    sampled_from,
)
from proptest.strategies.unique import (
    DictEntry,
    DictList,
    DictOf,
    UniqueListOf,
    dicts,
    unique_lists,
)
from proptest.strategies.primitives import (
    Booleans,
    Integers,
    IntegersOf,
    Just,
    booleans,
    decode_integers_of_choice,
    integers,
    integers_of,
    just,
)
from proptest.strategies.text import (
    Bytes,
    Text,
    bytes,
    decode_codepoint_choice,
    text,
)
from proptest.strategies.tuples import (
    OptionalOf,
    Tuple2,
    Tuple3,
    optionals,
    tuples,
)
from proptest.testcase import DEFAULT_MAX_CHOICES, Status, TestCase

comptime VERSION = "0.1.0"
