# 状態機械テスト

状態を持つ実装 (コンテナ、接続、ファイルなど) に対する property-based
testing は M5 で `StateMachine` トレイトとして計画中です。現時点では
`StateMachine` トレイトはありません。

## 現時点の代替手段

操作列をデータとして生成し、モデルと実装を並走させる property を書きます。
操作の種類は `integers` で引き、操作ごとのパラメータは合成 Strategy の
フィールドに持たせます ([composition](composition.md))。

```mojo
# 概念: 0 = push, 1 = pop をランダムな列で生成し、
# 単純なモデル (List) と被験スタックの振る舞いを比べる。
def _stack_matches_model(mut tc: TestCase) raises:
    var ops = tc.draw(IntLists(0, 1, 16), "ops")  # 操作列
    var model = List[Int]()
    var sut = MyStack()
    for op in ops:
        if op == 0:
            var v = tc.draw(integers(-100, 100), "v")
            model.append(v.copy())
            sut.push(v.copy())
        else:
            tc.assume(len(model) > 0)
            if sut.pop() != model.pop():
                raise Error("model mismatch after ops=" + String(ops))

    for_all(_stack_matches_model, Settings(seed=UInt64(9)))
```

ポイントは通常の property と同じです。

- 操作列は短く (`max_size` を小さく)。縮小が最小の操作列を見つけます。
- 成立しない操作 (`空への pop` など) は `tc.assume` で捨てる。
  捨てすぎたら操作の生成自体を工夫する ([basics](basics.md))。
- 反例の `ops` 表示に `label` を付けておく ([shrinking](shrinking.md))。

## 計画 (M5)

| 項目 | 概要 |
|------|------|
| `StateMachine` トレイト | 状態・コマンド・事前条件・次状態を定義する口 |
| コマンド生成と実行 | 操作列の生成、前提の自動スキップ、反例の縮小 |
| 再帰的データ | 木などの再帰構造の生成 (`recursive`) |
| `Arbitrary` トレイト | 型からの Strategy 導出 |
| `tc.target` | Targeted PBT (目的値への誘導) |

最新状況は [Specs: 概要](../specs/overview.md) の機能対応表を参照してください。
