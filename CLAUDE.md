# proptest-mojo

Pure Mojo の Property-based testing ライブラリ。

## ドキュメント

- 運用ルールは `docs/README.md` に従う。
- `docs/specs/` は現在の設計。実装を変えたら同じ変更で Specs も更新する。
- 設計判断をしたら `docs/adr/` に新しい ADR を追加し、索引を更新する。承認済み ADR の本文は書き換えない。
- 一時的なメモ・計画・スパイクは `tmp/` か `.claude/tasks/` に置き、コミットしない。

## タスク

- タスクは GitHub Issues で管理する（`gh issue list`）。作業は Issue 単位でブランチを切り、PR 本文で `Closes #N` とする。

## 実装方針

- 関数型を意識する。詳細は `docs/specs/coding-guidelines.md`。
- Mojo は nightly の最新構文を使う（`def` のみ、`comptime`、`std.` import など）。
- Mojo の言語制約（クロージャを struct に保持できない等）は ADR-0005 と `docs/specs/coding-guidelines.md` を参照。

## コマンド

- `pixi run test`: `tests/**/test_*.mojo` を `mojo run -I src` で全実行
- `pixi run format`: `mojo format src tests`
- `pixi run format-check`: フォーマット済みか検査（未整形なら非 0）
- `pixi run build`: `mojo precompile` で `proptest.mojoc` を生成

CI は `.github/workflows/ci.yml`（Linux / macOS で `format-check` と `test`）。
