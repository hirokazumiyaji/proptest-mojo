from proptest.prng import SplitMix64, Xoshiro256StarStar, derive
from std.testing import assert_equal, assert_true, TestSuite


def test_splitmix64_reference_vector() raises:
    # Vectors from the public-domain SplitMix64 reference (seed = 0).
    var sm = SplitMix64(seed=UInt64(0))
    assert_equal(sm.next_u64(), UInt64(0xE220A8397B1DCDAF))
    assert_equal(sm.next_u64(), UInt64(0x6E789E6AA1B965F4))
    assert_equal(sm.next_u64(), UInt64(0x06C45D188009454F))
    assert_equal(sm.next_u64(), UInt64(0xF88BB8A8724C81EC))
    assert_equal(sm.next_u64(), UInt64(0x1B39896A51A8749B))
    assert_equal(sm.next_u64(), UInt64(0x53CB9F0C747EA2EA))


def test_xoshiro256starstar_reference_vector() raises:
    # State = first four SplitMix64 outputs from seed 1; then xoshiro256** draws.
    var rng = Xoshiro256StarStar.from_seed(UInt64(1))
    assert_equal(rng.s0, UInt64(0x910A2DEC89025CC1))
    assert_equal(rng.s1, UInt64(0xBEEB8DA1658EEC67))
    assert_equal(rng.s2, UInt64(0xF893A2EEFB32555E))
    assert_equal(rng.s3, UInt64(0x71C18690EE42C90B))
    assert_equal(rng.next_u64(), UInt64(0xB3F2AF6D0FC710C5))
    assert_equal(rng.next_u64(), UInt64(0x853B559647364CEA))
    assert_equal(rng.next_u64(), UInt64(0x92F89756082A4514))
    assert_equal(rng.next_u64(), UInt64(0x642E1C7BC266A3A7))
    assert_equal(rng.next_u64(), UInt64(0xB27A48E29A233673))


def test_derive_is_deterministic() raises:
    var a = derive(UInt64(0xDEADBEEF), UInt64(7))
    var b = derive(UInt64(0xDEADBEEF), UInt64(7))
    for _ in range(32):
        assert_equal(a.next_u64(), b.next_u64())


def test_derive_differs_by_index() raises:
    var a = derive(UInt64(1), UInt64(0))
    var b = derive(UInt64(1), UInt64(1))
    var saw_diff = False
    for _ in range(8):
        if a.next_u64() != b.next_u64():
            saw_diff = True
            break
    assert_true(saw_diff, msg="streams for distinct indices must diverge")


def test_derive_does_not_collapse_additive_aliases() raises:
    # (s, i) must not share a stream with (s + i * golden, 0).
    var golden = UInt64(0x9E3779B97F4A7C15)
    var a = derive(UInt64(0), UInt64(1))
    var b = derive(golden, UInt64(0))
    var saw_diff = False
    for _ in range(8):
        if a.next_u64() != b.next_u64():
            saw_diff = True
            break
    assert_true(saw_diff, msg="additive aliases of (seed, index) must diverge")


def test_next_below_stays_in_range() raises:
    var rng = derive(UInt64(42), UInt64(0))
    assert_equal(rng.next_below(UInt64(0)), UInt64(0))
    assert_equal(rng.next_below(UInt64(1)), UInt64(0))
    for _ in range(256):
        var v = rng.next_below(UInt64(10))
        assert_true(v < UInt64(10), msg="next_below(10) must be in [0, 10)")


def test_next_float64_matches_mantissa_conversion() raises:
    var raw_rng = Xoshiro256StarStar(
        UInt64(0x0123456789ABCDEF), UInt64(7), UInt64(9), UInt64(11)
    )
    var float_rng = Xoshiro256StarStar(
        UInt64(0x0123456789ABCDEF), UInt64(7), UInt64(9), UInt64(11)
    )
    var raw = raw_rng.next_u64()
    var expected = Float64(raw >> 11) * (1.0 / 9007199254740992.0)
    assert_equal(float_rng.next_float64(), expected)


def test_next_float64_in_unit_interval() raises:
    var rng = derive(UInt64(99), UInt64(3))
    for _ in range(64):
        var x = rng.next_float64()
        assert_true(x >= 0.0, msg="float must be >= 0")
        assert_true(x < 1.0, msg="float must be < 1")


def test_all_zero_state_is_rewritten() raises:
    var rng = Xoshiro256StarStar(UInt64(0), UInt64(0), UInt64(0), UInt64(0))
    assert_equal(rng.s0, UInt64(1))
    # Rewritten state is (1, 0, 0, 0): s1 == 0, so the first draw is 0.
    assert_equal(rng.next_u64(), UInt64(0))
    assert_equal(rng.next_u64(), UInt64(5760))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
