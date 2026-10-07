"""Example database: persistence and replay of shrunken counterexamples.

Implements the `Example database` section of `docs/specs/runner.md`
(ADR-0010). Shrunk choice columns are stored as replay strings at
`{database_dir}/{sha256(name)[:16]}/{sha256(replay)}`; the next run
replays every stored file before generating, deleting files that no
longer fail. Hashing is a local pure SHA-256 so the layout needs no
stdlib hash API.
"""

from std.os import listdir, mkdir, remove
from std.pathlib import Path


def sha256_hex(data: String) -> String:
    """Lowercase hex SHA-256 of the UTF-8 bytes of `data` (FIPS 180-4)."""
    var message = data.as_bytes()
    var bit_length = UInt64(len(message)) * UInt64(8)
    var padded = List[UInt8]()
    for i in range(len(message)):
        padded.append(message[i])
    padded.append(UInt8(0x80))
    while len(padded) % 64 != 56:
        padded.append(UInt8(0))
    for i in range(8):
        var shift = UInt64(56) - UInt64(i) * UInt64(8)
        padded.append(UInt8((bit_length >> shift) & UInt64(0xFF)))

    var k = _sha256_round_constants()
    var h0 = UInt32(0x6A09E667)
    var h1 = UInt32(0xBB67AE85)
    var h2 = UInt32(0x3C6EF372)
    var h3 = UInt32(0xA54FF53A)
    var h4 = UInt32(0x510E527F)
    var h5 = UInt32(0x9B05688C)
    var h6 = UInt32(0x1F83D9AB)
    var h7 = UInt32(0x5BE0CD19)

    var blocks = len(padded) // 64
    for b in range(blocks):
        var w = List[UInt32]()
        for i in range(16):
            var j = b * 64 + i * 4
            w.append(
                (UInt32(padded[j]) << UInt32(24))
                | (UInt32(padded[j + 1]) << UInt32(16))
                | (UInt32(padded[j + 2]) << UInt32(8))
                | UInt32(padded[j + 3])
            )
        for i in range(16, 64):
            var s0 = (
                _rotr(w[i - 15], UInt32(7))
                ^ _rotr(w[i - 15], UInt32(18))
                ^ (w[i - 15] >> UInt32(3))
            )
            var s1 = (
                _rotr(w[i - 2], UInt32(17))
                ^ _rotr(w[i - 2], UInt32(19))
                ^ (w[i - 2] >> UInt32(10))
            )
            w.append(w[i - 16] + s0 + w[i - 7] + s1)
        var a = h0
        var bb = h1
        var c = h2
        var d = h3
        var e = h4
        var f = h5
        var g = h6
        var h = h7
        for i in range(64):
            var big_s1 = (
                _rotr(e, UInt32(6))
                ^ _rotr(e, UInt32(11))
                ^ _rotr(e, UInt32(25))
            )
            var ch = (e & f) ^ ((~e) & g)
            var t1 = h + big_s1 + ch + k[i] + w[i]
            var big_s0 = (
                _rotr(a, UInt32(2))
                ^ _rotr(a, UInt32(13))
                ^ _rotr(a, UInt32(22))
            )
            var maj = (a & bb) ^ (a & c) ^ (bb & c)
            var t2 = big_s0 + maj
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = bb
            bb = a
            a = t1 + t2
        h0 += a
        h1 += bb
        h2 += c
        h3 += d
        h4 += e
        h5 += f
        h6 += g
        h7 += h

    var words = List[UInt32]()
    words.append(h0)
    words.append(h1)
    words.append(h2)
    words.append(h3)
    words.append(h4)
    words.append(h5)
    words.append(h6)
    words.append(h7)
    var digits = String("0123456789abcdef")
    var out = String("")
    for i in range(len(words)):
        for j in range(8):
            var shift = UInt32(28) - UInt32(j) * UInt32(4)
            var nibble = Int((words[i] >> shift) & UInt32(0xF))
            out += String(digits[byte = nibble : nibble + 1])
    return out^


def name_dir(database_dir: String, name: String) -> String:
    """Directory holding one test's saved counterexamples."""
    var digest = sha256_hex(name)
    return database_dir + "/" + String(digest[byte=0:16])


def entry_path(database_dir: String, name: String, replay: String) -> String:
    """File storing one saved counterexample.

    The filename is the hex SHA-256 of the replay string, so it is
    filesystem-safe (unlike Base64, which may contain `/`) and identical
    content maps to one file.
    """
    return name_dir(database_dir, name) + "/" + sha256_hex(replay)


struct SavedEntry(Copyable, Movable):
    """One database file: its filename plus the stored replay string."""

    var filename: String
    var replay: String

    def __init__(out self, filename: String, replay: String):
        self.filename = filename.copy()
        self.replay = replay.copy()


struct ExampleDatabase(Copyable, Movable):
    """File-backed store of shrunken counterexamples for one test name.

    An empty `name` disables the database: `load` yields nothing and
    `save` / `remove` / `remove_file` touch no files.
    """

    var database_dir: String
    var name: String
    var _dir: String

    def __init__(out self, database_dir: String, name: String):
        self.database_dir = database_dir.copy()
        self.name = name.copy()
        self._dir = name_dir(
            database_dir, name
        ) if name.byte_length() > 0 else String("")

    def enabled(self) -> Bool:
        """Whether `name` selects database use (empty disables)."""
        return self.name.byte_length() > 0

    def load(self) raises -> List[SavedEntry]:
        """Saved entries in replay-sorted order.

        Unreadable files and subdirectories are skipped.
        No decoding happens here; the runner replays each string and
        deletes files that no longer fail.
        """
        var out = List[SavedEntry]()
        if not self.enabled():
            return out^
        if not Path(self._dir).exists():
            return out^
        var entries = listdir(self._dir)
        for i in range(len(entries)):
            var filename = String(entries[i])
            var full = self._dir + "/" + filename
            if not Path(full).is_file():
                continue
            var content = String("")
            try:
                content = Path(full).read_text()
            except:
                continue
            out.append(SavedEntry(filename^, content^))
        return _sorted_entries(out^)

    def save(self, replay: String) raises:
        """Persist `replay`, creating directories; no-op when disabled."""
        if not self.enabled():
            return
        _ensure_dir(self.database_dir)
        _ensure_dir(self._dir)
        Path(self._dir + "/" + sha256_hex(replay)).write_text(replay.copy())

    def remove(self, replay: String) raises:
        """Delete the file addressed by `replay`; missing files are ignored."""
        if not self.enabled():
            return
        self.remove_file(sha256_hex(replay))

    def remove_file(self, filename: String) raises:
        """Delete one listed file by name; missing files are ignored.

        Pruning uses the exact listed name so files whose content no
        longer matches their name are still deleted.
        """
        if not self.enabled():
            return
        var full = self._dir + "/" + filename
        if not Path(full).is_file():
            return
        remove(full)


def _ensure_dir(path: String) raises:
    """Recursively create directories for `path` (like mkdir -p)."""
    if Path(path).is_dir():
        return
    var bytes = path.as_bytes()
    if len(bytes) == 0:
        return
    for i in range(len(bytes)):
        if bytes[i] == 47 and i > 0:
            var sub = String(path[byte=0:i])
            if not Path(sub).is_dir():
                try:
                    mkdir(sub)
                except e:
                    if not Path(sub).is_dir():
                        raise e
    if not Path(path).is_dir():
        try:
            mkdir(path)
        except e:
            if not Path(path).is_dir():
                raise e


def _sorted_entries(values: List[SavedEntry]) -> List[SavedEntry]:
    """Copy of `values` ordered by replay string, for deterministic replay."""
    var out = values.copy()
    for i in range(1, len(out)):
        var key = out[i].copy()
        var j = i - 1
        while j >= 0 and out[j].replay > key.replay:
            out[j + 1] = out[j].copy()
            j -= 1
        out[j + 1] = key^
    return out^


def _rotr(x: UInt32, n: UInt32) -> UInt32:
    return (x >> n) | (x << (UInt32(32) - n))


def _sha256_round_constants() -> List[UInt32]:
    var k = List[UInt32]()
    k.append(UInt32(0x428A2F98))
    k.append(UInt32(0x71374491))
    k.append(UInt32(0xB5C0FBCF))
    k.append(UInt32(0xE9B5DBA5))
    k.append(UInt32(0x3956C25B))
    k.append(UInt32(0x59F111F1))
    k.append(UInt32(0x923F82A4))
    k.append(UInt32(0xAB1C5ED5))
    k.append(UInt32(0xD807AA98))
    k.append(UInt32(0x12835B01))
    k.append(UInt32(0x243185BE))
    k.append(UInt32(0x550C7DC3))
    k.append(UInt32(0x72BE5D74))
    k.append(UInt32(0x80DEB1FE))
    k.append(UInt32(0x9BDC06A7))
    k.append(UInt32(0xC19BF174))
    k.append(UInt32(0xE49B69C1))
    k.append(UInt32(0xEFBE4786))
    k.append(UInt32(0x0FC19DC6))
    k.append(UInt32(0x240CA1CC))
    k.append(UInt32(0x2DE92C6F))
    k.append(UInt32(0x4A7484AA))
    k.append(UInt32(0x5CB0A9DC))
    k.append(UInt32(0x76F988DA))
    k.append(UInt32(0x983E5152))
    k.append(UInt32(0xA831C66D))
    k.append(UInt32(0xB00327C8))
    k.append(UInt32(0xBF597FC7))
    k.append(UInt32(0xC6E00BF3))
    k.append(UInt32(0xD5A79147))
    k.append(UInt32(0x06CA6351))
    k.append(UInt32(0x14292967))
    k.append(UInt32(0x27B70A85))
    k.append(UInt32(0x2E1B2138))
    k.append(UInt32(0x4D2C6DFC))
    k.append(UInt32(0x53380D13))
    k.append(UInt32(0x650A7354))
    k.append(UInt32(0x766A0ABB))
    k.append(UInt32(0x81C2C92E))
    k.append(UInt32(0x92722C85))
    k.append(UInt32(0xA2BFE8A1))
    k.append(UInt32(0xA81A664B))
    k.append(UInt32(0xC24B8B70))
    k.append(UInt32(0xC76C51A3))
    k.append(UInt32(0xD192E819))
    k.append(UInt32(0xD6990624))
    k.append(UInt32(0xF40E3585))
    k.append(UInt32(0x106AA070))
    k.append(UInt32(0x19A4C116))
    k.append(UInt32(0x1E376C08))
    k.append(UInt32(0x2748774C))
    k.append(UInt32(0x34B0BCB5))
    k.append(UInt32(0x391C0CB3))
    k.append(UInt32(0x4ED8AA4A))
    k.append(UInt32(0x5B9CCA4F))
    k.append(UInt32(0x682E6FF3))
    k.append(UInt32(0x748F82EE))
    k.append(UInt32(0x78A5636F))
    k.append(UInt32(0x84C87814))
    k.append(UInt32(0x8CC70208))
    k.append(UInt32(0x90BEFFFA))
    k.append(UInt32(0xA4506CEB))
    k.append(UInt32(0xBEF9A3F7))
    k.append(UInt32(0xC67178F2))
    return k^
