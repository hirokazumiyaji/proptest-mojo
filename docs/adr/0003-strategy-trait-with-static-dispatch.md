# ADR-0003: Strategy をトレイトとジェネリック struct で静的ディスパッチする

- 状態: Accepted
- 日付: 2026-09-26
- 関連: [specs/strategies.md](../specs/strategies.md)

## 文脈

Strategy（値の生成器）を Mojo でどう表現するかを決める必要がある。
最も素直な「生成関数 `def(mut TestCase) raises -> T` をフィールドに持つ `Gen[T]`」を Mojo 1.2.0.dev2026092605 で検証した結果、次のことが分かった。

- `def(...) -> T` 型はトレイトとして扱われ、struct のフィールド型にできない（`struct fields do not support trait types`）。
- よって、型消去された生成関数を持つ単一の `Gen[T]` 型は作れない。

一方、次の形はコンパイル・実行できた。

```mojo
trait Strategy(Copyable, Deinitable):
    comptime Value: Copyable & Writable & Deinitable
    def draw(self, mut tc: TestCase) raises -> Self.Value: ...

@fieldwise_init
struct ListOf[S: Strategy](Strategy):
    comptime Value = List[Self.S.Value]
    var elem: Self.S
    ...
```

## 決定

- Strategy を関連型 `Value` を持つトレイトとして定義する。
- 組み込み Strategy とコンビネータは、内側の Strategy を型パラメータに取るジェネリック struct として実装する（Rust のイテレータアダプタと同じ形）。
- 生成は静的ディスパッチとし、実行時の型消去は行わない。
- 関連型 `Value` には `Copyable & Writable & Deinitable` を要求する。`Writable` は反例の表示に使う。

## 検討した代替案

- 生成関数を保持する `Gen[T]`: 上記の言語制約で実装できない。
- `ArcPointer` と手書きの vtable による型消去: unsafe なコードが増え、関数型のシンプルさを損なう。異種の Strategy を 1 つのコレクションに入れる需要（`one_of` の異種混合など）が出たときに、別 ADR で再検討する。

## 結果

- 生成はインライン化され、実行時のオーバーヘッドが小さい。
- コンビネータを重ねると型名が長くなる。ユーザーは `var` の型推論に任せ、型名を書く必要はほぼない。
- 再帰的な Strategy（木構造の生成）は型が無限に入れ子になるため、そのままでは書けない。別途設計が必要（Issue で調査する）。
- トレイトのデフォルトメソッドで `s.map[f]()` のようなメソッドチェーンを提供することは、現時点のコンパイラでは依存型付きの関数パラメータが通らず実現できない。コンビネータは自由関数 `map[f](s)` とする（[ADR-0005](0005-thin-functions-as-comptime-parameters.md)）。
