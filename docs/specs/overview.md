# 概要

## 目的

Pure Mojo で、Python の Hypothesis と Rust の proptest に匹敵する Property-based testing（PBT）ライブラリを提供する。

「匹敵する」を次の 3 点で定義する。

1. **表現力**: 基本型・コレクション・文字列・浮動小数点数の Strategy と、`map` / `filter` / `flat_map` / 合成 Strategy / 状態機械テストで、実用的なテストデータを組み立てられる。
2. **縮小品質**: 失敗時に、人間がそのまま読める最小の反例を自動で得られる。`map`・`filter`・依存的な生成を経ても縮小が効く。
3. **再現性**: 反例をシードと選択列で完全に再現でき、一度見つけた反例は次回実行で最初に再試行される。

## 非目標

- Python 版 Hypothesis との API 互換。
- Python ランタイムへの依存（Python interop は使わない）。
- GPU コードの property テスト。
- カバレッジ誘導型ファジング（将来の拡張候補に留める）。

## 設計の柱

| 柱 | 内容 | ADR |
|----|------|-----|
| 内部縮小 | 値ではなく選択列を縮小する（Hypothesis の Conjecture 方式） | [0002](../adr/0002-choice-sequence-based-shrinking.md) |
| 静的ディスパッチ | Strategy はトレイト、コンビネータはジェネリック struct | [0003](../adr/0003-strategy-trait-with-static-dispatch.md) |
| TestCase 駆動 | property は `def(mut TestCase) raises`、値は `tc.draw` で引く | [0004](../adr/0004-property-as-testcase-closure.md) |
| 純粋関数の合成 | コンビネータは thin 関数を comptime パラメータで受け取る | [0005](../adr/0005-thin-functions-as-comptime-parameters.md) |
| 決定的な乱数 | 状態を明示した自前 PRNG | [0006](../adr/0006-explicit-state-prng.md) |
| 関数型コア | 純粋なコア（Strategy・縮小パス）と命令型シェル（TestCase・ランナー） | [0008](../adr/0008-functional-core-imperative-shell.md) |

## 機能対応表

| 機能 | Hypothesis | proptest | proptest-mojo | 状態 |
|------|-----------|----------|---------------|------|
| 決定的 PRNG | 内部 | 内部 | `SplitMix64` / `Xoshiro256StarStar` / `derive` | Implemented (M1) |
| 整数・真偽値 | `integers`, `booleans` | `any::<i32>`, 範囲 | `integers`, `booleans` | Implemented (M1) |
| 整数型ごと | `integers` の型指定 | `any::<i32>` など | `integers_of[DType]` | Planned (M2) |
| 浮動小数点数 | `floats` | `f64::ANY` など | `floats` | Planned (M2) |
| 文字列・バイト列 | `text`, `binary` | 正規表現, `vec(u8)` | `text`, `bytes` | Planned (M2) |
| コレクション | `lists`, `sets`, `dictionaries` | `vec`, `hash_set`, `hash_map` | `lists`, `unique_lists`, `dicts` | Planned (M2) |
| タプル・Optional | `tuples`, `none() \| x` | タプル, `option::of` | `tuples`, `optionals` | Planned (M2) |
| 選択 | `one_of`, `sampled_from`, `just` | `prop_oneof!`, `select`, `Just` | `just` | Implemented (M1) |
| 選択（複数候補） | `one_of`, `sampled_from` | `prop_oneof!`, `select` | `one_of`, `sampled_from` | Planned (M2) |
| 変換 | `.map`, `.filter`, `.flatmap` | `prop_map`, `prop_filter`, `prop_flat_map` | `map[f]`, `filter[p]`, `flat_map[f]` | Planned (M2) |
| 合成 | `@composite`, `data()` | `prop_compose!` | 合成 Strategy struct、`tc.draw` | Implemented (M1) |
| 前提条件 | `assume` | `prop_assume!` | `tc.assume` | Implemented (M1) |
| 縮小 | 内部縮小 | 値ツリー | 内部縮小 | M1 実装済み、M3 は計画中 |
| 端値の優先生成 | あり | 一部 | あり | Planned (M4) |
| 再現 | `@seed`, `@reproduce_failure` | 失敗の永続化ファイル | `Settings(seed=...)`, `Settings(replay=...)` | Planned (M4) |
| 反例の永続化 | example database | `proptest-regressions/` | example database | Planned (M4) |
| ヘルスチェック | あり | 一部 | あり | Planned (M4) |
| 状態機械テスト | `RuleBasedStateMachine` | `proptest-state-machine` | `StateMachine` トレイト | Planned (M5) |
| 再帰的データ | `recursive` | `prop_recursive` | 調査中 | Planned (M5) |
| 型からの導出 | `from_type` | `Arbitrary` | `Arbitrary` トレイト | Planned (M5) |
| Targeted PBT | `target` | なし | `tc.target` | Planned (M5) |

## 用語

| 用語 | 意味 |
|------|------|
| Strategy | 値の生成方法を表す不変の値。`draw` で `TestCase` から値を作る |
| property | すべての入力で成り立つべき性質。失敗は例外（`raise`）で表す |
| TestCase | 1 回の property 実行に対応し、選択列を記録・再生する |
| 選択（choice） | 生成中に行われる 1 回の乱択。上限付き整数などの型付きの値 |
| 選択列（choice sequence） | 1 回の実行で行われた選択の列。縮小と再現の単位 |
| span | 選択列上の区間。1 つの Strategy 呼び出しが消費した範囲を表し、構造的な縮小に使う |
| 縮小（shrinking） | 失敗する選択列を、失敗を保ったままより単純な選択列に置き換えること |
