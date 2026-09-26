# 実装規約

原則は [ADR-0008](../adr/0008-functional-core-imperative-shell.md)（関数型コア・命令型シェル）。ここでは具体的な書き方を定める。

## 関数型の規約

| 規約 | 具体的な書き方 |
|------|----------------|
| 値は不変として扱う | Strategy・`ChoiceSequence`・`Settings`・`Report` は生成後に変更しない。「変更」は新しい値を返す関数で表す |
| 副作用の置き場所を限定する | 可変な状態は `TestCase` とランナー（縮小ループを含む）だけが持つ。コア側の関数は `mut` 引数を取らない（`draw(self, mut tc)` を除く） |
| 純粋関数を合成する | コンビネータに渡す関数は thin 関数（捕捉なし）。モジュールレベルの `def` として書く |
| 高階関数で副作用を注入する | 評価や I/O が必要なコアの関数は、その操作を関数引数で受け取る（例: 適応型の縮小パスが `is_interesting` を受け取る） |
| グローバル状態を持たない | モジュールレベルの `var` を使わない。`std.random` を使わない |
| 局所的な可変性は許容する | 関数内の `var` とループは、関数の外から観測できない限り使ってよい |
| 所有権を明示する | 値の受け渡しは `var` 引数と `^` で移動し、不要な `.copy()` をしない |
| 失敗は状態として表す | コアの分類は `Status` などの値で返す。`raise` は property の中断と、ランナーからユーザーへの報告に限る |

## Mojo の言語制約と回避策

`mojo 1.2.0.dev2026092605` での検証結果。コンパイラの更新で解消したら、ADR を起こして方針を見直す。

| 制約 | 回避策 |
|------|--------|
| `def(...) -> T` 型はトレイト扱いで、struct のフィールドにできない | 関数は thin 関数を comptime パラメータにする（[ADR-0005](../adr/0005-thin-functions-as-comptime-parameters.md)） |
| 捕捉クロージャは `Copyable` でなく、struct に保持できない | 捕捉が必要な変換は合成 Strategy（フィールドに値を持つ struct）で書く |
| 捕捉クロージャの型パラメータに関連型（`S.Value`）を含めると推論に失敗する | property は `def(mut TestCase) raises -> None` を受け取る（[ADR-0004](../adr/0004-property-as-testcase-closure.md)） |
| トレイトのデフォルトメソッドで依存型付きの関数パラメータを使えない | コンビネータは自由関数（`map[f](s)`）にする |
| トレイトの関連型をフィールドや一時値に使うには `Deinitable` が必要 | `Strategy` と `Strategy.Value` に `Deinitable` を要求する |

## Mojo の書き方

- 最新の構文を使う: `def` のみ、`comptime`、`std.` 付きの import、`out self` / `mut` / `var` の引数規約、`@fieldwise_init`、`Writable`。
- struct のパラメータは本体内で `Self.T` のように修飾する。
- コメントは「なぜ」だけを書く。処理の説明コメントは書かない。
- 公開 API には docstring を書く。

## テストの規約

- `tests/test_<module>.mojo` にモジュールごとのテストを置き、`TestSuite.discover_tests` で実行する。
- 関数型コア（PRNG、選択列、縮小パス）は property なしの単体テストで、入力と出力を直接比較する。
- 縮小パスの単体テストでは、評価関数に純粋な述語を渡す。
- ライブラリ自身の性質（例: shortlex が全順序である、シリアライズが往復で一致する）は、ライブラリ自身の `for_all` で検証する（ドッグフーディング）。M1 の `for_all` 完成前に書いたテストは、完成後に置き換えを検討する。
- 縮小品質は `tests/shrink_quality/` の回帰テストで守る（[shrinking.md](shrinking.md)）。
