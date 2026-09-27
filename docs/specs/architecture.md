# アーキテクチャ

## レイヤーと依存方向

```text
┌──────────────────────────── 命令型シェル ────────────────────────────┐
│ runner       for_all / Settings / Report / 生成フェーズ / 縮小ループ   │
│ database     example database（ファイル I/O）                          │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 呼び出す
┌───────────────▼──────────────────────────────────────────────────────┐
│ testcase     TestCase: 選択の記録・再生、span、状態、PRNG の所有        │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 依存
┌───────────────▼──────────────── 関数型コア ──────────────────────────┐
│ strategies   Strategy トレイト、組み込み Strategy、コンビネータ        │
│ shrink       縮小パス（選択列 → 候補の列）、shortlex 順序              │
│ choice       ChoiceNode / ChoiceSequence / Span / シリアライズ         │
│ prng         SplitMix64 / xoshiro256**、シード導出                      │
└──────────────────────────────────────────────────────────────────────┘
```

依存は上から下への一方向のみとする。
`strategies` が `testcase` に依存するのは `draw(self, mut tc: TestCase)` のシグネチャのためであり、`TestCase` のプリミティブ（`draw_integer` など）以外は使わない。
`shrink` は `testcase` と `runner` に依存しない。候補の評価はランナーが行う。

## パッケージ構成

```text
pixi.toml
pixi.lock
src/proptest/
  __init__.mojo              公開 API の再エクスポート
  prng.mojo                  PRNG と導出関数
  choice.mojo                ChoiceKind / ChoiceNode / ChoiceSequence / Span / shortlex
  encoding.mojo              選択列のシリアライズ（replay 文字列、database）
  testcase.mojo              TestCase, Status, 例外の分類
  strategy.mojo              Strategy トレイト
  strategies/
    primitives.mojo          integers, integers_of, booleans, just
    floats.mojo              floats
    text.mojo                text, bytes
    collections.mojo         lists, unique_lists, dicts, tuples, optionals
    choice.mojo              one_of, sampled_from
    combinators.mojo         map, filter, flat_map
  shrink/
    passes.mojo              各縮小パス（純粋関数）
    shrinker.mojo            縮小ループ（評価関数を受け取る）
  runner.mojo                for_all, Settings, Report
  database.mojo              ExampleDatabase
  stateful.mojo              StateMachine（Planned: M5）
tests/
  test_*.mojo                単体テスト・プロパティテスト
  shrink_quality/            縮小品質の回帰テスト
examples/                    利用例
```

`pixi.toml` のタスク:

| タスク | 内容 |
|--------|------|
| `test` | `tests/**/test_*.mojo` を `mojo run -I src` で全実行（1 つでも失敗したら非 0） |
| `format` | `mojo format src tests` |
| `format-check` | コピー上で `mojo format` し、作業ツリーと diff（index 非破壊） |
| `build` | `mojo precompile src/proptest -o proptest.mojoc`（成果物は gitignore） |

対応プラットフォームは `osx-arm64` と `linux-64`（ADR-0007 の Linux / macOS CI 前提）。

CI（`.github/workflows/ci.yml`）は PR と `main` への push で、`ubuntu-latest` と `macos-15` の両方で `pixi run format-check` と `pixi run test` を実行する（`prefix-dev/setup-pixi`、キャッシュ有効）。

## 1 回の `for_all` のデータフロー

```text
for_all(prop, settings)
 │
 ├─ 1. 再生フェーズ: database と settings.replay の選択列を TestCase(prefix=...) で再実行
 │
 ├─ 2. 生成フェーズ: i = 0..max_examples
 │      tc = TestCase.generating(derive(seed, i))
 │      prop(tc)
 │        └─ tc.draw(strategy) → strategy.draw(tc) → tc.draw_integer(...) → 記録
 │      結果: VALID / INVALID(assume・filter) / OVERRUN / INTERESTING(失敗)
 │
 ├─ 3. 縮小フェーズ（INTERESTING が出たら）
 │      best = tc.choices
 │      loop: for pass in passes:
 │              for cand in pass(best):              ← 純粋関数
 │                 if shortlex(cand) < shortlex(best) and evaluate(cand) is INTERESTING:
 │                     best = evaluate の結果の選択列（実際に消費した分だけ）
 │      固定点または予算切れで終了
 │
 └─ 4. 報告: best を再生して draw のラベルと値を収集し、例外として送出
          database に best を保存
```

## 主要な型の責務

| 型 | 可変性 | 責務 |
|----|--------|------|
| `Strategy` 実装 | 不変 | 選択列から値を決定的に作る |
| `ChoiceSequence` | 不変として扱う | 選択の列。比較・シリアライズの単位 |
| `TestCase` | 可変（唯一） | 選択の供給（prefix 再生または PRNG）、記録、span、状態 |
| `Settings` | 不変 | 実行パラメータ |
| `Shrinker` | ループ内でのみ可変 | 現在の最良の選択列を保持し、パスを固定点まで適用 |
| `Report` | 不変 | 反例の表示内容と再現情報 |
