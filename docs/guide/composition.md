# Composition

## `map`: transform values

Transform values with a pure function. Shrinking works through the base Strategy.

```mojo
from proptest.strategies.combinators import map

def double(x: Int) -> Int:
    return x * 2

var y = tc.draw(map[double](integers(0, 100)), "y")
```

## `filter`: restrict values

Allows only values that satisfy a predicate. Rejected attempts are recorded as discarded spans. If the limit (`MAX_FILTER_ATTEMPTS`) is exceeded, the example is discarded, as with `assume`.

```mojo
from proptest.strategies.combinators import filter

def is_even(x: Int) -> Bool:
    return x % 2 == 0

var z = tc.draw(filter[is_even](integers(0, 100)), "z")
```

If the condition is too strict, examples will keep being discarded. When possible, use bounds such as `integers(0, 100)` instead of filtering; this is faster.

## `flat_map`: make a Strategy depend on a value

Build an inner Strategy from an outer value. The inner Strategy's type is fixed at compile time; only its value parameters can depend on the outer value.

```mojo
from proptest import Integers
from proptest.strategies.combinators import flat_map

def capped(n: Int) -> Integers:
    return Integers(0, n)

var w = tc.draw(flat_map[capped](integers(0, 10)), "w")
```

See [`examples/combinators.mojo`](../../examples/combinators.mojo) for a runnable example.

## Custom composite Strategy structs: capture parameters

Combinators accept only thin functions, which cannot capture values. To generate values with parameters such as bounds, sizes, or character sets, implement `Strategy` on a struct that stores those parameters in fields.

```mojo
from proptest import TestCase, booleans, integers
from proptest.strategy import Strategy, kind_label

# `User` is a custom type assumed to be defined by the implementation.
@fieldwise_init
struct Users(Strategy):
    comptime Value = User
    var max_age: Int

    def span_label(self) -> UInt64:
        return kind_label("users")

    def draw(self, mut tc: TestCase) raises -> User:
        var age = tc.draw(integers(0, self.max_age), "age")
        var admin = tc.draw(booleans(), "admin")
        return User(age, admin)
```

Follow the conventions in the [Specs: Strategy](../specs/strategies.md) table. In particular, return the simplest value when all choices are zero (for example, `Users(120)` should return `User(age=0, admin=False)`) to enable shrinking. See [`examples/lists.mojo`](../../examples/lists.mojo) for a composite list example.
