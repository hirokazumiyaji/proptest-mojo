# Documentation Guidelines

This repository has three types of documentation, each with a distinct purpose.

| Type | Location | Purpose | How to update |
|------|----------|---------|---------------|
| Specifications (Specs) | `docs/specs/` | Describe the **current** system | Update in the same PR as implementation changes. Remove outdated descriptions. |
| ADRs | `docs/adr/` | Record decisions made **at a point in time** | Add a new file for each decision. Do not rewrite the decision after acceptance. |
| Guides | `docs/guide/` | Explain how to use the project | Update in the same PR when the public API changes. Mark unimplemented features as planned. |

## Specs (`docs/specs/`)

- Keep Specs consistent with the implementation on `main`. Treat conflicting descriptions as bugs.
- Planned features may be documented as **Planned**. Remove that label when the feature is implemented.
- Do not include decision history or rejected alternatives. Record those in ADRs and link to them from the Specs.

## ADRs (`docs/adr/`)

- Name files `NNNN-kebab-case-title.md`, using a four-digit sequence number.
- Use the [ADR template](adr/template.md).
- Statuses progress from `Proposed` to `Accepted`, and may later become `Superseded by ADR-NNNN` or `Deprecated`.
- In an accepted ADR, only change the status line and links to its replacement. Record a changed decision in a new ADR.
- When adding an ADR, add a row to the [ADR index](adr/README.md).

## Temporary documents

Do not commit work notes, TODO lists, research drafts, or spike code. Put them in one of these `.gitignore`d locations:

- `tmp/`, `scratch/`
- `tasks/`, `.claude/tasks/`
- `*.local.md`

Move conclusions worth keeping into the Specs, an ADR, or a GitHub Issue before discarding the temporary document.

## Task management

Manage tasks with GitHub Issues and Milestones. Do not keep TODO lists in documentation. Include links to relevant Specs or ADRs and acceptance criteria in each issue.
