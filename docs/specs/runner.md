# ランナー

背景は [ADR-0004](../adr/0004-property-as-testcase-closure.md) と [ADR-0006](../adr/0006-explicit-state-prng.md)。

## API

```mojo
def for_all[P: def(mut TestCase) raises -> None](
    prop: P, settings: Settings = Settings()
) raises
```

- `prop` は捕捉クロージャでよい。
- 反例が見つかれば、縮小後に整形したメッセージを持つ `Error` を送出する。`std.testing.TestSuite` の中で使えば、そのままテスト失敗になる。
- 反例がなければ何も返さない。

```mojo
from proptest import for_all, Settings, TestCase, integers, lists
from std.testing import assert_equal, TestSuite

def test_addition_commutes() raises:
    def prop(mut tc: TestCase) raises:
        var a = tc.draw(integers(-1000, 1000), "a")
        var b = tc.draw(integers(-1000, 1000), "b")
        assert_equal(a + b, b + a)

    for_all(prop, Settings(max_examples=500))

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
```

## Settings

不変の値型。`@fieldwise_init` と既定値付きのキーワード引数で作る。

| フィールド | 型 | 既定値 | 意味 | M |
|------------|----|--------|------|---|
| `max_examples` | `Int` | 100 | `VALID` な実行の目標数 | M1 |
| `seed` | `Optional[UInt64]` | `None` | 実行全体のシード。`None` なら環境変数 `PROPTEST_SEED`、なければ時刻から決める | M1 |
| `max_choices` | `Int` | 8192 | 1 回の実行で許す選択数。超えると `OVERRUN` | M1 |
| `max_shrink_evaluations` | `Int` | 5000 | 縮小中の実行回数の上限 | M1 |
| `replay` | `Optional[String]` | `None` | 報告された選択列を再生する（生成・縮小はしない） | M4 |
| `name` | `String` | `""` | example database のキー。空なら database を使わない | M4 |
| `database_dir` | `String` | `".proptest-mojo"` | example database の保存先 | M4 |
| `verbosity` | `Verbosity` | `NORMAL` | `QUIET` / `NORMAL` / `VERBOSE`（全 example を表示） | M4 |

環境変数 `PROPTEST_MAX_EXAMPLES` と `PROPTEST_SEED` は、`Settings` の既定値を上書きする（CI で回数を増やす用途）。コードで明示した値が優先される。

`max_examples` はコンストラクタで `Optional[Int]` として受け取り、明示されたかどうか（`max_examples_set`）を値とは別に保持する。既定値 100 との一致で「省略された」と判定すると、`Settings(max_examples=100)` が環境変数で上書きされてしまうため。

`max_examples` は正の値に限る。0 以下では生成ループの条件が偽のままで property が一度も実行されず、テストが黙って成功してしまうため、`effective_max_examples` が検証して `Error` にする（コンストラクタではなく。`for_all` の既定引数 `Settings()` から raise できないため）。`PROPTEST_MAX_EXAMPLES` も同様。

`PROPTEST_SEED` は `UInt64` として桁ごとに読む。符号付き `Int` を経由すると `Int.MAX` より大きい（報告される seed の半分の範囲）正当な seed を拒否してしまう。範囲外や数値でない値は `Error` にする。

## フェーズ

```text
1. 再生      settings.replay または database の保存済み選択列を再実行（M4）
             → INTERESTING なら生成フェーズを飛ばして縮小へ
2. 生成      i = 0 の実行は全選択 0（最も単純な例）
             i >= 1 は PRNG(derive(seed, i)) で生成
             VALID が max_examples 回に達するか、INTERESTING が出たら終了
3. 縮小      shrinking.md のループ
4. 報告      最良の選択列を再生し、draw の記録から反例を整形
             database に保存（M4）
```

### 生成の工夫（M4）

- **端値の優先**: 生成モードの `draw_integer` は、一定の確率で `0`・`1`・`max_value`・`max_value - 1` などの端値を返す。追加の選択を消費しないため、縮小に影響しない。
- **サイズの漸増**: 序盤の example ほどコレクションの平均長を小さくし、単純な反例を早く見つける。

### 標的生成（M5）

- `tc.target(score)` を呼ぶと、その実行の最高スコアが記録される（NaN と無限大は無視）。
- ランナーは `VALID` な実行の最高スコア選択列を保持し、`VALID` が `max_examples` の半数に達した後の生成では、その選択列の変異体（各非 `forced` 選択を確率 0.1 で一様に置き換え、少なくとも 1 箇所は変異）を `derive(seed, attempt)` の PRNG で作って再生する。
- `target` を使わない実行の生成経路・再現性は変わらない。

## ヘルスチェック（M4）

| 状況 | 判定 | 報告 |
|------|------|------|
| `VALID` が `max_examples` に達する前に、`INVALID` が `10 * max_examples` 回を超えた | 失敗 | `assume` / `filter` が厳しすぎる旨と棄却率 |
| `OVERRUN` が実行全体の 20% を超えた | 失敗 | 生成するデータが大きすぎる旨 |
| 1 回も `VALID` にならなかった | 失敗 | 条件を満たす入力を生成できない旨 |

## 報告

```text
Falsifying example (after 37 examples, 112 shrink evaluations):
  a = 0
  xs = [1, 0]
  note: sorted = [0, 1]
Error: expected [0, 1] got [1, 0]
Seed: 1234567890
Reproduce with: Settings(replay="AAECAQ==")
```

- 反例は `tc.draw` の記録順に「ラベル = 値」の形で並べる。ラベル省略時は `draw #1` のように連番にする。
- `tc.note` のメッセージは反例の再生時にのみ表示する。
- 縮小を予算で打ち切った場合は、その旨を 1 行追加する。

## Example database（M4）

- `settings.name` が空でなければ、縮小後の選択列を `{database_dir}/{sha256(name)の先頭16桁}/{選択列のハッシュ}` に保存する。
- 次回の実行では、生成の前にそのディレクトリ内の選択列をすべて再生する。`INTERESTING` でなくなったものは削除する。
- `.proptest-mojo/` はユーザーのリポジトリで `.gitignore` するか、回帰テストとしてコミットするかを選べる。
- `name` の既定値を呼び出し位置から自動で導出できるか（Mojo の `call_location` 相当の機能の有無）は M4 で調査する。
