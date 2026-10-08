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

- 候補は **再生モード** の `TestCase` で実行する。prefix を使い切った後の選択は 0 になる。
- 採用するのは、評価結果の選択列（実際に消費した分）である。候補より短くなることがある。
候補は残りの評価予算をそのまま `limit` にせず、固定サイズの小さなバッチに分けて生成する。候補 1 個が選択列全体のコピーなので、既定の 5000 評価予算を全部渡すと 8192 choices の入力では1 つ目を確認する前に 4000 万ノード級を保持してしまう。
- 列挙パスは候補列を先に全部作るので、候補 1 個が選択列全体のコピーになる。選択列が 8192 choices に近いと全候補の生成だけで数 GB は必要になり、予算が 1 でも OOM する。よって列挙パスは `limit` を取り、縮小ループは残りの評価予算だけを渡す。
- キャッシュヒットは評価を消費しないので `limit` も消費してはならない。バッチが全てキャッシュヒットだった場合は `limit` を増やして取り直す。さもないと後続の候補に到達できず、予算が残ったまま固定点と報告してしまう。
- 同じ候補を二度評価しないよう、選択値の列をキーに評価結果をキャッシュする。
- 既定では任意の `INTERESTING` を採用する（失敗メッセージの一致は要求しない）。

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
| `minimize_individual` | Adaptive | Replace each choice with 0, then minimize by binary search if that fails | `x = 1000` → `x = 101` | M1 |
| `delete_spans` | Enumeration | Delete whole spans, starting with deeper spans | Remove a list element | M3 |
| `zero_spans` | Enumeration | Set every choice in a span to 0 | Simplify an element to its simplest value | M3 |
| `sort_spans` | Enumeration | Sort sibling spans with the same label and depth by their choice sequences | `[3, 1, 2]` → `[1, 2, 3]` | M3 |
| `swap_adjacent_spans` | Enumeration | Swap adjacent spans with the same label | Partial reordering | M3 |
| `redistribute` | Adaptive | Decrease one of two integer choices while increasing the other | Reduce `x + y > 10` to `x = 0, y = 11` | M3 |
| `lower_duplicates` | Adaptive | Lower multiple choices with identical values together | Counterexamples that require `x == y` | M3 |
| `simplify_floats` | Adaptive | Simplify floating-point choices toward integers and simple fractions | `1.3927...` → `1.0` | M3 |

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
