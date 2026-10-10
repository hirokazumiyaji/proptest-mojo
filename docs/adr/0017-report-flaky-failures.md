# ADR-0017: Report failures that do not replay as flaky

- Status: Accepted
- Date: 2026-10-10
- Related: [runner spec](../specs/runner.md)

## Context

When a generated example fails but neither the shrunk sequence nor the original sequence fails on replay, the runner used to discard the failure and continue generation. That attempt advanced none of the counters behind `max_examples` or the health checks. A property whose fresh runs always fail but whose replays always pass, such as one that depends on hidden global state, therefore never terminated, and each attempt spent up to `max_shrink_evaluations` executions.

## Decision

The generation loop raises a `Flaky` error with the example index, the failure message, and the seed as soon as a failure does not reproduce on replay. A saved database entry that no longer reproduces is still pruned silently, because it is stale rather than flaky.

## Alternatives Considered

- Count non-reproducing failures and fail after a threshold: adds a new health-check bucket and a tuning constant, while a single non-reproducing failure already shows that the property is nondeterministic.
- Keep continuing: the run can loop forever and hides the nondeterminism from the user.

## Consequences

Nondeterministic properties now fail loudly instead of passing or hanging. A property that fails rarely and nondeterministically can fail a run that previously passed. The report has no replay string, because no sequence reproduces the failure.
