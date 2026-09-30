# proptest-mojo

Pure Mojo で書かれた Property-based testing ライブラリです。
Python の [Hypothesis](https://hypothesis.readthedocs.io/) と Rust の [proptest](https://proptest-rs.github.io/proptest/) に匹敵する表現力と縮小（shrinking）品質を目標にしています。

> Status: 設計フェーズ。全体計画は [Roadmap (#34)](https://github.com/hirokazumiyaji/proptest-mojo/issues/34)、実装は [Milestones](https://github.com/hirokazumiyaji/proptest-mojo/milestones) と [Issues](https://github.com/hirokazumiyaji/proptest-mojo/issues) で管理しています。

## はじめに（数分で動かす）

前提: [pixi](https://pixi.sh/) が入っていること。

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
pixi run mojo run -I src examples/basic.mojo < /dev/null
```

通る性質と、最小の反例まで縮小される性質の両方が動きます。
次は [ユーザーガイド](docs/guide/README.md) と [examples](examples/README.md) をどうぞ。

## 目指す使い心地

```mojo
from proptest import for_all, TestCase, integers, lists
from std.testing import assert_true

# 誤った性質: 任意のリストは昇順に並んでいる
def test_every_list_is_sorted() raises:
    def prop(mut tc: TestCase) raises:
        var xs = tc.draw(lists(integers(-100, 100), max_size=50), "xs")
        assert_true(is_sorted(xs))

    for_all(prop)
```

失敗すると、選択列（choice sequence）ベースの縮小で最小の反例を探し、再現用の情報とともに報告します。

```text
Falsifying example (after 37 examples, 112 shrink evaluations):
  xs = [1, 0]
Reproduce with: Settings(replay="AAECAQ==")
```

## ドキュメント

- [docs/guide](docs/guide/README.md): ユーザーガイド（セットアップから縮小・再現まで）
- [examples](examples/README.md): 動く使用例（CI で全実行）
- [docs/specs](docs/specs/README.md): 現在の設計（living document）
- [docs/adr](docs/adr/README.md): 設計判断の履歴（Architecture Decision Records）
- [docs/README.md](docs/README.md): ドキュメント運用ルール
