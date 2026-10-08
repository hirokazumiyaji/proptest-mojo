from proptest.prng import (
    INDEX_TAG,
    SEED_TAG,
    SplitMix64,
    Xoshiro256StarStar,
    derive,
)
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


def test_derive_golden_stream() raises:
    # Goldens from the domain-separated derive algorithm in prng.mojo
    # (SEED_TAG/INDEX_TAG + rotl-mix + finalize), cross-checked independently.
    var a = derive(UInt64(0xDEADBEEF), UInt64(7))
    assert_equal(a.next_u64(), UInt64(0x6DAA5F3DF7D8BD49))
    assert_equal(a.next_u64(), UInt64(0x325406FD4103F220))
    assert_equal(a.next_u64(), UInt64(0x2E712EDE182D2060))
    assert_equal(a.next_u64(), UInt64(0xFA6D7936A553E57E))


def test_derive_zero_zero_is_non_degenerate() raises:
    var a = derive(UInt64(0), UInt64(0))
    assert_equal(a.next_u64(), UInt64(0xFC41243C80E6428C))
    assert_equal(a.next_u64(), UInt64(0xAA22B11B74D51427))


def test_derive_differs_by_index() raises:
    var a = derive(UInt64(1), UInt64(0))
    var b = derive(UInt64(1), UInt64(1))
    for _ in range(8):
        assert_true(
            a.next_u64() != b.next_u64(),
            msg="streams for distinct indices must diverge each draw",
        )


def test_derive_does_not_collapse_swapped_or_equal_roles() raises:
    var a = derive(UInt64(3), UInt64(5))
    var b = derive(UInt64(5), UInt64(3))
    for _ in range(8):
        assert_true(
            a.next_u64() != b.next_u64(),
            msg="swapped (seed, index) must diverge",
        )
    var c = derive(UInt64(9), UInt64(9))
    var d = derive(UInt64(0), UInt64(0))
    for _ in range(8):
        assert_true(
            c.next_u64() != d.next_u64(),
            msg="distinct equal-role pairs must diverge",
        )


def test_derive_does_not_collapse_additive_aliases() raises:
    var golden = UInt64(0x9E3779B97F4A7C15)
    var a = derive(UInt64(0), UInt64(1))
    var b = derive(golden, UInt64(0))
    for _ in range(8):
        assert_true(
            a.next_u64() != b.next_u64(),
            msg="additive aliases of (seed, index) must diverge",
        )


def test_derive_does_not_collapse_tag_swap_symmetry() raises:
    # derive(a, b) must not equal derive(b ^ C, a ^ C) for C = SEED_TAG ^ INDEX_TAG.
    var c = SEED_TAG ^ INDEX_TAG
    var a = UInt64(3)
    var b = UInt64(5)
    var left = derive(a, b)
    var right = derive(b ^ c, a ^ c)
    assert_true(
        (left.s0 ^ right.s0)
        | (left.s1 ^ right.s1)
        | (left.s2 ^ right.s2)
        | (left.s3 ^ right.s3)
        != 0,
        msg="tag-swap symmetry must not collapse streams",
    )


def test_next_below_stays_in_range_and_varies() raises:
    var rng = derive(UInt64(42), UInt64(0))
    assert_equal(rng.next_below(UInt64(1)), UInt64(0))
    var seen0 = False
    var seen_nonzero = False
    for _ in range(256):
        var v = rng.next_below(UInt64(10))
        assert_true(v < UInt64(10), msg="next_below(10) must be in [0, 10)")
        if v == 0:
            seen0 = True
        else:
            seen_nonzero = True
    assert_true(seen0 and seen_nonzero, msg="next_below must not be degenerate")
    var wide = UInt64(1) << UInt64(40)
    assert_true(
        rng.next_below(wide) < wide, msg="next_below must honor wide bounds"
    )
    assert_true(rng.next_below(UInt64(256)) < UInt64(256))
    # Force the rejection branch: s1 == 0 makes the first raw draw 0, which is
    # below threshold for this bound, so the loop must draw again.
    var almost_max = UInt64(0xFFFFFFFFFFFFFFFD)
    var forced_reject = Xoshiro256StarStar(
        s0=UInt64(1), s1=UInt64(0), s2=UInt64(0), s3=UInt64(0)
    )
    assert_equal(forced_reject.next_below(almost_max), UInt64(5760))


def test_next_below_rejects_zero_bound() raises:
    var rng = derive(UInt64(1), UInt64(0))
    var raised = False
    try:
        _ = rng.next_below(UInt64(0))
    except:
        raised = True
    assert_true(raised, msg="next_below(0) must raise")


def test_next_float64_matches_mantissa_conversion() raises:
    var raw_rng = Xoshiro256StarStar(
        s0=UInt64(0x0123456789ABCDEF),
        s1=UInt64(7),
        s2=UInt64(9),
        s3=UInt64(11),
    )
    var float_rng = Xoshiro256StarStar(
        s0=UInt64(0x0123456789ABCDEF),
        s1=UInt64(7),
        s2=UInt64(9),
        s3=UInt64(11),
    )
    var raw = raw_rng.next_u64()
    var expected = Float64(raw >> UInt64(11)) * (1.0 / 9007199254740992.0)
    assert_equal(float_rng.next_float64(), expected)


def test_next_float64_in_unit_interval() raises:
    var rng = derive(UInt64(99), UInt64(3))
    for _ in range(64):
        var x = rng.next_float64()
        assert_true(x >= 0.0, msg="float must be >= 0")
        assert_true(x < 1.0, msg="float must be < 1")


def test_all_zero_state_is_rewritten() raises:
    var rng = Xoshiro256StarStar(
        s0=UInt64(0), s1=UInt64(0), s2=UInt64(0), s3=UInt64(0)
    )
    assert_equal(rng.s0, UInt64(1))
    assert_equal(rng.s1, UInt64(0))
    assert_equal(rng.s2, UInt64(0))
    assert_equal(rng.s3, UInt64(0))
    # Rewritten state is (1, 0, 0, 0): s1 == 0, so the first draw is 0.
    assert_equal(rng.next_u64(), UInt64(0))
    # Second draw: rotl(s1*5, 7)*9 with s1==1 → rotl(5,7)*9 = 640*9 = 5760.
    assert_equal(rng.next_u64(), UInt64(5760))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
