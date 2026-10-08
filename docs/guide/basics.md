# Basics

## The idea

A property is a condition that should hold for every input. Write it as a `def(mut TestCase) raises` function and draw values with `tc.draw`. Signal failures by raising an exception.

```mojo
from proptest import Settings, TestCase, for_all, integers

def _addition_commutes(mut tc: TestCase) raises:
    var a = tc.draw(integers(-1000, 1000), "a")
    var b = tc.draw(integers(-1000, 1000), "b")
    if a + b != b + a:
        raise Error("addition must commute")

def main() raises:
    for_all(_addition_commutes, Settings(seed=UInt64(1)))
```

`for_all` runs the property repeatedly with generated examples. If it finds a counterexample, it shrinks it and reports it as an `Error`. If no counterexample is found, it returns nothing.

## `tc.draw(strategy, label)`

Draws one value from a Strategy. The `label` is shown in failure reports. Labels make shrunk counterexamples easier to read, so use them by default.

```mojo
var x = tc.draw(integers(0, 10000), "x")
```

## `tc.assume(condition)`

States a precondition. Examples that do not satisfy it are discarded and replaced with another example.

```mojo
def _nonzero_divides(mut tc: TestCase) raises:
    var d = tc.draw(integers(-100, 100), "d")
    tc.assume(d != 0)
    if (d * 42) // d != 42:
        raise Error("division broke")
```

If too many examples are discarded, `for_all` gives up (`gave up after N examples (M rejected by assume): condition too strict`). In that case, use a narrower Strategy such as `integers(1, 100)`.

## `tc.note(message)`

Adds a note to the failure report. It is shown when replaying the shrunk counterexample.

```mojo
tc.note("checking size=" + String(len(xs)))
```

## `Settings`

Execution parameters for `for_all`. `Settings` is an immutable value type constructed with keyword arguments.

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `max_examples` | `Int` | `100` | Target number of `VALID` examples to try |
| `seed` | `Optional[UInt64]` | `None` | Seed for the whole run. If `None`, use `PROPTEST_SEED`, or the current time if that is unset |
| `max_choices` | `Int` | `8192` | Maximum choices allowed in one run. An example that exceeds this is discarded as `OVERRUN` |
| `max_shrink_evaluations` | `Int` | `5000` | Maximum number of executions during shrinking |

Set `PROPTEST_MAX_EXAMPLES` to override the default number of generated examples ([setup](setup.md)). See [replay](replay.md) for reproducing failures.

Direct `replay` (replaying a choice sequence) and an example database are planned for M4 ([Specs: Runner](../specs/runner.md)).
