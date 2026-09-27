"""Explicit-state PRNGs for deterministic example generation.

Implements SplitMix64 (seed expansion) and xoshiro256** (generation),
plus pure `derive(run_seed, index)` for per-example streams (ADR-0006).

All UInt64 arithmetic is wrapping (as required by the reference algorithms).
"""


def _rotl(x: UInt64, shift: UInt64) -> UInt64:
    return (x << shift) | (x >> (UInt64(64) - shift))


struct SplitMix64(Copyable, Movable):
    """64-bit SplitMix64 generator for expanding a seed into stream state."""

    var state: UInt64

    def __init__(out self, *, seed: UInt64):
        self.state = seed

    def next_u64(mut self) -> UInt64:
        self.state += UInt64(0x9E3779B97F4A7C15)
        var z = self.state
        z = (z ^ (z >> 30)) * UInt64(0xBF58476D1CE4E5B9)
        z = (z ^ (z >> 27)) * UInt64(0x94D049BB133111EB)
        return z ^ (z >> 31)


struct Xoshiro256StarStar(Copyable, Movable):
    """Xoshiro256** generator.

    Invariant: the four state words must not all be zero. Callers should treat
    the state as opaque and use `from_seed` / `derive`; the constructor rewrites
    an all-zero state to `(1, 0, 0, 0)`.
    """

    var s0: UInt64
    var s1: UInt64
    var s2: UInt64
    var s3: UInt64

    def __init__(out self, s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64):
        self.s0 = s0
        self.s1 = s1
        self.s2 = s2
        self.s3 = s3
        if (self.s0 | self.s1 | self.s2 | self.s3) == 0:
            self.s0 = 1

    @staticmethod
    def from_seed(seed: UInt64) -> Self:
        """Expand a 64-bit seed with SplitMix64 into a 256-bit xoshiro state."""
        var sm = SplitMix64(seed=seed)
        var s0 = sm.next_u64()
        var s1 = sm.next_u64()
        var s2 = sm.next_u64()
        var s3 = sm.next_u64()
        return Self(s0, s1, s2, s3)

    def next_u64(mut self) -> UInt64:
        var result = _rotl(self.s1 * UInt64(5), UInt64(7)) * UInt64(9)
        var t = self.s1 << UInt64(17)
        self.s2 ^= self.s0
        self.s3 ^= self.s1
        self.s1 ^= self.s2
        self.s0 ^= self.s3
        self.s2 ^= t
        self.s3 = _rotl(self.s3, UInt64(45))
        return result

    def next_below(mut self, bound: UInt64) -> UInt64:
        """Unbiased integer in `[0, bound)`. Returns 0 when `bound <= 1`."""
        if bound <= 1:
            return 0
        # Reject values in the incomplete residue class at the top of UInt64.
        var threshold = (UInt64(0) - bound) % bound
        while True:
            var r = self.next_u64()
            if r >= threshold:
                return r % bound

    def next_float64(mut self) -> Float64:
        """Uniform value in `[0.0, 1.0)` from the top 53 bits."""
        var mantissa = self.next_u64() >> 11
        return Float64(mantissa) * (1.0 / 9007199254740992.0)


def derive(run_seed: UInt64, index: UInt64) -> Xoshiro256StarStar:
    """Purely derive a per-example PRNG from `(run_seed, example_index)`.

    Both halves are expanded with SplitMix64 and XOR-mixed so that pairs like
    `(s, i)` and `(s + i * golden, 0)` do not collapse to the same stream.
    """
    var seed_sm = SplitMix64(seed=run_seed)
    var index_sm = SplitMix64(seed=index)
    var s0 = seed_sm.next_u64() ^ index_sm.next_u64()
    var s1 = seed_sm.next_u64() ^ index_sm.next_u64()
    var s2 = seed_sm.next_u64() ^ index_sm.next_u64()
    var s3 = seed_sm.next_u64() ^ index_sm.next_u64()
    return Xoshiro256StarStar(s0, s1, s2, s3)
