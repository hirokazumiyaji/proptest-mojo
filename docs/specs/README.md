# 設計書（Specs）

proptest-mojo の **現在の** 設計です。実装と常に一致させます（運用ルールは [docs/README.md](../README.md)）。
未実装の項目には「計画中（Planned）」と付記しています。

| 文書 | 内容 |
|------|------|
| [overview.md](overview.md) | 目的、スコープ、Hypothesis / proptest との機能対応 |
| [architecture.md](architecture.md) | モジュール構成、データの流れ、依存方向 |
| [choice-sequence.md](choice-sequence.md) | 選択列・TestCase・span・状態遷移 |
| [strategies.md](strategies.md) | Strategy トレイト、組み込み Strategy、コンビネータ |
| [shrinking.md](shrinking.md) | 単純さの順序、縮小パス、縮小ループ |
| [runner.md](runner.md) | `for_all`、Settings、生成フェーズ、レポート、再現、example database |
| [coding-guidelines.md](coding-guidelines.md) | 関数型の実装規約と Mojo の言語制約 |

判断の経緯は [ADR](../adr/README.md) を参照してください。
