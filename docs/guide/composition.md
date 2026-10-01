# 合成

## `map`: 変換する

純粋関数で引き直します。縮小はベース Strategy を通じて効きます。

```mojo
from proptest.strategies.combinators import map

def double(x: Int) -> Int:
    return x * 2

var y = tc.draw(map[double](integers(0, 100)), "y")
```

## `filter`: 絞り込む

述語を満たす値だけ通します。棄却された試行は破棄 span として記録され、
上限回数 (`MAX_FILTER_ATTEMPTS`) を超えるとその example を捨てます
(`assume` と同じ扱い)。

```mojo
from proptest.strategies.combinators import filter

def is_even(x: Int) -> Bool:
    return x % 2 == 0

var z = tc.draw(filter[is_even](integers(0, 100)), "z")
```

条件が厳しすぎると example が捨てられ続けます。可能な範囲は
`filter` より範囲指定 (`integers(0, 100)` の bounds など) で表す方が速いです。

## `flat_map`: 依存させる

外側の値から内側の Strategy を作ります。内側 Strategy の「型」は
コンパイル時に固定され、値のパラメータだけが外側に依存できます。

```mojo
from proptest import Integers
from proptest.strategies.combinators import flat_map

def capped(n: Int) -> Integers:
    return Integers(0, n)

var w = tc.draw(flat_map[capped](integers(0, 10)), "w")
```

動く例は [`examples/combinators.mojo`](../../examples/combinators.mojo) です。

## 合成 Strategy struct: パラメータを捕捉する

コンビネータが受け取れるのは捕捉を持たない (thin) 関数だけです。
境界・サイズ・文字集合などのパラメータを持つ生成は、パラメータを
フィールドに持つ struct に `Strategy` を実装します。

```mojo
from proptest import TestCase, booleans, integers
from proptest.strategy import Strategy

# `User` は例示用の自作型。実装側で定義済みと仮定します。
@fieldwise_init
struct Users(Strategy):
    comptime Value = User
    var max_age: Int

    def draw(self, mut tc: TestCase) raises -> User:
        var age = tc.draw(integers(0, self.max_age), "age")
        var admin = tc.draw(booleans(), "admin")
        return User(age, admin)
```

規約は [Specs: Strategy](../specs/strategies.md) の表に従います。
特に、全選択 0 のときに最も単純な値を返すこと
(例: `Users(120)` なら `User(age=0, admin=False)`) を守ると縮小が効きます。
リストの合成例は [`examples/lists.mojo`](../../examples/lists.mojo) です。
