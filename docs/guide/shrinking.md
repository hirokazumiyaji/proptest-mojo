# Shrinking

A failing example is automatically replaced with simpler choice sequences that preserve the failure (internal choice-sequence shrinking). The smallest counterexample found is reported.

## Reading the report

```text
Falsifying example (after 2 examples, 44 shrink evaluations):
  size = 2
  item = 1
  item = 0
  xs = [1, 0]
Error: unsorted: [1, 0]
Seed: 3
```

| Line | Meaning |
|------|---------|
| `after 2 examples` | Which example failed (example 0 is the simplest) |
| `44 shrink evaluations` | Number of reruns performed during shrinking |
| `label = value` | Value recorded by `tc.draw(..., "label")` in the shrunk counterexample |
| `Error: ...` | Message raised by the property |
| `Seed: 3` | Seed for reproducing the failure ([replay](replay.md)) |
| `Shrink budget exhausted ...` | If shown, the shrinking budget ran out and the result may not be minimal |

An unlabeled `draw` is displayed as `draw #N`. Messages from `tc.note` appear on `note: ...` lines.

## Writing shrink-friendly properties

1. **Add labels:** Reports will show readable counterexamples.
2. **Express the failure condition directly:** Shrinking considers only the choice sequence, so the property needs no special shrinking logic. Shrinking works automatically when smaller choices map to simpler values in the Strategy ([strategies](strategies.md)).
3. **Make custom Strategies return their simplest value for all-zero choices:** This is a convention described in [composition](composition.md). Without it, the assumption that run 0 is the simplest example no longer holds.
4. **If the budget runs out:** Increase `max_shrink_evaluations` or reduce generated data, especially the maximum size of custom collections. Increase `max_choices` if you see many `OVERRUN` results.

See [Specs: Shrinking](../specs/shrinking.md) for implementation details.
