# ADR-0002: 選択列（choice sequence）ベースの内部縮小を採用する

- 状態: Accepted
- 日付: 2026-09-26
- 関連: [specs/choice-sequence.md](../specs/choice-sequence.md)、[specs/shrinking.md](../specs/shrinking.md)

## 文脈

Property-based testing の品質は、反例を人間が読める最小形まで縮める能力でほぼ決まる。
縮小の方式には大きく 3 系統がある。

1. **型ごとの縮小関数**（QuickCheck）: 値 `T` から候補 `List[T]` を返す `shrink` を型ごとに書く。`map` した値は縮小できず、生成時の不変条件を縮小候補が破りうる。
2. **値ツリー**（proptest の `ValueTree`）: 生成時に「縮小可能な値」を作り、`simplify` / `complicate` で探索する。`map` は扱えるが `flat_map` の縮小が弱く、Strategy ごとに ValueTree 型を実装する必要がある。
3. **内部縮小**（Hypothesis の Conjecture）: 生成器が消費した乱択の列（選択列）を記録し、値ではなく選択列を縮小して再生成する。縮小は型に依存しない。

Mojo 固有の制約として、型消去されたクロージャやトレイトオブジェクトが使いにくい（[ADR-0003](0003-strategy-trait-with-static-dispatch.md)、[ADR-0005](0005-thin-functions-as-comptime-parameters.md)）。
Strategy ごとに縮小ロジックと ValueTree 型を持たせる方式は、ジェネリック型の組み合わせ爆発を招く。

スパイクで、選択列を記録する `TestCase`・Strategy トレイト・捕捉クロージャの property・単純な縮小ループを組み合わせ、`List[Int]` の反例が縮小されることを確認した。

## 決定

Hypothesis 方式の内部縮小を採用する。

- すべての乱択は `TestCase` を経由し、選択列 `ChoiceSequence`（型付きの選択ノードの列）として記録する。
- Strategy は「選択列から値を作る決定的な関数」とする。縮小ロジックを持たない。
- 縮小器は選択列だけを操作し、候補の選択列で property を再実行して「より単純で、かつ失敗する」ものを採用する。
- 単純さの順序は shortlex（短いほど単純、同じ長さなら各選択値の辞書順）とする。

## 検討した代替案

- proptest 方式の値ツリー: Strategy ごとに ValueTree 型が必要で、Mojo では型の組み合わせが肥大化する。`flat_map` や `filter` の縮小品質も内部縮小に劣る。
- QuickCheck 方式の型ごとの縮小: `map` / `filter` 後の値を正しく縮小できず、要件（Hypothesis・proptest に匹敵）を満たさない。

## 結果

- `map`・`filter`・`flat_map`・ユーザー定義の合成 Strategy が、追加実装なしで縮小可能になる。
- 縮小品質は縮小パス（削除・ゼロ化・二分探索・並べ替えなど）の出来で決まる。構造を意識した縮小のために選択列上に span（区間ラベル）を記録する必要がある。
- 縮小候補ごとに property を再実行するため、property の実行コストが縮小時間に直結する。試行済み選択列のキャッシュで緩和する。
- 選択列をそのままシリアライズすれば、反例の再現と永続化（example database）ができる。
