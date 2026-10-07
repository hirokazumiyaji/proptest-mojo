"""Tests for the example database and SHA-256 layout helpers.

Covers `docs/specs/runner.md` (example database): the on-disk layout
`{database_dir}/{sha256(name)[:16]}/{sha256(replay)}`, replay-before-
generation with pruning of stale entries, and the disabled-by-default
`name`. SHA-256 itself is checked against `sha256sum` reference vectors.
"""

from proptest import ExampleDatabase, Settings, TestCase, for_all, integers
from proptest.database import entry_path, name_dir, sha256_hex
from std.os import listdir, remove
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true
from std.time import monotonic


def _fails_at_1000(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))
    if x >= 1000:
        raise Error("too big: x=" + String(x))


def _always_passes(mut tc: TestCase) raises:
    var x = tc.draw(integers(0, 10000), "x")
    tc.note("saw x=" + String(x))


def _fresh_dir(label: String) -> String:
    return "/tmp/proptest-mojo-db-" + label + "-" + String(Int(monotonic()))


def _clean_db(database_dir: String, name: String) raises:
    try:
        var dir = name_dir(database_dir, name)
        var entries = listdir(dir)
        for i in range(len(entries)):
            var full = dir + "/" + String(entries[i])
            if Path(full).is_file():
                remove(full)
    except:
        pass


def _saved_files(database_dir: String, name: String) raises -> List[String]:
    var out = List[String]()
    try:
        for entry in listdir(name_dir(database_dir, name)):
            out.append(String(entry))
    except:
        pass
    return out^


def _is_hex(text: String) -> Bool:
    if text.byte_length() == 0:
        return False
    var digits = String("0123456789abcdef")
    for i in range(text.byte_length()):
        var ch = String(text[byte = i : i + 1])
        if not (ch in digits):
            return False
    return True


def test_sha256_known_vectors() raises:
    assert_equal(
        sha256_hex(""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    assert_equal(
        sha256_hex("abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    )
    assert_equal(
        sha256_hex("hello"),
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
    )
    assert_equal(
        sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    )


def test_sha256_padding_boundaries() raises:
    var fifties = String("")
    for _ in range(55):
        fifties += "a"
    assert_equal(
        sha256_hex(fifties),
        "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
    )
    var fiftysix = fifties + "a"
    assert_equal(
        sha256_hex(fiftysix),
        "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
    )
    var sixtyfour = fiftysix + "aaaaaaaa"
    assert_equal(
        sha256_hex(sixtyfour),
        "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
    )


def test_layout_paths_follow_spec() raises:
    var prefix = String("/db")
    var dir = name_dir(prefix, "my-test")
    assert_true(
        dir.byte_length() == prefix.byte_length() + 1 + 16,
        msg="name dir truncates the digest to 16 hex chars: " + dir,
    )
    assert_true(
        ("/" in dir)
        and _is_hex(String(dir[byte = prefix.byte_length() + 1 :])),
        msg="name dir suffix must be hex: " + dir,
    )
    var file = entry_path("/db", "my-test", "AQ==")
    assert_true(
        (file + "/") == (dir + "/" + sha256_hex("AQ==") + "/"),
        msg="entry nests the full replay digest under the name dir: " + file,
    )
    assert_true(
        _is_hex(
            String(file[byte = dir.byte_length() + 1 : file.byte_length()])
        ),
        msg="entry filename must be hex: " + file,
    )


def test_settings_database_defaults() raises:
    var settings = Settings()
    assert_equal(settings.name, "")
    assert_equal(settings.database_dir, ".proptest-mojo")
    assert_true(
        not ('name="' in String(settings)),
        msg="default settings hide the disabled name: " + String(settings),
    )
    var named = Settings(name="my-test")
    assert_true(
        ('name="my-test"' in String(named)),
        msg="settings show the database name: " + String(named),
    )


def test_save_and_load_roundtrip() raises:
    var dir = _fresh_dir("roundtrip")
    var db = ExampleDatabase(dir, "roundtrip")
    _clean_db(dir, "roundtrip")
    db.save("AQ==")
    db.save("AQ==")
    var loaded = db.load()
    assert_equal(len(loaded), 1)
    assert_equal(loaded[0].replay, "AQ==")
    assert_equal(loaded[0].filename, sha256_hex("AQ=="))
    db.save("Ag==")
    loaded = db.load()
    assert_equal(len(loaded), 2)
    assert_equal(loaded[0].replay, "AQ==")
    assert_equal(loaded[1].replay, "Ag==")
    db.remove("AQ==")
    loaded = db.load()
    assert_equal(len(loaded), 1)
    assert_equal(loaded[0].replay, "Ag==")
    _clean_db(dir, "roundtrip")


def test_empty_name_disables_database() raises:
    var db = ExampleDatabase(_fresh_dir("disabled"), "")
    assert_true(not db.enabled(), msg="empty name must disable the database")
    db.save("AQ==")
    assert_equal(len(db.load()), 0)
    db.remove("AQ==")


def test_failing_run_writes_nothing_without_name() raises:
    var dir = _fresh_dir("no-name")
    var report = String("")
    try:
        for_all(_fails_at_1000, Settings(seed=UInt64(1), database_dir=dir))
    except e:
        report = String(e)
    assert_true(("x = 1000" in report), msg="must still fail: " + report)
    assert_true(
        not Path(dir).exists(),
        msg="unnamed runs must not create the database dir",
    )


def test_failing_test_replays_first_next_run() raises:
    var dir = _fresh_dir("replay-first")
    var name = String("replay-first")
    _clean_db(dir, name)
    var first = String("")
    try:
        for_all(
            _fails_at_1000,
            Settings(seed=UInt64(1), name=name, database_dir=dir),
        )
    except e:
        first = String(e)
    assert_true(("x = 1000" in first), msg="first run fails minimal: " + first)
    assert_equal(len(_saved_files(dir, name)), 1)
    var second = String("")
    try:
        for_all(
            _fails_at_1000,
            Settings(seed=UInt64(999), name=name, database_dir=dir),
        )
    except e:
        second = String(e)
    assert_true(
        ("x = 1000" in second), msg="replay fails the same way: " + second
    )
    assert_true(
        ("after 1 examples" in second),
        msg="saved failure runs before generation: " + second,
    )
    _clean_db(dir, name)


def test_fixed_property_prunes_stale_entries() raises:
    var dir = _fresh_dir("prune-stale")
    var name = String("prune-stale")
    _clean_db(dir, name)
    try:
        for_all(
            _fails_at_1000,
            Settings(seed=UInt64(1), name=name, database_dir=dir),
        )
    except:
        pass
    assert_equal(len(_saved_files(dir, name)), 1)
    for_all(
        _always_passes,
        Settings(seed=UInt64(1), max_examples=20, name=name, database_dir=dir),
    )
    assert_equal(len(_saved_files(dir, name)), 0)
    _clean_db(dir, name)


def test_corrupt_files_are_skipped_and_pruned() raises:
    var dir = _fresh_dir("corrupt")
    var name = String("corrupt")
    _clean_db(dir, name)
    var db = ExampleDatabase(dir, name)
    db.save("AQ==")
    var garbage = String("!!!not-base64!!!")
    Path(entry_path(dir, name, garbage)).write_text(garbage.copy())
    Path(name_dir(dir, name) + "/foreign.txt").write_text("stray")
    var loaded = db.load()
    assert_equal(len(loaded), 3)
    for_all(
        _always_passes,
        Settings(seed=UInt64(1), max_examples=5, name=name, database_dir=dir),
    )
    assert_equal(len(_saved_files(dir, name)), 0)
    _clean_db(dir, name)


def test_load_preserves_whitespace() raises:
    var dir = _fresh_dir("whitespace")
    var name = String("whitespace")
    _clean_db(dir, name)
    var db = ExampleDatabase(dir, name)
    var token_with_ws = String("  AQ== \n")
    db.save(token_with_ws)
    var loaded = db.load()
    assert_equal(len(loaded), 1)
    assert_equal(loaded[0].replay, token_with_ws)
    _clean_db(dir, name)


def test_load_missing_directory_returns_empty() raises:
    var dir = _fresh_dir("missing")
    var db = ExampleDatabase(dir, "missing")
    var loaded = db.load()
    assert_equal(len(loaded), 0)


def test_save_creates_nested_parent_directories() raises:
    var dir = _fresh_dir("nested/parent/db")
    var name = String("nested")
    var db = ExampleDatabase(dir, name)
    db.save("AQ==")
    var loaded = db.load()
    assert_equal(len(loaded), 1)
    assert_equal(loaded[0].replay, "AQ==")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
