"""Tests for choice-sequence serialization and `Settings.replay`.

Covers `docs/specs/choice-sequence.md` (value-column LEB128 + Base64
encoding) and `docs/specs/runner.md` (the `Reproduce with` report line
and replay-only runs). Roundtrips over generated inputs run through
`for_all` itself.
"""

from std.base64 import b64encode

from proptest import (
    ChoiceKind,
    ChoiceNode,
    ChoiceSequence,
    Settings,
    TestCase,
    decode_sequence,
    decode_values,
    encode_sequence,
    encode_values,
    for_all,
    integers,
)
from std.testing import TestSuite, assert_equal, assert_true


def _values(*values: UInt64) -> List[UInt64]:
    var out = List[UInt64]()
    for v in values:
        out.append(v)
    return out^


def _assert_values_roundtrip(values: List[UInt64]) raises:
    assert_equal(decode_values(encode_values(values)), values)


def _extract_replay(report: String) raises -> String:
    var needle = String('replay="')
    var idx = report.find(needle)
    assert_true(
        idx >= 0, msg="report must carry a replay string, got: " + report
    )
    var rest = report[byte = idx + needle.byte_length() :]
    var end = rest.find('"')
    assert_true(end >= 0, msg="replay string must be quoted: " + report)
    return String(rest[byte=0:end])


def _fails_at_1000(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def _fails_on_zero(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    if x == 0:
        raise Error("zero")


def _prop_encoding_roundtrip(mut tc: TestCase) raises:
    var count = tc.draw(integers(0, 4), "count")
    var values = List[UInt64]()
    for _ in range(count):
        values.append(UInt64(tc.draw(integers(0, 100000), "v")))
    assert_equal(decode_values(encode_values(values)), values)


def test_empty_sequence_encodes_to_empty_string() raises:
    assert_equal(encode_values(List[UInt64]()), "")
    assert_equal(len(decode_values("")), 0)
    assert_equal(len(decode_sequence("")), 0)
    assert_equal(encode_sequence(ChoiceSequence()), "")


def test_known_single_value_vectors() raises:
    assert_equal(encode_values(_values(UInt64(0))), "AA==")
    assert_equal(encode_values(_values(UInt64(1))), "AQ==")
    assert_equal(encode_values(_values(UInt64(127))), "fw==")
    assert_equal(encode_values(_values(UInt64(128))), "gAE=")
    assert_equal(encode_values(_values(UInt64(255))), "/wE=")
    assert_equal(encode_values(_values(UInt64(300))), "rAI=")
    assert_equal(encode_values(_values(UInt64(16383))), "/38=")
    assert_equal(encode_values(_values(UInt64(16384))), "gIAB")
    assert_equal(encode_values(_values(UInt64(4294967295))), "/////w8=")
    assert_equal(
        encode_values(_values(UInt64(18446744073709551615))),
        "////////////AQ==",
    )
    assert_equal(
        encode_values(_values(UInt64(0), UInt64(1), UInt64(2))), "AAEC"
    )


def test_roundtrip_covers_leb128_boundaries() raises:
    _assert_values_roundtrip(_values())
    _assert_values_roundtrip(_values(UInt64(0)))
    _assert_values_roundtrip(_values(UInt64(1), UInt64(127), UInt64(128)))
    _assert_values_roundtrip(
        _values(UInt64(255), UInt64(256), UInt64(16383), UInt64(16384))
    )
    _assert_values_roundtrip(
        _values(
            UInt64(2097151),
            UInt64(2097152),
            UInt64(4294967295),
            UInt64(4294967296),
        )
    )
    _assert_values_roundtrip(
        _values(UInt64(9223372036854775807), UInt64(18446744073709551615))
    )
    _assert_values_roundtrip(
        _values(UInt64(0), UInt64(1), UInt64(2), UInt64(300))
    )


def test_roundtrip_holds_for_generated_values() raises:
    for_all(
        _prop_encoding_roundtrip, Settings(seed=UInt64(11), max_examples=50)
    )


def test_sequence_roundtrip_keeps_values_only() raises:
    var seq = ChoiceSequence()
    seq.append(
        ChoiceNode(ChoiceKind.BOOLEAN, UInt64(1), UInt64(1), Bool(False))
    )
    seq.append(
        ChoiceNode(ChoiceKind.INTEGER, UInt64(300), UInt64(500), Bool(True))
    )
    seq.append(ChoiceNode(ChoiceKind.FLOAT, UInt64(7), UInt64(9), Bool(False)))
    var decoded = decode_sequence(encode_sequence(seq.copy()))
    assert_equal(decoded.values(), seq.values())
    for i in range(len(decoded)):
        assert_equal(decoded[i].kind, ChoiceKind.INTEGER)
        assert_equal(decoded[i].forced, False)


def test_decode_rejects_truncated_leb128() raises:
    var raw = List[UInt8]()
    raw.append(UInt8(0x80))
    var raised = False
    try:
        _ = decode_values(b64encode(raw))
    except:
        raised = True
    assert_true(raised, msg="unterminated LEB128 group must raise")


def test_decode_rejects_overflowing_leb128() raises:
    var raw = List[UInt8]()
    for _ in range(9):
        raw.append(UInt8(0xFF))
    raw.append(UInt8(0x02))
    var raised = False
    try:
        _ = decode_values(b64encode(raw))
    except:
        raised = True
    assert_true(raised, msg="value exceeding UInt64 must raise")


def test_decode_rejects_invalid_base64() raises:
    var raised = False
    try:
        _ = decode_values("!!!")
    except:
        raised = True
    assert_true(raised, msg="invalid Base64 must raise")


def test_settings_replay_renders_in_write_to() raises:
    assert_equal(
        String(Settings()),
        (
            "Settings(max_examples=100, seed=None,"
            " max_choices=8192, max_shrink_evaluations=5000,"
            " verbosity=NORMAL)"
        ),
    )
    var token = encode_values(_values(UInt64(3)))
    var with_replay = Settings(replay=token)
    assert_true(
        ('replay="' + token + '"') in String(with_replay),
        msg="Settings must show its replay string: " + String(with_replay),
    )


def test_report_carries_replay_string() raises:
    var report = String("")
    try:
        for_all(_fails_at_1000, Settings(seed=UInt64(1)))
    except e:
        report = String(e)
    assert_true(("x = 1000" in report), msg="minimal failure, got: " + report)
    var token = _extract_replay(report)
    assert_true(token.byte_length() > 0, msg="replay string must be non-empty")
    assert_equal(decode_sequence(token).values()[0], UInt64(1000))


def test_reported_replay_reproduces_same_counterexample() raises:
    var first = String("")
    try:
        for_all(_fails_at_1000, Settings(seed=UInt64(1)))
    except e:
        first = String(e)
    var token = _extract_replay(first)
    var second = String("")
    try:
        for_all(_fails_at_1000, Settings(replay=token))
    except e:
        second = String(e)
    assert_true(
        ("x = 1000" in second), msg="replay must reproduce x: " + second
    )
    assert_true(
        ("too big: x=1000" in second),
        msg="replay must reproduce the message: " + second,
    )
    assert_true(
        ("note: saw x=1000" in second),
        msg="replay must reproduce notes: " + second,
    )
    assert_true(
        (token in second), msg="replay report must echo its token: " + second
    )
    assert_true(
        ("after 1 examples, 0 shrink evaluations" in second),
        msg="replay runs once with no shrinking: " + second,
    )


def test_replay_only_does_not_generate() raises:
    var passing = encode_values(_values(UInt64(5)))
    var message = String("")
    try:
        for_all(_fails_on_zero, Settings(replay=passing))
    except e:
        message = String(e)
    assert_true(
        ("did not reproduce" in message),
        msg="passing replay must not search: " + message,
    )
    assert_true(
        not ("Falsifying example" in message),
        msg="passing replay must not report a new example: " + message,
    )


def test_invalid_replay_string_raises() raises:
    var message = String("")
    try:
        for_all(_fails_at_1000, Settings(replay=String("!!!")))
    except e:
        message = String(e)
    assert_true(
        ("invalid replay string" in message),
        msg="bad replay input must explain itself: " + message,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
