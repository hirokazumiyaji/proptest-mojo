# 縮小

失敗した example は、失敗を保ったままより単純な選択列へ自動で置き換えられ
(選択列ベースの内部縮小)、最小の反例だけが報告されます。

## 報告書の読み方

```text
Falsifying example (after 2 examples, 44 shrink evaluations):
  size = 2
  item = 1
  item = 0
  xs = [1, 0]
Error: unsorted: [1, 0]
Seed: 3
```

| 行 | 意味 |
|----|------|
| `after 2 examples` | 何回目の example で失敗したか (0 回目は最も単純な例) |
| `44 shrink evaluations` | 縮小のために再実行した回数 |
| `label = value` | `tc.draw(..., "label")` の記録。縮小後の反例での値 |
| `Error: ...` | property が送出したメッセージ |
| `Seed: 3` | 再現用シード ([replay](replay.md)) |
| `Shrink budget exhausted ...` | 出る場合のみ。予算切れで最小でない可能性がある |

`label` の無い `draw` は `draw #N` と表示されます。
`tc.note` の内容は `note: ...` 行に表示されます。

## 縮小しやすい書き方

1. **`label` を付ける**: 反例がそのまま読める報告になります。
2. **失敗条件を素直に書く**: 縮小は選択列だけを見るので、property 側の
   工夫は要りません。小さい選択値が単純な値に対応する Strategy
   ([strategies](strategies.md)) を使っていれば自動で効きます。
3. **自作 Strategy は全選択 0 で最も単純な値を返す**:
   [composition](composition.md) の規約です。これが崩れると
   「0 回目の実行が最も単純な例」という前提が崩れます。
4. **予算切れが出たら**: `max_shrink_evaluations` を上げるか、
   生成するデータ (特に自作コレクションの最大サイズ) を小さくします。
   `OVERRUN` が多い場合は `max_choices` を上げます。

仕組みの詳細は [Specs: 縮小](../specs/shrinking.md) を参照してください。
