# Artifact Chunked Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace whole-file in-memory TeamBus artifact copies with ranged `Filesystem` IO, remove the 256 MiB cap, and resume incomplete fetches via `.tp-partial` sidecars — without changing MCP tool names/schemas.

**Architecture:** Add `readBytesRange` / `appendBytes` to every `Filesystem` backend. Move transfer orchestration into `ArtifactTransferService` (chunk loop + resume meta). Bus still stores handles only; App still moves bytes between seat filesystems.

**Tech Stack:** Dart/Flutter, existing `Filesystem` / `RemoteFileStore` / dartssh2 `SftpFile.readBytes(offset:)` / `writeBytes(offset:)`, unit tests under `client/test/`.

**Spec:** `docs/superpowers/specs/2026-07-21-artifact-chunked-transfer-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/services/io/filesystem.dart` | Add `readBytesRange` / `appendBytes` |
| `client/test/support/in_memory_filesystem.dart` | Fake ranged IO for tests |
| `client/lib/services/io/local_filesystem.dart` | RAF range read + append |
| `client/lib/services/storage/remote_file_store.dart` | SFTP ranged read/append |
| `client/lib/services/io/sftp_filesystem.dart` | Delegate new methods to store |
| `client/lib/services/io/wsl_filesystem.dart` | `dd`/`base64` ranged read; append via existing `_pipeBase64ToFile(..., append: true)` |
| `client/lib/services/launch/manifest_filesystem.dart` | Delegate range to `readDelegate`; append via overlay/write policy |
| `client/test/cubits/file_tree_cubit_test.dart` | Stub new methods on `_FakeFilesystem` |
| `client/test/services/file_tree/file_tree_visible_rows_test.dart` | Same |
| `client/lib/services/team_bus/artifacts/artifact_partial_meta.dart` | **Create** — serialize/match resume meta |
| `client/lib/services/team_bus/artifacts/artifact_exceptions.dart` | Remove too-large; add source-changed |
| `client/lib/services/team_bus/artifacts/artifact_transfer_service.dart` | Chunked fetch + resume; drop `maxBytes` |
| `client/test/services/io/in_memory_filesystem_range_test.dart` | **Create** |
| `client/test/services/team_bus/artifacts/artifact_partial_meta_test.dart` | **Create** |
| `client/test/services/team_bus/artifacts/artifact_transfer_service_test.dart` | Rewrite for chunks/resume |
| `client/test/services/team_bus/artifacts/teammate_bus_artifact_tools_test.dart` | Keep green; drop size-cap assumptions if any |
| `client/lib/services/team_bus/mcp/tools/publish_artifact_tool.dart` | Drop any size-cap wording in description if present |

`_NeverFs` / fakes using `noSuchMethod` need no stubs until called.

---

### Task 1: Filesystem API + InMemory ranged IO (TDD)

**Files:**
- Modify: `client/lib/services/io/filesystem.dart`
- Modify: `client/test/support/in_memory_filesystem.dart`
- Create: `client/test/services/io/in_memory_filesystem_range_test.dart`
- Modify (compile stubs only):  
  `client/test/cubits/file_tree_cubit_test.dart`  
  `client/test/services/file_tree/file_tree_visible_rows_test.dart`  
  `client/lib/services/io/local_filesystem.dart`  
  `client/lib/services/io/sftp_filesystem.dart`  
  `client/lib/services/io/wsl_filesystem.dart`  
  `client/lib/services/launch/manifest_filesystem.dart`

- [ ] **Step 1: Write failing InMemory range tests**

Create `client/test/services/io/in_memory_filesystem_range_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('readBytesRange returns slice and fewer bytes at EOF', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/a.bin', [0, 1, 2, 3, 4]);
    expect(await fs.readBytesRange('/a.bin', 1, 2), [1, 2]);
    expect(await fs.readBytesRange('/a.bin', 3, 10), [3, 4]);
    expect(await fs.readBytesRange('/a.bin', 5, 4), <int>[]);
    expect(await fs.readBytesRange('/missing', 0, 4), isNull);
  });

  test('appendBytes creates and extends', () async {
    final fs = InMemoryFilesystem();
    await fs.appendBytes('/a.bin', [1, 2]);
    await fs.appendBytes('/a.bin', [3]);
    expect(await fs.readBytes('/a.bin'), [1, 2, 3]);
  });
}
```

- [ ] **Step 2: Run tests — expect compile/fail (methods missing)**

Run: `cd client && flutter test test/services/io/in_memory_filesystem_range_test.dart`

Expected: FAIL (interface/methods missing)

- [ ] **Step 3: Add interface methods**

In `filesystem.dart` after `writeBytes`:

```dart
  /// Up to [length] bytes from [offset]. Null if missing. Shorter at EOF.
  Future<List<int>?> readBytesRange(String path, int offset, int length);

  /// Create if missing; append [bytes] at end.
  Future<void> appendBytes(String path, List<int> bytes);
```

- [ ] **Step 4: Implement on InMemoryFilesystem**

```dart
  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final all = await readBytes(path);
    if (all == null) return null;
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (length < 0) throw ArgumentError.value(length, 'length');
    if (offset >= all.length) return <int>[];
    final end = (offset + length).clamp(0, all.length);
    return all.sublist(offset, end);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final existing = await readBytes(path) ?? <int>[];
    await writeBytes(path, [...existing, ...bytes]);
  }
```

- [ ] **Step 5: Stub every other `implements Filesystem` so analyze compiles**

For production backends temporarily:

```dart
  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      throw UnimplementedError('readBytesRange');

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      throw UnimplementedError('appendBytes');
```

For `_FakeFilesystem` in the two file-tree tests, return `[]` / no-op like other methods.

`_NeverFs` / `noSuchMethod` fakes: leave alone.

- [ ] **Step 6: Re-run range tests — expect PASS**

Run: `cd client && flutter test test/services/io/in_memory_filesystem_range_test.dart`

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/io/filesystem.dart \
  client/test/support/in_memory_filesystem.dart \
  client/test/services/io/in_memory_filesystem_range_test.dart \
  client/test/cubits/file_tree_cubit_test.dart \
  client/test/services/file_tree/file_tree_visible_rows_test.dart \
  client/lib/services/io/local_filesystem.dart \
  client/lib/services/io/sftp_filesystem.dart \
  client/lib/services/io/wsl_filesystem.dart \
  client/lib/services/launch/manifest_filesystem.dart
git commit -m "$(cat <<'EOF'
feat(io): add Filesystem readBytesRange and appendBytes

Introduce ranged IO on the interface with InMemory coverage and stubs
on other backends so the tree still analyzes.
EOF
)"
```

---

### Task 2: LocalFilesystem ranged IO

**Files:**
- Modify: `client/lib/services/io/local_filesystem.dart`
- Create: `client/test/services/io/local_filesystem_range_test.dart`

- [ ] **Step 1: Write failing temp-dir tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory dir;
  late LocalFilesystem fs;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tp-fs-range-');
    fs = LocalFilesystem();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('range read and append round-trip', () async {
    final path = '${dir.path}/f.bin';
    await fs.writeBytes(path, [10, 20, 30, 40]);
    expect(await fs.readBytesRange(path, 1, 2), [20, 30]);
    await fs.appendBytes(path, [50]);
    expect(await fs.readBytes(path), [10, 20, 30, 40, 50]);
  });
}
```

- [ ] **Step 2: Run — expect FAIL (UnimplementedError)**

Run: `cd client && flutter test test/services/io/local_filesystem_range_test.dart`

- [ ] **Step 3: Implement with RandomAccessFile**

```dart
  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      return await raf.read(length);
    } on FileSystemException {
      return null;
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    final raf = await File(path).open(mode: FileMode.append);
    try {
      await raf.writeFrom(bytes);
    } finally {
      await raf.close();
    }
  }
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/io/local_filesystem.dart \
  client/test/services/io/local_filesystem_range_test.dart
git commit -m "$(cat <<'EOF'
feat(io): implement LocalFilesystem ranged read/append
EOF
)"
```

---

### Task 3: RemoteFileStore + SftpFilesystem ranged IO

**Files:**
- Modify: `client/lib/services/storage/remote_file_store.dart`
- Modify: `client/lib/services/io/sftp_filesystem.dart`

dartssh2 already supports `SftpFile.readBytes(length:, offset:)` and
`writeBytes(data, offset:)`.

- [ ] **Step 1: Add store methods**

```dart
  Future<List<int>?> readFileBytesRange(
    String path, {
    required int offset,
    required int length,
  }) async {
    try {
      final sftp = await _ensureConnected();
      final resolved = await expandHome(path);
      final file = await sftp.open(resolved, mode: SftpFileOpenMode.read);
      try {
        return await file.readBytes(length: length, offset: offset);
      } finally {
        await file.close();
      }
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return null;
      rethrow;
    }
  }

  Future<void> appendBytes(String path, Uint8List bytes) async {
    final sftp = await _ensureConnected();
    final resolved = await expandHome(path);
    await _ensureParentDirs(resolved);
    final file = await sftp.open(
      resolved,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.append,
    );
    try {
      // Prefer append mode; if dartssh2 ignores append flag, stat size and
      // writeBytes(..., offset: size) as fallback.
      await file.writeBytes(bytes);
    } finally {
      await file.close();
    }
  }
```

Verify `SftpFileOpenMode.append` exists in vendored dartssh2; if not, open
read|write|create, `stat` size, `writeBytes(bytes, offset: size)`.

- [ ] **Step 2: Wire SftpFilesystem**

```dart
  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      store.readFileBytesRange(path, offset: offset, length: length);

  @override
  Future<void> appendBytes(String path, List<int> bytes) => store.appendBytes(
    path,
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
```

- [ ] **Step 3: Analyze only (no live SSH in unit CI)**

Run: `cd client && dart analyze lib/services/storage/remote_file_store.dart lib/services/io/sftp_filesystem.dart`

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/storage/remote_file_store.dart \
  client/lib/services/io/sftp_filesystem.dart
git commit -m "$(cat <<'EOF'
feat(io): SFTP ranged read and append for artifacts
EOF
)"
```

---

### Task 4: WslFilesystem + ManifestFilesystem

**Files:**
- Modify: `client/lib/services/io/wsl_filesystem.dart`
- Modify: `client/lib/services/launch/manifest_filesystem.dart`

- [ ] **Step 1: WSL range read via `dd` + base64**

Reuse shell-quoting helpers already used by `readBytes`:

```dart
  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _run([
      'sh',
      '-lc',
      'dd if=$quoted bs=1 skip=$offset count=$length 2>/dev/null | '
          'base64 -w0 || dd if=$quoted bs=1 skip=$offset count=$length 2>/dev/null | base64',
    ]);
    if (result.exitCode != 0) return null;
    final encoded = (result.stdout as String).replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return <int>[];
    try {
      return base64.decode(encoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final encoded = base64.encode(bytes);
    await _pipeBase64ToFile(path, encoded, append: true);
  }
```

- [ ] **Step 2: ManifestFilesystem**

```dart
  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final all = await readBytes(path);
    if (all == null) return null;
    if (offset >= all.length) return <int>[];
    final end = (offset + length).clamp(0, all.length);
    return all.sublist(offset, end);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final existing = await readBytes(path) ?? <int>[];
    await writeBytes(path, [...existing, ...bytes]);
  }
```

(Manifest already routes writes through overlay + manifest ops.)

- [ ] **Step 3: Analyze touched files**

Run: `cd client && dart analyze lib/services/io/wsl_filesystem.dart lib/services/launch/manifest_filesystem.dart`

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/io/wsl_filesystem.dart \
  client/lib/services/launch/manifest_filesystem.dart
git commit -m "$(cat <<'EOF'
feat(io): WSL and ManifestFilesystem ranged IO
EOF
)"
```

---

### Task 5: ArtifactPartialMeta + exceptions (TDD)

**Files:**
- Create: `client/lib/services/team_bus/artifacts/artifact_partial_meta.dart`
- Create: `client/test/services/team_bus/artifacts/artifact_partial_meta_test.dart`
- Modify: `client/lib/services/team_bus/artifacts/artifact_exceptions.dart`

- [ ] **Step 1: Write failing meta match tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_partial_meta.dart';

void main() {
  final base = ArtifactPartialMeta(
    artifactName: 'jar',
    publisherMemberId: 'A',
    sourceTargetId: 'local',
    sourcePath: '/work/a.jar',
    expectedSizeBytes: 100,
    sourceMtimeMs: 50,
    bytesWritten: 40,
    chunkSize: 4 << 20,
  );

  test('matches when identity size mtime and length agree', () {
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 40,
      ),
      isTrue,
    );
  });

  test('rejects identity or length mismatch', () {
    expect(
      base.matchesLive(
        artifactName: 'other',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 40,
      ),
      isFalse,
    );
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 39,
      ),
      isFalse,
    );
  });

  test('rejects when both sides have mtime and they differ', () {
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 99,
        partialLength: 40,
      ),
      isFalse,
    );
  });

  test('json round-trip', () {
    final again = ArtifactPartialMeta.fromJson(base.toJson());
    expect(again.artifactName, base.artifactName);
    expect(again.bytesWritten, 40);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/services/team_bus/artifacts/artifact_partial_meta_test.dart`

- [ ] **Step 3: Implement `artifact_partial_meta.dart`**

Include `toJson` / `fromJson` / `matchesLive` per spec (size/mtime only compared when both sides known; `chunkSize` not matched).

- [ ] **Step 4: Update exceptions**

- Delete `ArtifactTooLargeException`.
- Add:

```dart
class ArtifactSourceChangedException extends ArtifactException {
  ArtifactSourceChangedException({required this.detail});
  final String detail;
  @override
  String toString() =>
      'Artifact source changed during transfer ($detail). '
      'Partial data was discarded; retry fetch_artifact from scratch.';
}
```

Grep and fix any remaining `ArtifactTooLargeException` references.

- [ ] **Step 5: Run meta tests — PASS**

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/artifacts/artifact_partial_meta.dart \
  client/test/services/team_bus/artifacts/artifact_partial_meta_test.dart \
  client/lib/services/team_bus/artifacts/artifact_exceptions.dart
git commit -m "$(cat <<'EOF'
feat(team-bus): add artifact resume meta and source-changed error
EOF
)"
```

---

### Task 6: Rewrite ArtifactTransferService (TDD)

**Files:**
- Modify: `client/lib/services/team_bus/artifacts/artifact_transfer_service.dart`
- Modify: `client/test/services/team_bus/artifacts/artifact_transfer_service_test.dart`

**Constants / helpers on the service (or private top-level):**

```dart
static const defaultChunkSize = 4 * 1024 * 1024;
static String partialPath(String dest) => '$dest.tp-partial';
static String partialMetaPath(String dest) => '$dest.tp-partial.meta.json';
```

Replace constructor `maxBytes` with `chunkSize` (default `defaultChunkSize`).

- [ ] **Step 1: Replace over-cap test with multi-chunk + resume tests**

Update `_Fixture` to take `chunkSize` (default `ArtifactTransferService.defaultChunkSize`) instead of `maxBytes`. Delete the `over-cap transfer throws` test. Keep existing happy-path / exists / escape / non-file.

Add this forwarding wrapper at the top of the test file (implement all `Filesystem` methods by delegating to `inner`; only `appendBytes` is special):

```dart
class _FailAfterAppends implements Filesystem {
  _FailAfterAppends(this.inner, {required this.failAfter});
  final Filesystem inner;
  final int failAfter;
  var _appends = 0;

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    _appends += 1;
    if (_appends > failAfter) throw StateError('boom');
    await inner.appendBytes(path, bytes);
  }

  // …delegate every other Filesystem member to inner…
}
```

Add these tests:

```dart
test('multi-chunk fetch copies full payload', () async {
  final f = _Fixture(chunkSize: 4);
  final bytes = List<int>.generate(10, (i) => i);
  await f.seedSource(bytes);
  await f.service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );
  final r = await f.service.fetch(
    fetcherMemberId: 'B',
    name: 'out',
    destPath: 'delivered.bin',
  );
  expect(await f.fetcherFs.readBytes(r.finalPath), bytes);
  expect(
    await f.fetcherFs.stat('${r.finalPath}.tp-partial'),
    predicate<FsStat>((s) => !s.exists),
  );
});

test('resume continues from partial after interrupt', () async {
  final bytes = List<int>.generate(12, (i) => i);
  final publisherFs = InMemoryFilesystem();
  final fetcherInner = InMemoryFilesystem();
  final fetcherFs = _FailAfterAppends(fetcherInner, failAfter: 1);
  final service = ArtifactTransferService(
    registry: ArtifactRegistry(),
    resolveFs: (id) async => id == 'local' ? publisherFs : fetcherFs,
    targetForMember: (m) => m == 'A' ? 'local' : 'ssh:hostB',
    inboxDirFor: (m) => m == 'A'
        ? '/home/a/inbox'
        : '/remote/sessions/s1/runtime/members/B/inbox',
    chunkSize: 4,
  );
  await publisherFs.writeBytes('/work/out.bin', bytes);
  await service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );

  await expectLater(
    () => service.fetch(
      fetcherMemberId: 'B',
      name: 'out',
      destPath: 'delivered.bin',
    ),
    throwsA(isA<StateError>()),
  );

  final dest =
      '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
  expect((await fetcherInner.stat('$dest.tp-partial')).exists, isTrue);

  // Second attempt uses a clean wrapper (no fail) on the same store.
  final service2 = ArtifactTransferService(
    registry: service.registry,
    resolveFs: (id) async => id == 'local' ? publisherFs : fetcherInner,
    targetForMember: (m) => m == 'A' ? 'local' : 'ssh:hostB',
    inboxDirFor: (m) => m == 'A'
        ? '/home/a/inbox'
        : '/remote/sessions/s1/runtime/members/B/inbox',
    chunkSize: 4,
  );
  final r = await service2.fetch(
    fetcherMemberId: 'B',
    name: 'out',
    destPath: 'delivered.bin',
  );
  expect(await fetcherInner.readBytes(r.finalPath), bytes);
});

test('mismatched meta discards partial and restarts', () async {
  final f = _Fixture(chunkSize: 4);
  final bytes = List<int>.generate(8, (i) => i);
  await f.seedSource(bytes);
  await f.service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );
  final dest =
      '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
  await f.fetcherFs.writeBytes('$dest.tp-partial', [9, 9, 9, 9]);
  await f.fetcherFs.writeString(
    '$dest.tp-partial.meta.json',
    // identity that will not match (wrong sourcePath)
    '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
    '"sourcePath":"/work/OTHER.bin","expectedSizeBytes":8,"bytesWritten":4,'
    '"chunkSize":4}',
  );
  final r = await f.service.fetch(
    fetcherMemberId: 'B',
    name: 'out',
    destPath: 'delivered.bin',
  );
  expect(await f.fetcherFs.readBytes(r.finalPath), bytes);
});

test('complete partial retries rename only', () async {
  final f = _Fixture(chunkSize: 4);
  final bytes = List<int>.generate(8, (i) => i);
  await f.seedSource(bytes);
  await f.service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );
  final dest =
      '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
  await f.fetcherFs.writeBytes('$dest.tp-partial', bytes);
  await f.fetcherFs.writeString(
    '$dest.tp-partial.meta.json',
    '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
    '"sourcePath":"/work/out.bin","expectedSizeBytes":8,"bytesWritten":8,'
    '"chunkSize":4}',
  );
  final r = await f.service.fetch(
    fetcherMemberId: 'B',
    name: 'out',
    destPath: 'delivered.bin',
  );
  expect(r.finalPath, dest);
  expect(await f.fetcherFs.readBytes(dest), bytes);
  expect((await f.fetcherFs.stat('$dest.tp-partial')).exists, isFalse);
});

test('same-machine uses copyFile and clears partials', () async {
  final shared = InMemoryFilesystem();
  final registry = ArtifactRegistry();
  final service = ArtifactTransferService(
    registry: registry,
    resolveFs: (_) async => shared,
    targetForMember: (_) => 'local',
    inboxDirFor: (_) => '/inbox',
    chunkSize: 4,
  );
  final bytes = [1, 2, 3, 4, 5];
  await shared.writeBytes('/work/out.bin', bytes);
  await shared.writeBytes('/inbox/out.bin.tp-partial', [9]);
  await shared.writeString('/inbox/out.bin.tp-partial.meta.json', '{}');
  await service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );
  final r = await service.fetch(
    fetcherMemberId: 'B',
    name: 'out',
    destPath: 'out.bin',
  );
  expect(r.finalPath, '/inbox/out.bin');
  expect(await shared.readBytes('/inbox/out.bin'), bytes);
  expect((await shared.stat('/inbox/out.bin.tp-partial')).exists, isFalse);
  expect(
    (await shared.stat('/inbox/out.bin.tp-partial.meta.json')).exists,
    isFalse,
  );
});

test('source shrink mid-transfer discards partial', () async {
  final f = _Fixture(chunkSize: 4);
  final bytes = List<int>.generate(12, (i) => i);
  await f.seedSource(bytes);
  await f.service.publish(
    publisherMemberId: 'A',
    path: '/work/out.bin',
    name: 'out',
  );
  final dest =
      '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
  await f.fetcherFs.writeBytes(
    '$dest.tp-partial',
    bytes.sublist(0, 8),
  );
  await f.fetcherFs.writeString(
    '$dest.tp-partial.meta.json',
    '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
    '"sourcePath":"/work/out.bin","expectedSizeBytes":12,"bytesWritten":8,'
    '"chunkSize":4}',
  );
  // Shrink source below bytesWritten.
  await f.publisherFs.writeBytes('/work/out.bin', bytes.sublist(0, 4));
  await expectLater(
    () => f.service.fetch(
      fetcherMemberId: 'B',
      name: 'out',
      destPath: 'delivered.bin',
    ),
    throwsA(isA<ArtifactSourceChangedException>()),
  );
  expect((await f.fetcherFs.stat('$dest.tp-partial')).exists, isFalse);
  expect(
    (await f.fetcherFs.stat('$dest.tp-partial.meta.json')).exists,
    isFalse,
  );
});
```

Expose `registry` on `ArtifactTransferService` (already a public final field) so the resume test can reuse it. Update the service class dartdoc to describe chunked transfer (remove `maxBytes` / whole-file wording).

- [ ] **Step 2: Run — expect FAIL on new behaviors**

Run: `cd client && flutter test test/services/team_bus/artifacts/artifact_transfer_service_test.dart`

- [ ] **Step 3: Implement fetch orchestration**

Algorithm (must match spec):

1. Resolve dest + inbox guard (existing).
2. If final dest exists && !overwrite → throw exists.
3. If overwrite && dest exists → `removeRecursive(dest)`.
4. If `handle.targetId == fetcherTargetId`:
   - delete partial+meta if present
   - `copyFile(handle.absolutePath, dest)` on that fs
   - return result
5. Stat source on publisher fs; if missing → cleanup + unreadable.
6. Load meta if present; if `matchesLive(...)` resume `bytesWritten`, else delete partial+meta and start at 0 (create empty partial + write meta).
7. If known size && `bytesWritten == size` → goto rename.
8. Loop: `readBytesRange(src, bytesWritten, chunkSize)` → if empty/short and size unknown break; if size known and still short of size after empty → source changed; `appendBytes(partial, chunk)`; update meta `bytesWritten`; if known size and `bytesWritten > size` → source changed.
9. `rename(partial, dest)`; delete meta.
10. Never call `readBytes`/`writeBytes` for the payload path.

Publish: remove size-vs-`maxBytes` check; still reject non-files.

- [ ] **Step 4: Run transfer tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/artifacts/artifact_transfer_service.dart \
  client/test/services/team_bus/artifacts/artifact_transfer_service_test.dart
git commit -m "$(cat <<'EOF'
feat(team-bus): chunked resumable artifact fetch

Replace whole-file buffering with ranged copy, resume sidecars, and
no hard size cap.
EOF
)"
```

---

### Task 7: MCP tools + full verification

**Files:**
- Modify: `client/lib/services/team_bus/mcp/tools/publish_artifact_tool.dart` (description only if needed)
- Modify: `client/test/services/team_bus/artifacts/teammate_bus_artifact_tools_test.dart` (fix fixture if it passed `maxBytes`)
- Grep: `maxBytes|defaultMaxBytes|ArtifactTooLarge|TooLarge`

- [ ] **Step 1: Grep cleanup**

Run: `cd client && rg -n 'maxBytes|defaultMaxBytes|ArtifactTooLarge' lib test`

Expected: no remaining production references (tests for too-large removed).

- [ ] **Step 2: Run artifact + IO tests**

```bash
cd client && flutter test \
  test/services/io/in_memory_filesystem_range_test.dart \
  test/services/io/local_filesystem_range_test.dart \
  test/services/team_bus/artifacts/
```

Expected: all PASS

- [ ] **Step 3: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors related to `Filesystem` missing members

- [ ] **Step 4: Commit if any leftover edits**

```bash
git add -u client/lib/services/team_bus client/test/services/team_bus
git commit -m "$(cat <<'EOF'
chore(team-bus): finish artifact chunked-transfer cleanup
EOF
)"
```

---

## Execution notes

- Prefer **subagent-driven-development**: one task per subagent, TDD order as written.
- Do not add progress MCP, checksums, or directory artifacts.
- No backward-compat shims for whole-file fetch or old partial formats.
- WSL `dd` range read is intentionally simple; optimize later if needed.
