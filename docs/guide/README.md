# ユーザーガイド

数分で property-based testing を始めるための手引きです。設計の詳細は
[Specs](../specs/README.md) を参照してください。

## 3 分クイックスタート

前提: [pixi](https://pixi.sh/) が入っていること。

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
pixi run mojo run -I src examples/basic.mojo < /dev/null
```

`examples/basic.mojo` は「通る性質」と「縮小される性質」の両方を示します。
通る性質だけなら、自分のテストはこの形です。

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

## 目次

| 頁 | 内容 |
|----|------|
| [setup](setup.md) | セットアップ: 依存関係、実行方法、CI での回し方 |
| [basics](basics.md) | 基本: `for_all`、`TestCase.draw`、`assume`、`note` |
| [strategies](strategies.md) | Strategy 一覧: 使えるものと計画中のもの |
| [composition](composition.md) | 合成: `map` / `filter` / `flat_map` と合成 Strategy struct |
| [shrinking](shrinking.md) | 縮小: 報告書の読み方と縮小しやすい書き方 |
| [replay](replay.md) | 再現: シード固定と環境変数 |
| [stateful](stateful.md) | 状態機械テスト: 計画 (M5) と現時点の代替手段 |

対応する動くコードは [`examples/`](../../examples/README.md) にあります。
CI は全 example を実行します。
