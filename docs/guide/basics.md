# 基本

## 考え方

property は「すべての入力で成り立つべき性質」です。
`def(mut TestCase) raises` の形で書き、値は `tc.draw` で引きます。
失敗は例外 (`raise`) で表します。

```mojo
from proptest import Settings, TestCase, for_all, integers

def _addition_commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-1000, 1000), "a")
    var b = tc.draw(integers(-1000, 1000), "b")
    if a + b != b + a:
        raise Error("addition must commute")

def main() raises:
    for_all(_addition_commutes, Settings(seed=UInt64(1)))
```

`for_all` は property を生成した example に対して繰り返し実行し、
反例が見つかれば縮小して `Error` で報告します。反例がなければ何も返しません。

## `tc.draw(strategy, label)`

Strategy から値を 1 つ引きます。`label` は失敗報告に表示される名前です。
`label` を付けると縮小後の反例がそのまま読めるので、基本的には付けます。

```mojo
var x = tc.draw(integers(0, 10000), "x")
```

## `tc.assume(condition)`

前提条件を表します。条件を満たさない example は捨てて次に行きます。

```mojo
def _nonzero_divides(mut tc: TestCase) raises:
    var d = tc.draw(integers(-100, 100), "d")
    tc.assume(d != 0)
    if (d * 42) // d != 42:
        raise Error("division broke")
```

捨てすぎると `for_all` が諦めます (`gave up after ... rejected by
assume: condition too strict`)。その場合は範囲を絞った Strategy
(`integers(1, 100)` など) に書き換えてください。

## `tc.note(message)`

失敗報告に残すメモです。縮小後の反例を再生したときに表示されます。

```mojo
tc.note("checking size=" + String(len(xs)))
```

## `Settings`

`for_all` の実行パラメータです。不変の値型で、キーワード引数で作ります。

| フィールド | 型 | 既定値 | 意味 |
|------------|----|--------|------|
| `max_examples` | `Int` | `100` | 試す `VALID` な example の目標数 |
| `seed` | `Optional[UInt64]` | `None` | 実行全体のシード。`None` なら `PROPTEST_SEED`、なければ時刻 |
| `max_choices` | `Int` | `8192` | 1 回の実行で許す選択数。超えると `OVERRUN` で捨てる |
| `max_shrink_evaluations` | `Int` | `5000` | 縮小中の実行回数の上限 |

生成数の既定値は `PROPTEST_MAX_EXAMPLES` で上書きできます
([setup](setup.md))。再現については [replay](replay.md) を参照してください。

`replay` (選択列の再生) や example database は M4 で計画中です
([Specs: ランナー](../specs/runner.md))。
