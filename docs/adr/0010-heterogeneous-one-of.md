# ADR-0010: 異種 Strategy の one_of を `where` 句と `rebind` で実現する

- 状態: Accepted
- 日付: 2026-09-30
- 関連: Issue #14、[specs/strategies.md](../specs/strategies.md)、[ADR-0003](0003-strategy-trait-with-static-dispatch.md)

## 文脈

`one_of` は複数の Strategy から 1 つを選んで値を引く。静的ディスパッチ（ADR-0003）の下では、同種の Strategy のリスト（`List[S]`）はそのまま書けるが、`Value` が同じで型が異なる Strategy の組み合わせ（例: `Integers` と `Just[Int]`）が書けるかは不明だった。`def(...) -> T` 型をフィールドにできない制約（ADR-0003）により、型消去された単一の `Gen[T]` 型は作れない。Issue #14 の調査として、`mojo 1.2.0.dev2026092605` で `OneOf2[A, B]` のコンパイル可否を検証した。

検証結果:

- 素朴な実装は通らない。`comptime Value = Self.A.Value` とした struct の `draw` で `return self.b.draw(tc)` と書くと、`A.Value` と `B.Value` がどちらも `Int` であっても `cannot implicitly convert 'B.Value' value to 'OneOf2[A, B].Value'` になる。関連型は具体型が一致しても自動で単一化されない。
- パラメータリスト内の `where`（`struct OneOf2[A: Strategy, B: Strategy where ...]`）は「no longer supported」で却下される。シグネチャ後の trailing `where`（`struct OneOf2[A: Strategy, B: Strategy](Strategy) where A.Value == B.Value`）は通る。不一致の組（例: `OneOf2[Integers, Booleans]`）の構築は `violated constraint ... expected 'Bool(identical(A.Value, B.Value))'` で失敗し、等価性の証拠として機能する。コンパイラ自身が `==` を `identical` に正規化して表示する。
- 本体の分岐は `rebind[Self.Value](other^).copy()` で通る。一致する組（`Integers`/`Integers`、`Integers`/`Just[Int]`）はコンパイル・実行でき、不一致の組は `draw` の実体化時点で失敗する。`rebind` は import 不要の組み込みで、戻り値は generic な `Value`（`Copyable` だが `ImplicitlyCopyable` でない）のため明示の `.copy()` が必要だった。
- コンストラクタ `one_of2` にも trailing `where A.Value == B.Value` が必須である。付けないと `lacking evidence to prove correctness` で定義自体が通らない。付けると型推論（`one_of2(integers(0, 1), booleans())`）のまま不一致が呼び出し側で `violated constraint` として報告される。

## 決定

- 同種 N 分岐は `OneOf[S]` + `one_of(var strategies: List[S])` とする（`src/proptest/strategies/choice.mojo`）。
- 値の選択は `SampledFrom[T]` + `sampled_from(var values: List[T])` とする。
- 異種 2 分岐は `OneOf2[A, B]` + `one_of2(var a: A, var b: B)` とし、struct と関数の両方に trailing `where A.Value == B.Value` を付け、本体では `rebind[Self.Value](other^).copy()` で分岐する。
- 異種 3 分岐以上は `one_of2` の入れ子、または分岐を 1 つの Strategy 型に寄せてから `one_of` を使う。型消去の vtable は導入しない。

## 検討した代替案

- `return self.b.draw(tc)` の直接返却: 上記の通り関連型が単一化されず、不一致でなく一致でも失敗する。
- `ArcPointer` と手書き vtable による型消去: ADR-0003 で unsafe 増加を理由に却下済み。今回 `where` + `rebind` で静的に書けたため不要。
- ユーザー側の enum ラッパー: N 分岐で payload が異なる場合には依然有効な手段として残るが、ライブラリ標準の仕組みは不要になった。
- コンパイラの将来の関連型の単一化改善を待つ: `rebind` が証拠として使えたため待たない。改善が入れば本体を単純化できる。

## 結果

- 同種 `one_of`・`sampled_from`・異種ペア `one_of2` がいずれも「選択 0 が先頭」の縮小単調性を満たす。インデックス選択を最初に引くため、縮小パスは選択値を下げるだけで先頭分岐にたどり着く。
- 異種の不一致は実行時エラーではなくコンパイルエラーになる。
- 制約: 異種 N 分岐は入れ子で型名が伸びる。再帰 Strategy と同様、深い組み合わせは型名が長くなる（ADR-0003 の既知の tradeoff）。
