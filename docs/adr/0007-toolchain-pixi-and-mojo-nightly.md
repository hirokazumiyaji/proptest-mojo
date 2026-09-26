# ADR-0007: ツールチェーンに pixi と Mojo nightly を使う

- 状態: Accepted
- 日付: 2026-09-26
- 関連: Milestone M0

## 文脈

Mojo は言語仕様の変化が速く、安定版と nightly で構文や標準ライブラリが異なる。
本プロジェクトは現行の構文（`def` のみ、`comptime`、統合クロージャ、`std.` import）を前提に設計している（ADR-0003〜0005 の検証は `mojo 1.2.0.dev2026092605` で行った）。
また、`mojo test` サブコマンドは廃止されており、テストは `std.testing.TestSuite` を使う実行ファイルとして書く。

## 決定

- 環境管理に pixi を使い、チャネルは `https://conda.modular.com/max-nightly` と `conda-forge` とする。
- `pixi.lock` をコミットし、Mojo のバージョンを固定する。更新は専用の PR で行い、全テストが通ることを確認する。
- テストは `tests/` 以下の `test_*.mojo` を `mojo run -I src` で実行し、各ファイルは `TestSuite.discover_tests` で自身のテストを実行する。`pixi run test` タスクで全ファイルを実行する。
- CI は GitHub Actions で Linux と macOS の両方で実行する。

## 検討した代替案

- 安定版 Mojo を使う: 本設計で使う言語機能の一部が安定版にない、または構文が異なる。
- uv（pip）でのインストール: pixi のほうが Modular の公式手順に沿い、ロックファイルでの固定が容易。

## 結果

- nightly の破壊的変更で壊れることがある。ロックファイルで固定し、更新を意図的に行うことで制御する。
- 安定版がこのプロジェクトの要件を満たした時点で、安定版への移行を別 ADR で検討する。
