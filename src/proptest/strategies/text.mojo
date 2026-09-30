"""Text and byte-string strategies over an ordered codepoint space.

Implements the `text` / `bytes` rows of `docs/specs/strategies.md`
(ADR-0003, ADR-0008).

Codepoints are ordered with `'0'` first, then the remaining ASCII
alphanumerics, then every other valid codepoint in numeric order. The
decoder skips surrogates arithmetically, so `chr` only ever sees valid
codepoints and every generated `String` is valid UTF-8. Length uses the
same continue-flag encoding as `lists`, so span deletion removes one
character and shrinking drives text toward `min_size` copies of the
alphabet's first character.
"""

from proptest.strategy import Strategy
from proptest.testcase import TestCase

comptime _TEXT_ELEMENT_LABEL = UInt64(0x74657874456C656D)
comptime _BYTES_ELEMENT_LABEL = UInt64(0x62797465456C656D)
comptime _MAX_CODEPOINT_RANK = UInt64(1112063)


def _default_average_size(min_size: Int, max_size: Int) -> Float64:
    # min(max(min_size * 2, min_size + 5), (min_size + max_size) / 2).
    var lo = min_size * 2
    var shifted = min_size + 5
    if shifted > lo:
        lo = shifted
    var mid = Float64(min_size + max_size) / 2.0
    var lof = Float64(lo)
    if lof < mid:
        return lof
    return mid


def decode_codepoint_choice(choice: UInt64) -> Int:
    """Map a rank onto a valid Unicode codepoint, simplest first.

    Rank 0 is `'0'`; ranks 1-61 are the remaining ASCII alphanumerics in
    codepoint order; higher ranks are every other valid codepoint in
    numeric order with surrogates removed. Smaller ranks therefore draw
    simpler characters, so shrinking only needs to lower choices.
    Precondition: `choice <= 1112063`.
    """
    if choice < UInt64(10):
        return Int(UInt64(0x30) + choice)
    if choice < UInt64(36):
        return Int(UInt64(0x41) + (choice - UInt64(10)))
    if choice < UInt64(62):
        return Int(UInt64(0x61) + (choice - UInt64(36)))
    var rest = choice - UInt64(62)
    if rest < UInt64(48):
        return Int(rest)
    if rest < UInt64(55):
        return Int(rest - UInt64(48) + UInt64(0x3A))
    if rest < UInt64(61):
        return Int(rest - UInt64(55) + UInt64(0x5B))
    if rest < UInt64(55234):
        return Int(rest - UInt64(61) + UInt64(0x7B))
    return Int(rest - UInt64(55234) + UInt64(0xE000))


@fieldwise_init
struct Text(Strategy):
    """Strings with codepoint count in `[min_size, max_size]`.

    An empty `alphabet` draws from the default codepoint ordering;
    otherwise each character is drawn from `alphabet` with index 0
    simplest.
    """

    comptime Value = String
    var alphabet: List[String]
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def draw(self, mut tc: TestCase) raises -> String:
        var out = String("")
        var count = 0
        var p_continue: Float64 = 0.0
        if self.average_size > 0.0:
            p_continue = self.average_size / (1.0 + self.average_size)
        var bound = _MAX_CODEPOINT_RANK
        if len(self.alphabet) > 0:
            bound = UInt64(len(self.alphabet) - 1)
        while True:
            tc.start_span(_TEXT_ELEMENT_LABEL)
            try:
                var cont: Bool
                if count >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif count < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
                if not cont:
                    tc.stop_span(discard=True)
                    break
                if len(self.alphabet) > 0:
                    var index = tc.draw_integer(bound)
                    out += self.alphabet[Int(index)]
                else:
                    var rank = tc.draw_integer(bound)
                    out += chr(decode_codepoint_choice(rank))
                count += 1
                tc.stop_span()
            except e:
                tc.stop_span()
                raise e
        return out^


def text(
    alphabet: String = "",
    min_size: Int = 0,
    max_size: Int = 32,
    average_size: Float64 = -1.0,
) raises -> Text:
    """Strategy drawing `String` with codepoint count in `[min_size, max_size]`.

    With no `alphabet`, characters follow the default codepoint ordering
    (`'0'` first, then ASCII alphanumerics, then the rest of Unicode
    without surrogates); otherwise characters come from `alphabet` with
    its first character simplest. All-zero choices draw `min_size`
    copies of the simplest character. Raises when the bounds are empty.
    """
    if min_size < 0:
        raise Error("text: min_size must be >= 0")
    if max_size < min_size:
        raise Error("text: max_size must be >= min_size")
    var chars = List[String]()
    for point in alphabet.codepoints():
        var one = String(point)
        var seen = False
        for i in range(len(chars)):
            if chars[i] == one:
                seen = True
                break
        if not seen:
            chars.append(one^)
    var avg = average_size
    if avg < 0.0:
        avg = _default_average_size(min_size, max_size)
    if avg < 0.0:
        raise Error("text: average_size must be >= 0")
    return Text(chars^, min_size, max_size, avg)


@fieldwise_init
struct Bytes(Strategy):
    """Byte strings with length in `[min_size, max_size]`."""

    comptime Value = List[UInt8]
    var min_size: Int
    var max_size: Int
    var average_size: Float64

    def draw(self, mut tc: TestCase) raises -> List[UInt8]:
        var out = List[UInt8]()
        var p_continue: Float64 = 0.0
        if self.average_size > 0.0:
            p_continue = self.average_size / (1.0 + self.average_size)
        while True:
            tc.start_span(_BYTES_ELEMENT_LABEL)
            try:
                var cont: Bool
                if len(out) >= self.max_size:
                    _ = tc.forced_integer(UInt64(0), UInt64(1))
                    cont = False
                elif len(out) < self.min_size:
                    _ = tc.forced_integer(UInt64(1), UInt64(1))
                    cont = True
                else:
                    cont = tc.draw_boolean(p_continue)
                if not cont:
                    tc.stop_span(discard=True)
                    break
                var byte = tc.draw_integer(UInt64(255))
                tc.stop_span()
                out.append(UInt8(byte))
            except e:
                tc.stop_span()
                raise e
        return out^


def bytes(
    min_size: Int = 0,
    max_size: Int = 32,
    average_size: Float64 = -1.0,
) raises -> Bytes:
    """Strategy drawing `List[UInt8]` with length in `[min_size, max_size]`.

    All-zero choices draw `min_size` zero bytes. Raises when the bounds
    are empty.
    """
    if min_size < 0:
        raise Error("bytes: min_size must be >= 0")
    if max_size < min_size:
        raise Error("bytes: max_size must be >= min_size")
    var avg = average_size
    if avg < 0.0:
        avg = _default_average_size(min_size, max_size)
    if avg < 0.0:
        raise Error("bytes: average_size must be >= 0")
    return Bytes(min_size, max_size, avg)
