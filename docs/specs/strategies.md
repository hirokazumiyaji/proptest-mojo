# Strategy

背景は [ADR-0003](../adr/0003-strategy-trait-with-static-dispatch.md) と [ADR-0005](../adr/0005-thin-functions-as-comptime-parameters.md)。

## Strategy トレイト

```mojo
trait Strategy(Copyable, Deinitable):
    comptime Value: Copyable & Writable & Deinitable

    def span_label(self) -> UInt64:
        ...

    def draw(self, mut tc: TestCase) raises -> Self.Value:
        ...
```

`span_label` は Strategy の種類を表すラベルの `UInt64`。`tc.draw` が自動で張る span の `label` に使われる。報告用のラベル（`tc.draw(strategy, label)` の `label`）とは独立で、Strategy の種類だけに依存する。実装は `kind_label("<kind>")` を返す。

`span_label` は必須メソッドで既定値を持たない。共通の既定値では実装を省いた Strategy がすべて同じラベルになり、兄弟 draw として現れたときに再び互換性とみなされてしまうため。

すべての Strategy 実装は次の規約を守る。

| 規約 | 理由 |
|------|------|
| **決定性**: 同じ選択列からは同じ値を作る。`TestCase` 以外の状態（グローバル変数、時刻、`std.random`）を読まない | 縮小と再現が選択列だけで成り立つため |
| **単純さの単調性**: 選択の値が小さいほど、生成される値が「単純」になる。全選択 0 のとき最も単純な値を返す | shortlex で小さい選択列が、人間にとって単純な反例に対応するため |
| **不変性**: `draw` は `self` を変更しない | Strategy は値として自由にコピー・共有されるため |
| **局所性**: 構造上の単位（コレクションの 1 要素など）ごとに span を張る | 構造的な縮小パスが働くため |
| **構造ラベル**: `span_label` は Strategy の種類だけで決まり、報告ラベルに依存しない | 縮小パスが同種とみなす span を入れ替えるため |

## 組み込み Strategy

表の「M」は実装予定のマイルストーン。

| 関数 | 値の型 | 縮小の目標 | M |
|------|--------|-----------|---|
| `integers(min, max)` | `Int` | 範囲内で 0 に最も近い値 | M1 |
| `integers_of[dtype](min, max)` | `Scalar[dtype]`（`Int8`〜`UInt64`） | 同上。範囲省略時はその型の全域 | M2 |
| `booleans()` | `Bool` | `False` | M1 |
| `just(value)` | `T` | （選択を消費しない） | M1 |
| `sampled_from(values: List[T])` | `T` | 先頭の要素 | M2 |
| `floats(min, max, allow_nan, allow_infinity)` | `Float64` | 0.0、次いで小さい整数値、単純な分数 | M2 |
| `text(alphabet, min_size, max_size)` | `String` | 空文字列、次いで先頭の文字 `"0"` 方向 | M2 |
| `bytes(min_size, max_size)` | `List[UInt8]` | 空列 | M2 |
| `lists(elements, min_size, max_size)` | `List[T]` | 短いリスト、各要素が単純 | M2 |
| `unique_lists(elements, min_size, max_size)` | `List[T]`（`T: Equatable`） | 同上 | M2 |
| `dicts(keys, values, min_size, max_size)` | `Dict[K, V]` | 空の辞書 | M2 |
| `tuples(a, b)` / `tuples(a, b, c)` | 2〜3 要素の値 | 各要素が単純 | M2 |
| `optionals(s)` | `Optional[T]` | `None` | M2 |
| `one_of(strategies: List[S])` | `S.Value` | 先頭の Strategy | M2 |
| `one_of2(a: A, b: B) where A.Value == B.Value` | `A.Value` | 先頭の Strategy（`a`） | M2 |

`Optional` や `Tuple` など標準ライブラリの型が `Writable` を満たさない場合は、このライブラリが `Writable` を実装した薄い値型を提供する（M2 の実装時に確認し、この表を更新する）。

### 整数の符号化

`integers(min, max)` は、縮小の目標値 `t`（範囲内で 0 に最も近い値）からの距離を次の順で非負整数 `k` に写す。

```text
k:     0   1    2    3    4   ...
値:    t  t+1  t-1  t+2  t-2  ...   （範囲外になる側はスキップ）
```

これにより「選択値 0 → 目標値」「小さい選択値 → 目標に近い値」という単調性が成り立ち、縮小パスは符号を意識せずに選択値を小さくするだけでよい。

### コレクションの符号化

Hypothesis の `many` と同じく、要素ごとに「続けるか」の真偽値を引く。

```text
[span: element] continue=1, <要素の選択...> [/span] [span] continue=1, <...> [/span] continue=0
```

- 続ける確率は平均長 `average_size`（既定は `min(max(min_size * 2, min_size + 5), (min_size + max_size) / 2)`）から決める。
- `min_size` までは `forced_integer` で 1 を強制し、`max_size` に達したら 0 を強制する。強制された選択は縮小対象外。
- 要素の span は continue フラグを含むため、span 削除パスが「要素を 1 つ取り除く」操作になる。

### 浮動小数点数の符号化（M2）

Hypothesis と同じ辞書順エンコーディングを使う。64bit の選択値のうち、小さい値ほど「単純な」浮動小数点数（0.0、小さな非負整数、分母の小さい値、…、無限大、NaN の順）に対応させる。符号は別の真偽値の選択とする。

## コンビネータ

いずれも thin 関数（捕捉を持たない関数）を comptime パラメータで受け取る自由関数である。

```mojo
def map[S: Strategy, U: Copyable & Writable & Deinitable, //,
        f: def(S.Value) thin -> U](s: S) -> Map[S, U, f]

def filter[S: Strategy, //, p: def(S.Value) thin -> Bool](s: S) -> Filter[S, p]

def flat_map[S: Strategy, T: Strategy, //,
             f: def(S.Value) thin -> T](s: S) -> FlatMap[S, T, f]
```

使用例:

```mojo
def double(x: Int) -> Int:
    return x * 2

def is_even(x: Int) -> Bool:
    return x % 2 == 0

def lists_up_to(n: Int) -> ListOf[IntRange]:
    return lists(integers(0, 100), max_size=n)

var evens = map[double](integers(0, 50))
var evens2 = filter[is_even](integers(0, 100))
var sized = flat_map[lists_up_to](integers(0, 10))
```

- `filter` は述語を満たさない値を引いた試行の span を `discarded` として記録し、最大 3 回まで引き直す。それでも満たさなければ `tc.assume(False)` 相当で `INVALID` にする。
- `flat_map` は外側の値に応じて内側の Strategy を作る。内側の Strategy の **型** はコンパイル時に 1 つに決まっている必要がある（値のパラメータだけが変わる）。

## 合成 Strategy（`@composite` / `prop_compose!` 相当）

捕捉が必要な変換や、複数の値を組み合わせる生成は、`Strategy` を実装する struct として書く。
これが公式の推奨パターンである。

```mojo
@fieldwise_init
struct User(Copyable, Writable):
    var name: String
    var age: Int

@fieldwise_init
struct Users(Strategy):
    comptime Value = User
    var max_age: Int

    def draw(self, mut tc: TestCase) raises -> User:
        var name = tc.draw(text(min_size=1, max_size=20))
        var age = tc.draw(integers(0, self.max_age))
        return User(name^, age)
```

property の中で直接 `tc.draw` を重ねてもよい。再利用したい組み合わせだけを合成 Strategy にする。

## 計画中（Planned）

- `Arbitrary` トレイト（M5）: 型ごとの既定 Strategy。`arbitrary[Int]()` で `integers_of[DType.int64]()` を返すなど。
- 再帰的な Strategy（M5）: 静的ディスパッチでは型が無限に入れ子になるため、深さを型パラメータで区切る方式か、限定的な型消去を調査する。
- 異種の Strategy の組み合わせ（M2 で実装済み）: `Value` が同じ異なる型の Strategy は `one_of2(a, b)` で組み合わせる（[ADR-0010](../adr/0010-heterogeneous-one-of.md)）。等価性は trailing `where A.Value == B.Value` で保証され、不一致はコンパイルエラーになる。3 分岐以上は `one_of2` の入れ子、または分岐を 1 つの Strategy 型に寄せてから `one_of` を使う。
