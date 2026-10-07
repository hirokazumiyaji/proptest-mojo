"""Value-column serialization for choice sequences.

Per `docs/specs/choice-sequence.md`, only the value column is stored:
each value is encoded as an unsigned LEB128 integer, the bytes are
concatenated, and the result is Base64-encoded. Kinds and bounds are
recomputed by strategies on replay, so they are not stored. Decoding
rebuilds a `ChoiceSequence` with maximal bounds; replay clamps each
value to the bound the strategy currently requires, keeping shrunken
prefixes playable after earlier choices move their bounds.
"""

from std.base64 import b64decode, b64encode

from proptest.choice import ChoiceKind, ChoiceNode, ChoiceSequence


def encode_values(values: List[UInt64]) -> String:
    """Encode values as concatenated unsigned LEB128, Base64-encoded."""
    var raw = List[UInt8]()
    for i in range(len(values)):
        var rest = values[i]
        while True:
            var byte = UInt8(rest & UInt64(0x7F))
            rest >>= UInt64(7)
            if rest != UInt64(0):
                raw.append(byte | UInt8(0x80))
            else:
                raw.append(byte)
                break
    return b64encode(raw)


def decode_values(encoded: String) raises -> List[UInt64]:
    """Decode the output of `encode_values`, rejecting malformed input."""
    var raw = b64decode(encoded)
    var out = List[UInt64]()
    var value = UInt64(0)
    var shift = 0
    for i in range(len(raw)):
        var byte = raw[i]
        var continued = (byte & UInt8(0x80)) != UInt8(0)
        var low = UInt64(byte & UInt8(0x7F))
        if shift == 63 and (continued or low > UInt64(1)):
            raise Error("encoding: LEB128 overflows UInt64")
        value |= low << UInt64(shift)
        if continued:
            shift += 7
        else:
            out.append(value)
            value = UInt64(0)
            shift = 0
    if shift != 0:
        raise Error("encoding: truncated LEB128 sequence")
    return out^


def encode_sequence(seq: ChoiceSequence) -> String:
    """Encode the value column of `seq`, ignoring kinds and bounds."""
    return encode_values(seq.values())


def decode_sequence(encoded: String) raises -> ChoiceSequence:
    """Decode into a sequence replayable under any bounds.

    Nodes use maximal bounds so replay preserves every decoded value
    unless the drawing strategy requires a smaller bound, in which
    case `TestCase` clamps as usual.
    """
    var values = decode_values(encoded)
    var seq = ChoiceSequence()
    for i in range(len(values)):
        seq.append(
            ChoiceNode(
                ChoiceKind.INTEGER,
                values[i],
                UInt64(0xFFFFFFFFFFFFFFFF),
                Bool(False),
            )
        )
    return seq^
