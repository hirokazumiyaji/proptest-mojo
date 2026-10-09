# Shrinking

See [ADR-0002](../adr/0002-choice-sequence-based-shrinking.md) and [ADR-0008](../adr/0008-functional-core-imperative-shell.md).

## Goal

Given a failing choice sequence `s`, find an `s'` such that:

1. Running the property with `s'` produces `INTERESTING`.
2. `s' < s` in shortlex order.

Repeat until reaching a fixed point (no pass can improve the sequence) or exhausting the budget. Since shortlex is well-ordered, shrinking always terminates.

## Evaluation

The runner (the imperative shell) evaluates candidates.

```mojo
def evaluate(candidate: ChoiceSequence) -> Evaluation   # status and the choices actually consumed
```

- Evaluate candidates with a TestCase in replay mode. Choices after the prefix is exhausted are 0.
- Adopt the choice sequence from the evaluation result (the choices actually consumed); it may be shorter than the candidate.
- Generate candidates in small, fixed-size batches. Each candidate copies the full sequence, so materializing all 5000 default evaluations for 8192 choices would retain roughly 40 million nodes before checking the first candidate.
- Enumeration passes accept a limit to bound eager candidate creation. Without it, generating all candidates for a near-8192-choice sequence could require several gigabytes, even with an evaluation budget of one.
- Cache hits do not consume evaluations or the batch limit. When a batch contains only cache hits, request the next page so later uncached candidates are reached.
- Cache evaluation results by choice values to avoid evaluating the same candidate twice.
- By default, adopt any INTERESTING result; the failure message does not have to match.

## Pass types

Shrinking passes belong to the functional core and have two forms:

| Type | Conceptual signature | Examples |
|------|----------------------|----------|
| Enumeration pass | Pure function `(seq, spans) -> List[ChoiceSequence]` that returns candidates in simplicity order | Deletion, zeroing, sorting |
| Adaptive pass | Higher-order function accepting an `is_interesting` evaluator; each next candidate depends on earlier results, as in binary search | Minimizing individual values, redistributing values |

Candidates are ordered by resulting shortlex order, not by generation order.

Enumeration passes accept `limit`, which the shrinking loop sets to the remaining evaluation budget. Each candidate copies the entire choice sequence, so without `limit`, generating all candidates for a sequence near 8192 choices could require several gigabytes. `zero_chunks` checks whether a range contains any non-zero values before creating a candidate and discards ranges that do not. Discarding after creation would copy the entire zeroed sequence once per range. The shrinking loop adopts the first interesting candidate and restarts from the first pass. Ordering candidates by range length or start position can therefore commit to larger values among candidates of equal length. For example, deleting a range of length 8 from `[1..10]` produces `[9,10]`, `[1,10]`, `[1,2]`; the correct shortlex order is `[1,2]`, `[1,10]`, `[9,10]`.

Ordering compares only start indices, not whole candidate sequences, in O(1). Candidates deleting the same number of nodes have equal lengths, so comparing candidates for a `start` and `size` is equivalent to lexicographically comparing `values[0:start] ++ values[start + size:]`. The Z-array of `values` (`_shift_lcp`) determines this in O(1). For zeroing, `_zero_runs` similarly finds the first non-zero position in O(1). Comparing whole candidates costs O(n) per comparison; with O(n) candidates, sequences near 8192 choices caused practical hangs. Sort indices with bottom-up merge sort rather than binary insertion sort. For monotonically increasing sequences, each new candidate belongs at the beginning, making insertion-sort index movement O(n²). Merge sort moves only indices in O(n log n), and candidates are created after their order is determined.

Adaptive passes only receive the evaluator as an injected function and have no other side effects. Tests pass a pure predicate as the evaluator.

## Passes

Apply passes in order and restart from the first pass whenever one improves the sequence.

| Pass | Type | Operation | Example effect | M |
|------|------|-----------|----------------|---|
| `delete_chunks` | Enumeration | Delete contiguous ranges of lengths 8, 4, 2, and 1; order results by shortlex | Remove extra choices | M1 |
| `zero_chunks` | Enumeration | Set contiguous ranges of lengths 8, 4, 2, and 1 to 0; order results by shortlex | Simplify several values at once | M1 |
| `minimize_individual` | Adaptive | Replace each choice with 0, then enumerate smaller values in increasing order. `FLOAT` choices use geometric probes, ascending fill (full range when the current code is small), fraction probes, and binary search on magnitude codes instead of raw ascending enumeration over huge codes | `x = 1000` → `x = 101`; `2.0` → `1.5` | M1 |
| `delete_spans` | Enumeration | Delete whole spans, starting with deeper spans | Remove a list element | M3 |
| `zero_spans` | Enumeration | Set every choice in a span to 0 | Simplify an element to its simplest value | M3 |
| `sort_spans` | Enumeration | Sort sibling spans with the same label and depth by their choice sequences | `[3, 1, 2]` → `[1, 2, 3]` | M3 |
| `swap_adjacent_spans` | Enumeration | Swap adjacent spans with the same label | Partial reordering | M3 |
| `redistribute` | Adaptive | Decrease one of two integer choices while increasing the other | Reduce `x + y > 10` to `x = 0, y = 11` | M3 |
| `lower_duplicates` | Adaptive | Lower multiple choices with identical values together | Counterexamples that require `x == y` | M3 |
| `simplify_floats` | Adaptive | Standalone float simplification toward integers and simple fractions; the shrink loop applies the same float-aware search inside `minimize_individual` so `for_all` benefits within the shared evaluation budget | `1.3927...` → `1.0` | M3 |

No pass modifies a `forced` choice.

## Budget and termination

| Setting | Default | Meaning |
|---------|---------|---------|
| `Settings.max_shrink_evaluations` | 5000 | Maximum number of property executions during shrinking |

When the limit is reached, report the best choice sequence found so far and indicate in the report that shrinking stopped at the budget limit.

## Quality validation

Add regression tests under `tests/shrink_quality/` for problems where Hypothesis is known to find a minimal counterexample, and verify that equivalent results are obtained (M3).

| Problem | Expected minimal counterexample |
|---------|---------------------------------|
| `sum(xs) <= 1000` (`xs: List[Int]`, elements 0..1000) | `[1, 1000]` (two elements are shortest because each element is at most 1000) |
| `x < 1000` | `x = 1000` |
| `len(xs) < 3` | `[0, 0, 0]` |
| `xs` is not sorted in ascending order | `[1, 0]` |
| `x + y <= 10` | `x = 0, y = 11` |
| String does not contain `"a"` | `"a"` |
