# ADR-0011: 再帰的 Strategy を実行時深さ制限の単一 struct で実現する

- 状態: Accepted
- 日付: 2026-09-30
- 関連: Issue #29、[specs/strategies.md](../specs/strategies.md)、[ADR-0003](0003-strategy-trait-with-static-dispatch.md)

## 文脈

木構造などの再帰的なデータを生成する必要がある。静的ディスパッチ（ADR-0003）の下では、素朴な再帰型 `Tree = OneOf[Leaf, Node[Tree]]` は型が無限に入れ子になり書けない。`specs/strategies.md` の Planned にある通り、深さを型パラメータで区切る方式か、限定的な型消去かをスパイクで比較した（`mojo 1.2.0.dev2026092605`、worktree 内のみで検証しコミットしていない）。

検証結果:

- 深さ型パラメータ: `Branch[S: Strategy](Strategy) where S.Value == Int` の入れ子はコンパイル・実行できた。ただし深さごとに異なる型（`OneOf2[Integers, Branch[OneOf2[...]]]`）が必要で、型名が深さに比例して伸びる。木の値型自体も再帰（`List[Self]` は `field 'children' has non-'Deinitable' type` で却下）されるため、型レベルの再帰だけでは JSON 風の値は作れない。
- 限定的な型消去: `def(...) -> T` 型はトレイト扱いで struct のフィールドにできず（ADR-0003）、単一の `Gen[T]` 型は作れない。`ArcPointer` と手書き vtable による消去は unsafe が増えるため採用しない。
- 実行時深さ制限: `List[Self]` の代わりに `List[ArcPointer[Self]]` の間接参照を使うと、具体的な再帰値型 `JsonValue`（null・整数・配列）がコンパイル・実行できた。その値型に対する単一の `JsonTree` Strategy が実行時の `max_depth` フィールドで再帰を打ち切り、型は 1 つで済む。全ゼロ選択で `null` を引き、深さ・幅の上限が選択予算内に収まることも確認した。

## 決定

- 再帰は型レベルでなく値レベルで行う。`src/proptest/strategies/recursive.mojo` に具体的な再帰値 `JsonValue` と、実行時の深さ予算を持つ単一の `JsonTree` Strategy を置く。
- `JsonValue` の子は `ArcPointer` の間接参照とし、unsafe な vtable は導入しない。値は `draw` 後は不変として扱い、コピー間の共有を観測しない。
- 符号化は `node(depth)` が分岐旗（0=葉、1=配列）、葉が種別（0=null、1=整数）、配列が幅（0..max_width）と子の再帰とし、深さ 0 では分岐旗を消費しない。全ゼロ選択は `null` を引く。
- 汎用の `prop_recursive(leaf, branch)` コンビネータは作らない。分岐の作り方が値型ごとに異なる上、内側 Strategy の型を静的に 1 つに決める必要（`flat_map` と同じ制約）があり、単一 struct の方が正直なため。再帰が必要な形状ごとに `JsonTree` と同じ形の bespoke な Strategy を書く。

## 検討した代替案

- 深さを型パラメータで区切る方式: 動作するが、深さごとに型が増え、再帰値型の問題も残る。深い木で型名が実用に耐えないため不採用。
- `ArcPointer` と手書き vtable による Strategy の型消去: ADR-0003 で unsafe 増加を理由に却下済み。値の間接参照（safe）で足りたため不要。
- JSON を `String` 値として生成する方式: 再帰値型を避けられるが、構造の検査（深さ・要素数）が文字列解析になり、縮小の局所性も失うため不採用。

## 結果

- `json_tree(max_depth, max_width, minimum, maximum)` で JSON 風の木が生成でき、縮小で空配列 `[]`・`null` などの単純な木に落ちる（`tests/test_recursive.mojo` の `for_all` 回帰で保証）。
- 制約: 再帰の形状ごとに新しい値型と Strategy が必要になる。`Arbitrary` トレイト（M5）は依然として Planned に残る。
- 子の描画は `JSON_CHILD_SPAN` の span で囲む。現行の縮小パス（M1）は span を見ないが、M3 の span 系パスが来たときに要素単位の操作ができる。
