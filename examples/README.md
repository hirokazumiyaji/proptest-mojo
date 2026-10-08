# Examples

Runnable usage examples. CI runs all of them. Each example catches and displays its expected failure with `try`, so it exits with status 0.

| File | Contents | Related guide |
|------|----------|---------------|
| `basic.mojo` | Minimal usage: a passing property and one that gets shrunk | [basics](../docs/guide/basics.md) |
| `combinators.mojo` | Deriving Strategies with `map`, `filter`, and `flat_map` | [composition](../docs/guide/composition.md) |
| `lists.mojo` | An integer list built with a composite Strategy struct | [composition](../docs/guide/composition.md) |

Run the examples with:

```sh
pixi run mojo run -I src examples/basic.mojo < /dev/null
pixi run mojo run -I src examples/combinators.mojo < /dev/null
pixi run mojo run -I src examples/lists.mojo < /dev/null
```
