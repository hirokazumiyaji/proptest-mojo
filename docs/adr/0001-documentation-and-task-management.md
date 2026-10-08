# ADR-0001: Documentation and task management policy

- Status: Accepted
- Date: 2026-09-26
- Related: [docs/README.md](../README.md)

## Context

From the start of the project, we wanted to preserve both the current design and the reasons behind it. Combining them in one document would force readers of the current design to skip past historical discussions, while rewriting the document would erase the history. Committing working notes and draft plans would also make it unclear which information is authoritative.

## Decision

- Treat `docs/specs/` as living documents describing the **current design**. Update them in the same PR as implementation changes.
- Treat `docs/adr/` as the **decision history**. Add a numbered ADR for each decision and, after acceptance, change only its status line.
- Do not commit temporary documents (working notes, TODOs, research drafts, or spikes). Exclude `tmp/`, `scratch/`, `tasks/`, `.claude/tasks/`, and `*.local.md` in `.gitignore`.
- Track tasks with GitHub Issues and Milestones. Do not keep TODO lists in documentation.

## Alternatives Considered

- Keep a change history section in a single design document: current design and history become mixed, making both harder to read.
- Use ADRs alone: readers would have to read every ADR in sequence and synthesize the current design from the changes.
- Track tasks in repository Markdown: linking tasks to PRs and commits and visualizing progress are less effective.

## Consequences

- Specs must stay up to date, so PR reviews need to check that relevant Specs were updated.
- To reverse a decision, create a new ADR and set the old ADR's status to `Superseded by ADR-NNNN`.
