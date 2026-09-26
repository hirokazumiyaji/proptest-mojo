# Architecture Decision Records

設計判断の履歴です。運用ルールは [docs/README.md](../README.md) を参照してください。
新しい ADR は [template.md](template.md) をコピーして作成します。

| No. | タイトル | 状態 | 日付 |
|-----|----------|------|------|
| [0001](0001-documentation-and-task-management.md) | ドキュメントとタスク管理の方針 | Accepted | 2026-09-26 |
| [0002](0002-choice-sequence-based-shrinking.md) | 選択列（choice sequence）ベースの内部縮小を採用する | Accepted | 2026-09-26 |
| [0003](0003-strategy-trait-with-static-dispatch.md) | Strategy をトレイトとジェネリック struct で静的ディスパッチする | Accepted | 2026-09-26 |
| [0004](0004-property-as-testcase-closure.md) | Property を `def(mut TestCase) raises` のクロージャで表現する | Accepted | 2026-09-26 |
| [0005](0005-thin-functions-as-comptime-parameters.md) | コンビネータの関数は thin 関数を comptime パラメータで受け取る | Accepted | 2026-09-26 |
| [0006](0006-explicit-state-prng.md) | 明示的な状態を持つ自前の PRNG を使う | Accepted | 2026-09-26 |
| [0007](0007-toolchain-pixi-and-mojo-nightly.md) | ツールチェーンに pixi と Mojo nightly を使う | Accepted | 2026-09-26 |
| [0008](0008-functional-core-imperative-shell.md) | 関数型コア・命令型シェルで構成する | Accepted | 2026-09-26 |
