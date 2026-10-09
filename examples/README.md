# examples

動く使用例です。CI はすべて実行します (失敗例は `try` で受けて報告を
表示するので、終了コードは 0 です)。

| ファイル | 内容 | 対応ガイド |
|----------|------|-----------|
| `basic.mojo` | 最小の使い方: 通る性質と縮小される性質 | [basics](../docs/guide/basics.md) |
| `combinators.mojo` | `map` / `filter` / `flat_map` の導出 | [composition](../docs/guide/composition.md) |
| `lists.mojo` | 合成 Strategy struct で作る整数リスト | [composition](../docs/guide/composition.md) |

実行方法:

```sh
pixi run mojo run -I src examples/basic.mojo < /dev/null
pixi run mojo run -I src examples/combinators.mojo < /dev/null
pixi run mojo run -I src examples/lists.mojo < /dev/null
```
