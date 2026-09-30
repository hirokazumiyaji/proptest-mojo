# Strategy 一覧

Strategy は「値の生成方法を表す不変の値」です。`tc.draw` に渡して使います。
共通の規約 (決定性・単純さの単調性・不変性・局所性) は
[Specs: Strategy](../specs/strategies.md) を参照してください。

## 使えるもの

| 関数 | 値の型 | 縮小の目標 |
|------|--------|-----------|
| `integers(min, max)` | `Int` | 範囲内で 0 に最も近い値 |
| `booleans()` | `Bool` | `False` |
| `just(value)` | `T` | (選択を消費しない定数) |
| `map[f](s)` | 変換後の型 | ベース Strategy を通じて縮小 |
| `filter[p](s)` | `s` と同じ型 | 条件を満たす最も単純な値 |
| `flat_map[f](s)` | 内側 Strategy の値の型 | 外側・内側の両方を通じて縮小 |

```mojo
from proptest import Integers, booleans, integers, just
from proptest.strategies.combinators import filter, flat_map, map

var any_int = integers(-100, 100)  # raises: max < min なら Error
var flag = booleans()
var constant = just(42)
```

`map` / `filter` / `flat_map` の使い方と自作の合成 Strategy については
[composition](composition.md) を参照してください。

## 計画中のもの

次の Strategy は M2 以降で計画中です。API 形は
[Specs: Strategy](../specs/strategies.md) の表が最新です。

- 数値・真偽の拡張: `integers_of[dtype]`、`floats`
- 文字列・バイト列: `text`、`bytes`
- コレクション: `lists`、`unique_lists`、`dicts`
- 構造: `tuples`、`optionals`、`one_of`、`sampled_from`
- 高度な生成: 再帰的データ、`Arbitrary` トレイト、`tc.target`

コレクションが必要な今は、[composition](composition.md) の合成 Strategy
struct パターンで自作してください。動く例が
[`examples/lists.mojo`](../../examples/lists.mojo) にあります。
