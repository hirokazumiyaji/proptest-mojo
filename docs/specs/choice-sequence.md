# 選択列と TestCase

縮小と再現の土台となるデータ構造を定める。背景は [ADR-0002](../adr/0002-choice-sequence-based-shrinking.md)。

## ChoiceNode

1 回の選択を表す。

```mojo
@fieldwise_init
struct ChoiceKind(Equatable, TrivialRegisterPassable, Writable):
    var value: UInt8
    comptime INTEGER = ChoiceKind(0)   # 0..=max_value の非負整数
    comptime BOOLEAN = ChoiceKind(1)   # 0 または 1
    comptime FLOAT = ChoiceKind(2)     # 辞書順エンコード済みの 64bit（floats.md 参照）

@fieldwise_init
struct ChoiceNode(Copyable, Equatable, Writable):
    var kind: ChoiceKind
    var value: UInt64       # 選ばれた値。0 が最も単純
    var max_value: UInt64   # 取りうる最大値（含む）
    var forced: Bool        # 生成器が値を固定した選択。縮小対象外
```

- すべての選択は「`0..=max_value` の非負整数」に正規化する。**0 が最も単純な値** という規約を全 Strategy が守る。
  - 例: `integers(-10, 10)` は、縮小の目標値（範囲内で 0 に最も近い値）からの距離を「+1, -1, +2, -2, ...」の順で非負整数に写す。
- `kind` は縮小パスが意味に応じた操作（真偽値は反転しない、浮動小数点数は整数への単純化を試す等）を選ぶために使う。

## ChoiceSequence

`List[ChoiceNode]` を包む不変の値。

- **shortlex 順序**: `a < b` ⇔ `len(a) < len(b)`、または長さが等しく値の列が辞書順で小さい。縮小はこの順序で厳密に小さくなる方向にのみ進むため、必ず停止する。
- **シリアライズ**: 値だけを可変長整数（LEB128）で並べ、Base64 で文字列化する。`kind` と `max_value` は再生時に Strategy が再計算するため保存しない。

## Span

選択列上の区間。1 回の `tc.draw(strategy)` やコレクションの 1 要素など、構造上の単位を表す。

```mojo
@fieldwise_init
struct Span(Copyable, Writable):
    var start: Int      # 開始インデックス（含む）
    var end: Int        # 終了インデックス（含まない）
    var label: UInt64   # Strategy の種類を表すラベル（同種の span の入れ替えに使う）
    var depth: Int      # 入れ子の深さ
    var discarded: Bool # filter で棄却された試行の span
```

- `TestCase.start_span(label)` / `stop_span(discard=False)` で記録する。`tc.draw` は自動で span を張る。
- 縮小パスは span を使って「リストの 1 要素を丸ごと削除する」「同じラベルの span を並べ替える」といった構造的な操作をする。
- `label` は Strategy の種類だけに依存する。`tc.draw(strategy, label)` の `label` は報告用の `draw_labels` にだけ使い、span のラベルには `Strategy.span_label()`（必須メソッド、実装は `kind_label("<kind>")`）を使う。同じ報告ラベルで異なる Strategy を描くと span ラベルも異なるので、縮小パスが構造的に互換でないブロックを入れ替えない。

## TestCase

1 回の property 実行に対応する唯一の可変オブジェクト。

### 選択の供給

| モード | 供給元 | prefix を使い切った後 |
|--------|--------|------------------------|
| 生成（generating） | PRNG | PRNG から引き続き生成 |
| 再生（replaying） | 与えられた prefix | 以降の選択はすべて 0（最も単純な値）を返す |

- prefix の値が現在の `max_value` を超える場合は `max_value` に丸める（縮小で前方の選択が変わり、後方の選択の上限が変わっても再生が壊れないようにする）。
- 選択数が `Settings.max_choices`（既定 8192）を超えたら状態を `OVERRUN` にして中断する。

### プリミティブ

```mojo
def draw_integer(mut self, max_value: UInt64) raises -> UInt64
def draw_boolean(mut self, p_true: Float64 = 0.5) raises -> Bool
def draw_float_bits(mut self) raises -> UInt64          # Planned: M2
def forced_integer(mut self, value: UInt64, max_value: UInt64) raises -> UInt64
def start_span(mut self, label: UInt64)
def stop_span(mut self, discard: Bool = False)
```

`draw_boolean` の偏り `p_true` は生成時にのみ使い、記録される値は 0 / 1 である。0（False）が単純な側になる。

`forced_integer` は乱数を消費しないが、再生時には prefix カーソルも 1 つ進める。強制された選択も choices 上の 1 スロットを占めるため、後続の再生を元の実行と同じ位置に揃える必要があるためである。

### ユーザー向け操作

```mojo
def draw[S: Strategy](mut self, strategy: S, label: StringSlice = "") raises -> S.Value
def assume(mut self, condition: Bool) raises
def note(mut self, message: String)
def target(mut self, score: Float64, label: String = "")   # Planned: M5
```

`draw` は値の `Writable` 表現をラベルとともに記録し、反例の報告に使う。

### 状態

```text
          ┌──────────── property が正常終了 ────────────► VALID
RUNNING ──┼──────────── assume 失敗 / filter 棄却超過 ──► INVALID
          ├──────────── 選択数の上限超過 ────────────────► OVERRUN
          └──────────── property が raise ──────────────► INTERESTING
```

- `assume` と `OVERRUN` は、状態を設定したうえで内部用の `Error` を送出して property を中断する。
- ランナーは例外を受けたとき、**メッセージではなく `tc.status` で分類する**。状態が `RUNNING` のままなら property 自身の失敗（`INTERESTING`）とみなす。これにより、ユーザーの例外メッセージと衝突しない。
- `INTERESTING` のときは例外のメッセージを失敗の説明として保持する。
