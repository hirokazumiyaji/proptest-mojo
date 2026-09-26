# ADR-0005: コンビネータの関数は thin 関数を comptime パラメータで受け取る

- 状態: Accepted
- 日付: 2026-09-26
- 関連: [specs/strategies.md](../specs/strategies.md)、[specs/coding-guidelines.md](../specs/coding-guidelines.md)

## 文脈

`map`・`filter`・`flat_map` はユーザー関数を Strategy の中に保持する必要がある。
Mojo 1.2.0.dev2026092605 での検証結果は次の通り。

| 保持の方法 | 結果 |
|------------|------|
| 捕捉クロージャを型パラメータ `F: def(T) -> U` にしてフィールド `var f: Self.F` に保持 | クロージャ型が `Copyable` でなく、Strategy の `Copyable` 要件を満たせない。関連型を含むと推論も失敗する |
| thin 関数ポインタをフィールド `var f: def(Self.S.Value) thin -> Self.U` に保持 | 動作する |
| thin 関数を comptime パラメータ `f: def(S.Value) thin -> U` にする | 動作する。`map[show](map[double](s))` の形で `S`・`U` も推論される |
| トレイトのデフォルトメソッド `s.map[f]()` | 依存型付きの関数パラメータがトレイト要件と一致せずコンパイルできない |

## 決定

- `map`・`filter`・`flat_map` は、捕捉を持たない（thin な）関数を comptime パラメータで受け取る自由関数とする。

  ```mojo
  def map[S: Strategy, U: ..., //, f: def(S.Value) thin -> U](s: S) -> Map[S, U, f]
  ```

- 外部の値に依存する変換（捕捉が必要なケース）は、フィールドにパラメータを持つ合成 Strategy（ユーザー定義 struct が `Strategy` を実装する）で書く。これは Hypothesis の `@composite`、proptest の `prop_compose!` に相当する公式パターンとして文書化する。

## 検討した代替案

- 実行時の thin 関数ポインタをフィールドに持つ: 動作するが、comptime パラメータに比べてインライン化の機会を失う。型パラメータが 1 つ減る利点は、型推論が効くため小さい。
- 捕捉クロージャを受け入れる: 現行コンパイラでは保持できない。

## 結果

- コンビネータに渡す関数はトップレベル（またはモジュールレベル）の純粋関数になり、関数型の書き方と相性が良い。
- 捕捉が必要なケースは合成 Strategy を書く分だけ冗長になる。
- コンパイラが捕捉クロージャの保持やトレイトのデフォルトメソッドをサポートしたら、メソッドチェーン API の追加を別 ADR で検討する。
