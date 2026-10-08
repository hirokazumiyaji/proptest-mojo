# Strategy reference

A Strategy is an immutable value that describes how to generate values. Pass it to `tc.draw`. For shared conventions such as determinism, monotonic simplicity, immutability, and locality, see [Specs: Strategy](../specs/strategies.md).

## Built-in strategies

| Strategy | Value type | Simplest values |
|----------|------------|-----------------|
| `integers(min, max)` | `Int` | Value in range closest to 0 |
| `integers_of[dtype](min, max)` | Integer scalar type | Value in range closest to 0 |
| `booleans()` | `Bool` | `False` |
| `just(value)` | `T` | The given constant; consumes no choices |
| `floats(...)` | `Float64` | `0.0`, then simpler numeric values |
| `text(...)` | `String` | Empty string, then simpler characters |
| `bytes(...)` | `List[UInt8]` | Empty sequence |
| `lists(elements, ...)` | `List[T]` | Short list with simple elements |
| `unique_lists(elements, ...)` | `List[T]` | Short list with simple elements |
| `dicts(keys, values, ...)` | `DictList[K, V]` | Empty dictionary |
| `tuples(a, b)` / `tuples(a, b, c)` | Tuple of 2 or 3 values | Each element simplified |
| `optionals(strategy)` | `Optional[T]` | `None` |
| `one_of(strategies)` / `one_of2(a, b)` | Strategy value | First strategy |
| `sampled_from(values)` | `T` | First element |
| `json_tree(...)` | `JsonValue` | `null` |

The `map`, `filter`, and `flat_map` combinators derive strategies from other strategies. See [composition](composition.md) for examples and for implementing a custom Strategy struct.

```mojo
from proptest import booleans, integers, just, lists

var any_ints = integers(-100, 100)
var flags = booleans()
var constant = just(42)
var small_lists = lists(integers(0, 10), max_size=5)
```

See [Specs: Strategy](../specs/strategies.md) for complete signatures and shrinking behavior. `Arbitrary`-based derivation is planned.
