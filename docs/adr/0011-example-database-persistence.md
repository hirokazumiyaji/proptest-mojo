# ADR-0011: Example database persistence format and explicit naming

- Status: Accepted
- Date: 2026-09-30
- Related: Issue #26, [specs/runner.md](../specs/runner.md) (Example database)

## Context

The Spec stores a shrunk choice sequence at `{database_dir}/{first 16 hex digits of sha256(name)}/{hash of choice sequence}` and replays it before generation on the next run. Milestone M4 also called for investigating whether `name` could default to a value derived automatically from the call site, using a Mojo equivalent of `call_location`.

We inspected the stdlib in Mojo 1.2.0.dev2026092605 and found no way to retrieve the call site. We tried `__file__`, `std.source_location`, `std.sys.call_location`, `std.compile.current_file`, `std.reflect`, `std.debug`, and `std.defines`; these were either undefined or their modules did not exist. Comptime type-name stringification (`type_of`) exists, but there is no display API, nor any guarantee that it can distinguish calls to the same closure from different locations.

The stdlib provides sufficient file I/O through `std.os` (`mkdir`, `remove`, `listdir`) and `std.pathlib.Path` (`write_text`, `read_text`, `exists`, `is_dir`, `is_file`, `listdir`, and `/` joining). `std.os.remove` cannot delete directories, but this is fine because only choice-sequence files need to be removed. The available stdlib hash APIs (`std.hash` and straightforward use of `std.hashlib`) were insufficient.

## Decision

- Keep `settings.name` explicit. The default is an empty string, meaning that the database is not used. Do not derive the name from the call site.
- Use the layout specified above: `{database_dir}/{sha256(name)[:16]}/{sha256(replay)}`. The filename is the full 64-character SHA-256 hex digest of the replay string (the replay string itself may contain `/` because it is Base64); the file contents are the replay string.
- Implement SHA-256 as a pure function in the repository (`sha256_hex` in `database.mojo`), without a stdlib dependency. Verify it against known FIPS 180-4 test vectors.
- `load` returns the sorted file contents without decoding them. The runner validates entries during replay and deletes files that fail to decode or are not INTERESTING, using the filename found during enumeration (the content hash may not identify the file).

## Alternatives Considered

- Derive `name` from a comptime type name: there is no API to stringify the type, and no guarantee that calls to the same closure from different locations can be distinguished.
- Provide a default `name` through an environment variable: this introduces implicit global state and conflicts with the coding guidelines.
- Use the replay string as the filename: `/` conflicts with path separators. Base64URL encoding was considered, but a fixed-length hash has clearer collision behavior and makes directory listings easier to scan.
- Use a shorter custom hash such as FNV-1a: easier to implement, but conflicts with the Spec's SHA-256 requirement. A local SHA-256 implementation is about 100 lines, so follow the Spec.

## Consequences

- Callers of `for_all` must set `name` when they want counterexamples persisted. Without it, nothing is saved, as before.
- `.proptest-mojo/` is already in `.gitignore`, so using the default does not dirty the working tree. Committing the database can turn an example into a regression test.
- If the compiler adds a call-site API equivalent to `call_location`, supersede this ADR and reconsider automatic naming.
