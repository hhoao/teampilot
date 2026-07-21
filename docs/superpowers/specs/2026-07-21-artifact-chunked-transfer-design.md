# Artifact chunked transfer: design

## Problem

Cross-machine TeamBus artifacts use `ArtifactTransferService`, which buffers the
entire file in App memory (`Filesystem.readBytes` → `writeBytes`) and rejects
anything over `defaultMaxBytes` (256 MiB). Large build products (e.g. ~500 MB
JARs) fail on the bus, so members fall back to ad-hoc SCP/HTTP.

## Goal

- Remove the hard size cap.
- Transfer via fixed-size chunks so peak App memory is O(chunk), not O(file).
- Keep MCP tools `publish_artifact` / `list_artifacts` / `fetch_artifact`
  unchanged for members (chunking is internal).
- Support resume: a failed `fetch_artifact` can continue from a partial file on
  a later call with the same destination.

## Non-goals

- Member-visible progress or cancel MCP APIs
- Directory / tar artifact kinds
- Global bandwidth limiting across concurrent fetches
- Content checksums (size + mtime + offset consistency only in v1)
- Backward or forward compatibility with the whole-file transfer path or any
  prior on-disk partial format — this replaces the transfer implementation

## Approach

**Extend `Filesystem` with ranged IO; orchestrate chunked copy + resume in
`ArtifactTransferService`.**

Bus still stores only handles. The local App remains the only process that can
reach both machines' filesystems.

```
publish_artifact
  → stat source file → register ArtifactHandle (no byte copy)

fetch_artifact
  → resolve inbox dest
  → same-machine? copyFile (discard stale partials) → done
  → else open/resume {dest}.tp-partial + meta
  → loop: readBytesRange(src) → appendBytes(partial) → update meta
  → rename partial → dest; delete meta
```

Default chunk size: **4 MiB** (configurable on the service; bounds peak memory
only).

## Filesystem API

Add to `Filesystem` (all implementations must provide them):

| Method | Contract |
|--------|----------|
| `readBytesRange(path, offset, length)` | Returns up to `length` bytes starting at `offset`. Returns `null` if missing. Returns fewer bytes at EOF. Throws if not a regular file / unreadable. |
| `appendBytes(path, bytes)` | Creates file if missing; appends `bytes` at end. Ensures parent dirs as existing write helpers do. |

Keep existing `readBytes` / `writeBytes`. Call sites that need whole-file
semantics may keep using them; artifact fetch must not.

Implementations:

| Backend | Range read | Append |
|---------|------------|--------|
| `LocalFilesystem` | `RandomAccessFile` | open append / write-at-end |
| `SftpFilesystem` / `RemoteFileStore` | SFTP read at offset | open create\|write\|append (or seek+write) |
| `WslFilesystem` | Match existing WSL IO style (prefer local path via `wslpath` + RAF when available; else equivalent ranged shell read) | Same for append |
| `InMemoryFilesystem` | Slice in-memory bytes | Concatenate |
| `ManifestFilesystem` | Range read if readable; `appendBytes` follows existing write policy (unsupported → `UnsupportedError` if that FS is write-blocked) |

## Resume format

On the **fetcher** machine, inside the member inbox:

| Path | Role |
|------|------|
| `{dest}.tp-partial` | Incomplete payload |
| `{dest}.tp-partial.meta.json` | Resume metadata |

Meta fields:

- `artifactName`
- `publisherMemberId`
- `sourceTargetId`
- `sourcePath`
- `expectedSizeBytes` (nullable if unknown)
- `sourceMtimeMs` (omitted if backend has no mtime)
- `bytesWritten`
- `chunkSize`

Extract pure match/serialize helpers (e.g. `ArtifactPartialMeta`) so tests do
not need a full transfer.

### Resume match (all required → resume; else discard partial+meta and restart)

1. Meta identity matches current handle: name, publisher, source target, path.
2. If both meta and live `stat.size` are known, sizes equal.
3. If both meta and live mtime are present, mtimes equal.
4. On-disk partial length equals `bytesWritten`.

### overwrite / exists

- Final `dest` exists and `overwrite=false` → existing
  `ArtifactDestinationExistsException` (unchanged).
- `overwrite=true` → delete final `dest`, then apply resume match on partial
  (match → continue; mismatch → restart).

## Failure behavior

| Event | Action |
|-------|--------|
| Mid-chunk IO / network error | Keep partial+meta; surface error to MCP |
| Source missing / unreadable | Delete partial+meta; `ArtifactSourceUnreadableException` |
| Source size shrunk below `bytesWritten` or identity mismatch mid-transfer | Delete partial+meta; fail with a clear size/identity-changed error |
| Successful transfer | `rename` partial → dest; delete meta |
| Rename fails after last chunk | Keep partial+meta so retry can finish via rename/resume path |

Remove `maxBytes`, `defaultMaxBytes`, and `ArtifactTooLargeException`.

## Same-machine shortcut

When `handle.targetId == fetcherTargetId`, use `Filesystem.copyFile` (or
equivalent). Discard any leftover `.tp-partial` / meta for that dest first.
No chunk loop required.

## Concurrency

- Same session + same resolved dest: treat as one logical transfer (last writer
  wins via filesystem; do not add a cross-isolate lock in v1).
- Different dests may run concurrently; no global rate limit.

## MCP surface

No schema or tool-name changes. Success/error strings may mention byte counts;
they must not require members to manage chunks. Tool descriptions may drop any
wording that implies a hard size cap, if present.

## Testing

1. `InMemoryFilesystem` range read + append.
2. `ArtifactPartialMeta` match / mismatch matrix.
3. `ArtifactTransferService`:
   - multi-chunk happy path (file larger than chunk size)
   - interrupt then resume to completion
   - mismatched meta → full restart
   - source shrink / vanish → cleanup + error
   - overwrite behavior
   - same-machine `copyFile` path
   - remove over-cap tests
4. Existing teammate-bus artifact MCP tool tests remain green under the new
   transfer path.

## Out of scope follow-ups

- Progress events / cancel
- Strong integrity (hash)
- Directory artifacts
- Concurrent-fetch throttling
