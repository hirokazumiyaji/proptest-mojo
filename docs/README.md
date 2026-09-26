# ドキュメント運用ルール

このリポジトリのドキュメントは、性質の異なる 2 種類に分けて管理します。

| 種類 | 置き場所 | 性質 | 更新方法 |
|------|----------|------|----------|
| 設計書（Specs） | `docs/specs/` | **現在** のシステムを表す | 実装変更と同じ PR で書き換える。過去の記述は残さない |
| ADR | `docs/adr/` | **その時点** の判断の記録（履歴） | 判断ごとに新規ファイルを追加する。承認後は本文を書き換えない |

## Specs（`docs/specs/`）

- 常に `main` の実装と一致させます。実装と食い違う記述はバグとして扱います。
- 未実装の機能は「計画中（Planned）」と明記して記述してよいです。実装時に表記を外します。
- 判断の経緯や却下した代替案は書きません。経緯は ADR に書き、Specs からはリンクします。

## ADR（`docs/adr/`）

- ファイル名は `NNNN-kebab-case-title.md`（4 桁の連番）です。
- 雛形は [`docs/adr/template.md`](adr/template.md) を使います。
- 状態は `Proposed` → `Accepted` →（必要なら）`Superseded by ADR-NNNN` / `Deprecated` と遷移します。
- 承認済み ADR で変更してよいのは「状態」行と、置き換え先へのリンクだけです。判断を変えるときは新しい ADR を起こします。
- ADR を追加したら [`docs/adr/README.md`](adr/README.md) の索引に 1 行追加します。

## 一時的なドキュメント

作業メモ、TODO リスト、調査の下書き、スパイクのコードなどはコミットしません。
次の場所に置けば `.gitignore` で除外されます。

- `tmp/`、`scratch/`
- `tasks/`、`.claude/tasks/`
- `*.local.md`

残す価値がある結論は、Specs・ADR・GitHub Issue のいずれかに書き写してから破棄します。

## タスク管理

タスクは GitHub Issues と Milestones で管理します。ドキュメント内に TODO リストは持ちません。
Issue には関連する Specs / ADR へのリンクと受け入れ条件を書きます。
