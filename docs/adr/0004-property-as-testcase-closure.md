# ADR-0004: Property を `def(mut TestCase) raises` のクロージャで表現する

- 状態: Accepted
- 日付: 2026-09-26
- 関連: [specs/runner.md](../specs/runner.md)

## 文脈

テスト対象の性質（property）をどんな関数型で受け取るかを決める必要がある。
候補は次の 2 つ。

1. **値を受け取る形**（proptest / Hypothesis の `@given`）: `for_all(strategy, prop)` で `prop: def(S.Value) raises`。
2. **TestCase を受け取る形**（Hypothesis の `data()` / `st.data()`）: `for_all(prop)` で `prop: def(mut TestCase) raises`。property の中で `tc.draw(strategy)` を呼ぶ。

スパイクの結果、1 は現行コンパイラで通らなかった。
捕捉クロージャの型パラメータ `P: def(S.Value) raises -> None` に関連型 `S.Value` が含まれると、`def(xs: List[Int]) raises -> None` が `def(S.Value) raises -> None` に適合しないと判定される。
2 は依存型を含まないため、捕捉クロージャのまま問題なく動作した。

## 決定

- property は `def(mut TestCase) raises -> None` に適合するクロージャとし、ランナーは `for_all[P: def(mut TestCase) raises -> None](prop: P, settings: Settings = Settings())` の形で受け取る。
- 値は property 内で `tc.draw(strategy, label)` によって取り出す。
- property はローカル変数を捕捉してよい（`{imm x}` など）。

## 検討した代替案

- 値を受け取る形: 上記の型推論の制約で実装できない。コンパイラが改善されたら、薄いラッパー（`for_all(strategy, prop)`）を追加で提供することを別 ADR で検討する。

## 結果

- 前に引いた値に応じて次の Strategy を選ぶ依存的な生成が、`flat_map` なしで普通のコードとして書ける。
- 反例の表示は `tc.draw` 時に記録したラベルと値の `Writable` 表現から組み立てる。
- `assume` や `note` などのテスト中の操作も `tc` のメソッドとして自然に提供できる。
- 引数の数が固定されないため、`@given(a=..., b=...)` のような宣言的な書き方はできない。
