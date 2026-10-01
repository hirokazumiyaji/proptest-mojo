from proptest import (
    Settings,
    TestCase,
    bytes,
    decode_codepoint_choice,
    for_all,
    text,
)
from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence
from proptest.prng import derive
from proptest.strategy import Strategy
from std.testing import TestSuite, assert_equal, assert_true


def _empty() -> TestCase:
    return TestCase.replaying(ChoiceSequence())


def _generating(seed: UInt64) -> TestCase:
    return TestCase.generating(derive(seed, UInt64(0)))


def _draw_empty[S: Strategy](strategy: S) raises -> S.Value:
    var tc = _empty()
    return tc.draw(strategy)


def _draw_replaying[
    S: Strategy
](strategy: S, *values: UInt64) raises -> S.Value:
    var prefix = ChoiceSequence()
    for v in values:
        prefix.append(
            ChoiceNode(ChoiceKind.INTEGER, v, UInt64(100), Bool(False))
        )
    var tc = TestCase.replaying(prefix^)
    return tc.draw(strategy)


def _codepoint_count(s: String) -> Int:
    var n = 0
    for _ in s.codepoints():
        n += 1
    return n


def _is_valid_utf8(s: String) -> Bool:
    var raw = s.as_bytes()
    var i = 0
    while i < len(raw):
        var b = Int(raw[i])
        if b < 0x80:
            i += 1
            continue
        var extra = 0
        var lo = 0x80
        var hi = 0xBF
        if b < 0xC2:
            return False
        elif b < 0xE0:
            extra = 1
        elif b < 0xF0:
            extra = 2
            if b == 0xE0:
                lo = 0xA0
            elif b == 0xED:
                hi = 0x9F
        elif b < 0xF5:
            extra = 3
            if b == 0xF0:
                lo = 0x90
            elif b == 0xF4:
                hi = 0x8F
        else:
            return False
        if i + extra >= len(raw):
            return False
        for j in range(extra):
            var c = Int(raw[i + 1 + j])
            var floor = 0x80
            var ceiling = 0xBF
            if j == 0:
                floor = lo
                ceiling = hi
            if c < floor or c > ceiling:
                return False
        i += 1 + extra
    return True


def _all_codepoints_valid(s: String) -> Bool:
    for point in s.codepoints():
        var v = Int(point)
        if v < 0 or v > 0x10FFFF:
            return False
        if 0xD800 <= v and v <= 0xDFFF:
            return False
    return True


def _fails_when_contains_a(mut tc: TestCase) raises:
    var s = tc.draw(text(alphabet="cbaxyz", min_size=0, max_size=8), "s")
    if "a" in s:
        raise Error("contains a: " + s)


def _fails_when_nonempty_bytes(mut tc: TestCase) raises:
    var bs = tc.draw(bytes(min_size=0, max_size=8), "bs")
    if len(bs) > 0:
        raise Error("nonempty: " + String(bs))


def test_decode_rank_zero_is_zero() raises:
    assert_equal(decode_codepoint_choice(UInt64(0)), 0x30)
    assert_equal(decode_codepoint_choice(UInt64(9)), 0x39)
    assert_equal(decode_codepoint_choice(UInt64(10)), 0x41)
    assert_equal(decode_codepoint_choice(UInt64(35)), 0x5A)
    assert_equal(decode_codepoint_choice(UInt64(36)), 0x61)
    assert_equal(decode_codepoint_choice(UInt64(61)), 0x7A)


def test_decode_first_62_are_ascii_alnum() raises:
    var out = String("")
    for rank in range(62):
        out += chr(decode_codepoint_choice(UInt64(rank)))
    assert_equal(
        out,
        String(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqr"
            + "stuvwxyz"
        ),
    )


def test_decode_skips_surrogates_at_boundary() raises:
    assert_equal(decode_codepoint_choice(UInt64(62)), 0)
    assert_equal(decode_codepoint_choice(UInt64(62 + 47)), 0x2F)
    assert_equal(decode_codepoint_choice(UInt64(62 + 48)), 0x3A)
    assert_equal(decode_codepoint_choice(UInt64(62 + 55233)), 0xD7FF)
    assert_equal(decode_codepoint_choice(UInt64(62 + 55234)), 0xE000)
    assert_equal(decode_codepoint_choice(UInt64(1112063)), 0x10FFFF)


def test_decode_never_yields_surrogate_or_out_of_range() raises:
    for rank in range(1112064):
        var v = decode_codepoint_choice(UInt64(rank))
        assert_true(0 <= v and v <= 0x10FFFF, msg="codepoint in range")
        assert_true(not (0xD800 <= v and v <= 0xDFFF), msg="no surrogates")


def test_text_all_zero_gives_min_simplest() raises:
    assert_equal(_draw_empty(text(min_size=2, max_size=5)), String("00"))
    assert_equal(_draw_empty(text()), String(""))
    assert_equal(
        _draw_empty(text(alphabet="bca", min_size=3, max_size=3)),
        String("bbb"),
    )


def test_text_rank_choice_draws_expected_char() raises:
    # forced_integer for the continue flag now advances the replay cursor,
    # so each element consumes one slot before the rank draw.
    assert_equal(
        _draw_replaying(text(min_size=1, max_size=1), UInt64(1), UInt64(0)),
        String("0"),
    )
    assert_equal(
        _draw_replaying(text(min_size=1, max_size=1), UInt64(1), UInt64(36)),
        String("a"),
    )
    assert_equal(
        _draw_replaying(
            text(alphabet="xyz", min_size=1, max_size=1),
            UInt64(1),
            UInt64(0),
        ),
        String("x"),
    )
    assert_equal(
        _draw_replaying(
            text(alphabet="xyz", min_size=1, max_size=1),
            UInt64(1),
            UInt64(2),
        ),
        String("z"),
    )


def test_text_length_and_validity_across_seeds() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var s = tc.draw(text(min_size=1, max_size=6))
        var n = _codepoint_count(s)
        assert_true(1 <= n and n <= 6, msg="codepoint count stays in bounds")
        assert_true(_is_valid_utf8(s), msg="bytes are valid UTF-8")
        assert_true(
            _all_codepoints_valid(s), msg="no surrogates or range error"
        )


def test_text_alphabet_restricts_characters() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var s = tc.draw(text(alphabet="ab", min_size=0, max_size=8))
        assert_true(
            _codepoint_count(s) <= 8, msg="codepoint count stays in bounds"
        )
        for point in s.codepoints():
            var one = String(point)
            assert_true(
                one == String("a") or one == String("b"),
                msg="characters come from the alphabet",
            )


def test_text_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(9))
    var first = a.draw(text(min_size=0, max_size=8))
    var b = _generating(UInt64(9))
    var second = b.draw(text(min_size=0, max_size=8))
    assert_equal(first, second)
    assert_equal(a.choices, b.choices)


def test_text_invalid_bounds_raise() raises:
    var raised = False
    try:
        _ = text(min_size=5, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="max below min must raise")
    raised = False
    try:
        _ = text(min_size=-1, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="negative min must raise")


def test_text_shrinks_no_a_to_a() raises:
    var report = String("")
    try:
        for_all(
            _fails_when_contains_a, Settings(seed=UInt64(1), max_examples=100)
        )
    except e:
        report = String(e)
    assert_true(("s = a\n" in report), msg="expected s = a, got: " + report)


def test_bytes_all_zero_gives_min_zeros() raises:
    var xs = _draw_empty(bytes(min_size=2, max_size=5))
    assert_equal(len(xs), 2)
    assert_equal(xs[0], UInt8(0))
    assert_equal(xs[1], UInt8(0))
    assert_equal(len(_draw_empty(bytes())), 0)


def test_bytes_values_and_length_within_bounds() raises:
    for seed in range(50):
        var tc = _generating(UInt64(seed))
        var xs = tc.draw(bytes(min_size=1, max_size=6))
        assert_true(1 <= len(xs) and len(xs) <= 6, msg="length stays in bounds")
        for i in range(len(xs)):
            assert_true(UInt8(0) <= xs[i] and xs[i] <= UInt8(255))


def test_bytes_deterministic_for_same_seed() raises:
    var a = _generating(UInt64(9))
    var first = a.draw(bytes(min_size=0, max_size=8))
    var b = _generating(UInt64(9))
    var second = b.draw(bytes(min_size=0, max_size=8))
    assert_equal(first, second)
    assert_equal(a.choices, b.choices)


def test_bytes_invalid_bounds_raise() raises:
    var raised = False
    try:
        _ = bytes(min_size=5, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="max below min must raise")
    raised = False
    try:
        _ = bytes(min_size=-1, max_size=3)
    except:
        raised = True
    assert_true(raised, msg="negative min must raise")


def test_bytes_shrinks_nonempty_to_single_zero() raises:
    var report = String("")
    try:
        for_all(
            _fails_when_nonempty_bytes,
            Settings(seed=UInt64(1), max_examples=100),
        )
    except e:
        report = String(e)
    assert_true(
        ("bs = [0]\n" in report), msg="expected bs = [0], got: " + report
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
