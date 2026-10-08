# User Guide

Get started with property-based testing in a few minutes. For design details, see the [Specs](../specs/README.md).

## 3-minute quick start

Prerequisite: [pixi](https://pixi.sh/) must be installed.

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
pixi run mojo run -I src examples/basic.mojo < /dev/null
```

`examples/basic.mojo` demonstrates both a passing property and a property that gets shrunk. For a passing property, your test can look like this:

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

## Contents

| Page | Contents |
|------|----------|
| [setup](setup.md) | Setup: dependencies, running tests, and CI usage |
| [basics](basics.md) | Basics: `for_all`, `TestCase.draw`, `assume`, and `note` |
| [strategies](strategies.md) | Strategy reference: available and planned strategies |
| [composition](composition.md) | Composition: `map`, `filter`, `flat_map`, and custom Strategy structs |
| [shrinking](shrinking.md) | Shrinking: reading reports and writing shrink-friendly properties |
| [replay](replay.md) | Reproduction: fixed seeds and environment variables |
| [stateful](stateful.md) | State-machine testing with generated and shrunk operation sequences |

Runnable examples are in [`examples/`](../../examples/README.md). CI runs every example.
