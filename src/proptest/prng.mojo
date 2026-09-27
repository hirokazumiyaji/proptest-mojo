"""Explicit-state PRNGs for deterministic example generation.

Implements SplitMix64 (seed expansion) and xoshiro256** (generation),
plus pure `derive(run_seed, index)` for per-example streams (ADR-0006).

All UInt64 arithmetic is wrapping (as required by the reference algorithms).
"""

comptime _FLOAT_SCALE = 1.0 / 9007199254740992.0
comptime _SEED_TAG = UInt64(0x243F6A8885A308D3)
comptime _INDEX_TAG = UInt64(0x13198A2E03707344)


def _rotl(x: UInt64, shift: UInt64) -> UInt64:
    # Precondition: 0 < shift < 64 (call sites use constants 7 and 45).
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

    Invariant: the four state words must not all be zero. Prefer `from_seed`
    / `derive`; raw construction is keyword-only so word order is explicit.
    An all-zero state is rewritten to `(1, 0, 0, 0)`.
    """

    var s0: UInt64
    var s1: UInt64
    var s2: UInt64
    var s3: UInt64

    def __init__(out self, *, s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64):
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
        return Self(s0=s0, s1=s1, s2=s2, s3=s3)

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

    def next_below(mut self, bound: UInt64) raises -> UInt64:
        """Unbiased integer in `[0, bound)`.

        Requires `bound >= 1`. `bound == 1` always yields 0.
        """
        if bound == 0:
            raise Error("next_below: bound must be >= 1")
        if bound == 1:
            return 0
        # Reject values in the incomplete residue class at the top of UInt64.
        var threshold = (UInt64(0) - bound) % bound
        while True:
            var r = self.next_u64()
            if r >= threshold:
                return r % bound

    def next_float64(mut self) -> Float64:
        """Uniform value in `[0.0, 1.0)` from the top 53 bits."""
        var mantissa = self.next_u64() >> UInt64(11)
        return Float64(mantissa) * _FLOAT_SCALE


def derive(run_seed: UInt64, index: UInt64) -> Xoshiro256StarStar:
    """Purely derive a per-example PRNG from `(run_seed, example_index)`.

    Domain-separated SplitMix64 expansions are XOR-mixed, then finalized so
    pairs like `(s, i)` / `(i, s)` and `(s, s)` (including `(0, 0)`) do not
    collapse to a shared or all-zero stream.
    """
    var seed_sm = SplitMix64(seed=run_seed ^ _SEED_TAG)
    var index_sm = SplitMix64(seed=index ^ _INDEX_TAG)
    var s0 = seed_sm.next_u64() ^ _rotl(index_sm.next_u64(), UInt64(32))
    var s1 = seed_sm.next_u64() ^ _rotl(index_sm.next_u64(), UInt64(32))
    var s2 = seed_sm.next_u64() ^ _rotl(index_sm.next_u64(), UInt64(32))
    var s3 = seed_sm.next_u64() ^ _rotl(index_sm.next_u64(), UInt64(32))
    var fin = SplitMix64(
        seed=s0
        ^ _rotl(s1, UInt64(17))
        ^ _rotl(s2, UInt64(33))
        ^ _rotl(s3, UInt64(49))
    )
    return Xoshiro256StarStar(
        s0=fin.next_u64(),
        s1=fin.next_u64(),
        s2=fin.next_u64(),
        s3=fin.next_u64(),
    )
