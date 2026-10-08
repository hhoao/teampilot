# Work-plane Apply Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Off-home SSH session flush compiles a v1 ApplyPlan (provided-link + blob-split) into at most one mutation script and one overlay tar, so plugin/skill trees already on the work root are `ln` instead of re-shipped.

**Architecture:** Keep `LaunchManifest` as the staging API. `WorkPathProjector` turns it into `ApplyPlan` plus an in-memory `BlobStore`. Local flush runs `WorkPlaneApplier`. SSH flush compiles the plan (not the raw manifest) with the existing `bash -s` / `gzip|tar` stdin transport. Epoch splitting of the unexpanded manifest is retired. Phase 2 (`teampilot-apply`, on-disk cas, provision rewrite) is a **separate plan**.

**Tech Stack:** Dart 3.8 / Flutter (`client/`), `package:crypto` (`sha256.convert(bytes).toString()`), `package:archive` overlay helpers already in `manifest_ssh_overlay.dart`, existing `SshWorkPlaneScriptRunner`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-16-work-plane-apply-design.md` (phase 1 only).
- `protocolVersion` is `1`. Inline UTF-8 `writeFile` limit is **4096 bytes** (hard constant `applyPlanInlineLimitBytes`).
- ApplyPlan paths and symlink targets must be under `workRoot`; reject `..`, NUL, and escapes.
- Never put file bodies in the SSH `exec` command (max ~1KB). Scripts: `bash -s` + stdin. Tar: `gzip -dc | tar -x -C <workRoot>`.
- Do not pack the entire TeamPilot home.
- `cd client && dart run tool/run_tests.dart <paths>` — never `flutter test` in `client/`.
- Services stay near ~600 lines; new types go in new files. Do not grow `manifest_executor.dart` with projector/compiler logic.
- Do not add `teampilot-apply`, on-disk `cas/`, or provision SFTP changes in this plan.
- Do not commit unless the user asks; skip commit steps during execution if they have not.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/launch/apply_plan.dart` | `ApplyPlan` / `ApplyOp`, JSON, path sandbox, sha256 helper, inline limit |
| `client/lib/services/launch/blob_store.dart` | `BlobStore` + `MemoryBlobStore` |
| `client/lib/services/launch/work_path_projector.dart` | `buildApplyPlan` from `LaunchManifest` |
| `client/lib/services/launch/work_plane_applier.dart` | In-process apply onto a `Filesystem` |
| `client/lib/services/launch/apply_plan_ssh_compiler.dart` | Plan → ≤2 SSH payloads (script, tar) |
| `client/lib/services/launch/manifest_executor.dart` | Call projector; local applier vs SSH compiler |
| `client/lib/services/launch/session_connect_orchestrator.dart` | Pass `homeRoot` into `flush` |
| Tests listed per task | |

---

### Task 1: ApplyPlan model, JSON, sandbox

**Files:**
- Create: `client/lib/services/launch/apply_plan.dart`
- Test: `client/test/services/launch/apply_plan_test.dart`

**Interfaces:**
- Consumes: `package:path/path.dart`, `package:crypto/crypto.dart`
- Produces:

```dart
const applyPlanProtocolVersion = 1;
const applyPlanInlineLimitBytes = 4096;

String contentSha256Hex(List<int> bytes);

void assertApplyPath({
  required String path,
  required String workRoot,
  required p.Context pathContext,
});

sealed class ApplyOp { Map<String, Object?> toJson(); }

final class ApplyEnsureDir extends ApplyOp { ApplyEnsureDir(this.path); final String path; }
final class ApplyRemove extends ApplyOp { ApplyRemove(this.path); final String path; }
final class ApplyRename extends ApplyOp { ApplyRename({required this.from, required this.to}); final String from; final String to; }
final class ApplySymlink extends ApplyOp { ApplySymlink({required this.linkPath, required this.target}); final String linkPath; final String target; }
final class ApplyWriteInline extends ApplyOp { ApplyWriteInline({required this.path, required this.content, this.mode}); final String path; final String content; final int? mode; }
final class ApplyWriteBlob extends ApplyOp { ApplyWriteBlob({required this.path, required this.sha256, this.mode}); final String path; final String sha256; final int? mode; }
final class ApplyTree extends ApplyOp {
  ApplyTree({required this.dest, required this.entries});
  final String dest;
  final List<ApplyTreeEntry> entries;
}
final class ApplyTreeEntry {
  const ApplyTreeEntry({required this.rel, required this.sha256, this.mode});
  final String rel;
  final String sha256;
  final int? mode;
}

final class ApplyPlan {
  const ApplyPlan({required this.workRoot, required this.ops, this.protocolVersion = applyPlanProtocolVersion});
  final int protocolVersion;
  final String workRoot;
  final List<ApplyOp> ops;
  Map<String, Object?> toJson();
  factory ApplyPlan.fromJson(Map<String, Object?> json);
  static ApplyOp opFromJson(Map<String, Object?> json);
}
```

JSON `op` strings: `ensureDir`, `remove`, `rename`, `symlink`, `writeInline`, `writeBlob`, `tree`. Tree entries: `{ "rel", "sha256", "mode"? }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/launch/apply_plan.dart';

void main() {
  final ctx = p.Context(style: p.Style.posix);

  test('json roundtrip keeps protocolVersion 1 and op order', () {
    final plan = ApplyPlan(
      workRoot: '/work',
      ops: [
        ApplyEnsureDir('/work/a'),
        ApplyWriteInline(path: '/work/a/f.txt', content: 'hi'),
        ApplyWriteBlob(path: '/work/a/b.bin', sha256: 'ab' * 32),
        ApplyTree(
          dest: '/work/t',
          entries: [ApplyTreeEntry(rel: 'x', sha256: 'cd' * 32)],
        ),
        ApplySymlink(linkPath: '/work/l', target: '/work/t'),
        ApplyRemove('/work/old'),
        ApplyRename(from: '/work/a', to: '/work/b'),
      ],
    );
    final decoded = ApplyPlan.fromJson(plan.toJson());
    expect(decoded.protocolVersion, applyPlanProtocolVersion);
    expect(decoded.workRoot, '/work');
    expect(decoded.ops, hasLength(7));
    expect(decoded.ops[0], isA<ApplyEnsureDir>());
    expect(decoded.ops[4], isA<ApplySymlink>());
  });

  test('sandbox rejects path escape and NUL', () {
    expect(
      () => assertApplyPath(
        path: '/work/../etc/passwd',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    expect(
      () => assertApplyPath(
        path: '/work/a\x00b',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    expect(
      () => assertApplyPath(
        path: '/etc/passwd',
        workRoot: '/work',
        pathContext: ctx,
      ),
      throwsStateError,
    );
    assertApplyPath(path: '/work', workRoot: '/work', pathContext: ctx);
    assertApplyPath(path: '/work/a/b', workRoot: '/work', pathContext: ctx);
  });

  test('utf8 writeFile threshold is 4096', () {
    expect(utf8.encode('a' * applyPlanInlineLimitBytes).length, 4096);
  });
}
```

Add `import 'dart:convert';` for `utf8`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/apply_plan_test.dart`

Expected: FAIL compile — `apply_plan.dart` missing.

- [ ] **Step 3: Write minimal implementation**

Implement `apply_plan.dart` as specified. `assertApplyPath`:

- throw `StateError` if `path` contains `'\x00'`
- normalize with `pathContext.normalize`
- throw if `pathContext.split(normalized)` contains `'..'`
- throw if `normalized != workRoot` and `!pathContext.isWithin(workRoot, normalized)`

`fromJson`: if `protocolVersion != 1`, throw `StateError('unsupported protocolVersion')`.

`contentSha256Hex`: `sha256.convert(bytes).toString()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/apply_plan_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** (skip unless the user asked)

```bash
git add client/lib/services/launch/apply_plan.dart client/test/services/launch/apply_plan_test.dart
git commit -m "feat(launch): add ApplyPlan v1 model and path sandbox"
```

---

### Task 2: Memory blob store

**Files:**
- Create: `client/lib/services/launch/blob_store.dart`
- Test: `client/test/services/launch/blob_store_test.dart`

**Interfaces:**
- Consumes: `contentSha256Hex` from Task 1
- Produces:

```dart
abstract class BlobStore {
  Future<void> put(String sha256, List<int> bytes);
  Future<bool> has(String sha256);
  Future<List<int>> open(String sha256);
}

final class MemoryBlobStore implements BlobStore {
  MemoryBlobStore();
}
```

`open` throws `StateError('missing blob $sha256')` if absent. `put` of an existing hash is a no-op (immutable; do not overwrite). If `put` bytes do not match `contentSha256Hex(bytes)`, throw `StateError`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/blob_store.dart';

void main() {
  test('put then open returns bytes; missing throws', () async {
    final store = MemoryBlobStore();
    final bytes = <int>[0, 1, 255];
    final hash = contentSha256Hex(bytes);
    await store.put(hash, bytes);
    expect(await store.has(hash), isTrue);
    expect(await store.open(hash), bytes);
    expect(store.open('00' * 32), throwsStateError);
  });

  test('put with wrong hash throws and does not store', () async {
    final store = MemoryBlobStore();
    expect(
      () => store.put('00' * 32, <int>[1, 2, 3]),
      throwsStateError,
    );
    expect(await store.has('00' * 32), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/blob_store_test.dart`

Expected: FAIL compile — `blob_store.dart` missing.

- [ ] **Step 3: Write minimal implementation**

```dart
final class MemoryBlobStore implements BlobStore {
  final _bytes = <String, List<int>>{};

  @override
  Future<void> put(String sha256, List<int> bytes) async {
    final actual = contentSha256Hex(bytes);
    if (actual != sha256) {
      throw StateError('blob sha256 mismatch: expected $sha256 got $actual');
    }
    _bytes.putIfAbsent(sha256, () => List<int>.from(bytes));
  }

  @override
  Future<bool> has(String sha256) async => _bytes.containsKey(sha256);

  @override
  Future<List<int>> open(String sha256) async {
    final bytes = _bytes[sha256];
    if (bytes == null) throw StateError('missing blob $sha256');
    return bytes;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/blob_store_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/blob_store.dart client/test/services/launch/blob_store_test.dart
git commit -m "feat(launch): add in-memory BlobStore for ApplyPlan payloads"
```

---

### Task 3: WorkPathProjector (provided-link + blob-split)

**Files:**
- Create: `client/lib/services/launch/work_path_projector.dart`
- Test: `client/test/services/launch/work_path_projector_test.dart`

**Interfaces:**
- Consumes: `LaunchManifest`, `Filesystem` + `FilesystemLstat`, Tasks 1–2
- Produces:

```dart
final class ApplyPlanBuild {
  const ApplyPlanBuild({required this.plan, required this.blobs, required this.providedLinks});
  final ApplyPlan plan;
  final MemoryBlobStore blobs;
  final int providedLinks;
}

Future<ApplyPlanBuild> buildApplyPlan({
  required LaunchManifest manifest,
  required Filesystem sourceFs,
  required Filesystem workFs,
  required String homeRoot,
  required String workRoot,
});
```

**Projection** (`_candidate(path)`):

1. If `path` is `workRoot` or inside it → candidate is `path` (staging already uses `workTeampilotRoot`).
2. Else if `path` is `homeRoot` or inside it → `join(workRoot, relative(path, homeRoot))`.
3. Else → `null` (cannot project).

**Provided** (candidate non-null, under `workRoot`):

- `lstat(candidate)` exists on **workFs**.
- File: `contentSha256Hex(work bytes) == contentSha256Hex(source bytes)` (read source from sourceFs at the original path; work bytes from workFs at candidate). If source missing, not provided.
- Directory (copyTree / symlink-to-dir): exists as directory (or symlink-to-dir via `stat`); do not recursively hash.
- Symlink: `workFs.readSymlinkTarget(candidate)` equals the **projected** target string.

**Manifest walk (do not reorder):**

| Entry | Result |
|-------|--------|
| `ensureDir` | project path; `ApplyEnsureDir`. Fail if unprojectable. |
| `writeFile` | project path. If UTF-8 length ≤ 4096 → `ApplyWriteInline`. Else put blob, `ApplyWriteBlob`. |
| `removeRecursive` | `ApplyRemove` projected path |
| `rename` | `ApplyRename` both projected |
| `symlink` | project `linkPath` and `target`. If target unprojectable → `StateError` (no silent `_copyExternal`). If target provided or is under workRoot after projection → `ApplySymlink`. |
| `copyFile` | if source provided → `ApplySymlink(linkPath: dest, target: candidate)`. Else read source bytes, put blob, `ApplyWriteBlob` at projected dest. |
| `copyTree` | if source provided dir → `ApplySymlink` dest→candidate. Else list `sourceFs.listDirRecursive(source)`, skip directories, put each file blob, one `ApplyTree` (empty tree → `ApplyEnsureDir` dest only). Fail if dest unprojectable. |

`providedLinks` increments once per copy/symlink that became `ApplySymlink` because the source/target was provided.

Every emitted path/target: `assertApplyPath`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/work_path_projector.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('copyTree of provided install dir becomes symlink', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
    await workFs.ensureDir('/w/plugins/installed/foo');
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 1);
    expect(built.plan.ops, hasLength(1));
    final op = built.plan.ops.single as ApplySymlink;
    expect(op.linkPath, '/w/sessions/pool/foo');
    expect(op.target, '/w/plugins/installed/foo');
  });

  test('copyTree when work dir missing becomes hashed tree', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeBytes('/h/plugins/installed/foo/bin.dat', [0, 1, 255]);
    final manifest = LaunchManifest()
      ..copyTree(
        source: '/h/plugins/installed/foo',
        destination: '/w/sessions/pool/foo',
      );
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/h',
      workRoot: '/w',
    );
    expect(built.providedLinks, 0);
    final tree = built.plan.ops.whereType<ApplyTree>().single;
    expect(tree.dest, '/w/sessions/pool/foo');
    expect(tree.entries.single.rel, 'bin.dat');
    final bytes = await built.blobs.open(tree.entries.single.sha256);
    expect(bytes, [0, 1, 255]);
  });

  test('same path string different file bytes is not provided', () async {
    final sourceFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    await sourceFs.writeString('/tp/a.txt', 'local');
    await workFs.writeString('/tp/a.txt', 'remote');
    final manifest = LaunchManifest()
      ..copyFile(source: '/tp/a.txt', destination: '/tp/sess/a.txt');
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: workFs,
      homeRoot: '/tp',
      workRoot: '/tp',
    );
    expect(built.providedLinks, 0);
    expect(built.plan.ops.single, isA<ApplyWriteBlob>());
  });

  test('writeFile at 4096 stays inline; 4097 is blob', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..writeFile('/w/small.txt', 'a' * 4096)
      ..writeFile('/w/big.txt', 'a' * 4097);
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: fs,
      workFs: fs,
      homeRoot: '/w',
      workRoot: '/w',
    );
    expect(built.plan.ops[0], isA<ApplyWriteInline>());
    expect(built.plan.ops[1], isA<ApplyWriteBlob>());
  });

  test('unprojectable symlink target fails staging', () async {
    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..symlink(linkPath: '/w/l', target: '/not/in/roots');
    expect(
      () => buildApplyPlan(
        manifest: manifest,
        sourceFs: fs,
        workFs: fs,
        homeRoot: '/h',
        workRoot: '/w',
      ),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_path_projector_test.dart`

Expected: FAIL compile — projector missing.

- [ ] **Step 3: Write minimal implementation**

Implement `work_path_projector.dart`. Use `sourceFs.pathContext` (POSIX in tests). `listDirRecursive` names are relative; join with `pathContext.join(source, entry.name)` as `manifest_ssh_flush_plan.dart` already does.

For `copyTree` tree `rel`, use POSIX-relative path from `source` with `/` (the recursive listing in `InMemoryFilesystem` uses names like `foo/bin.dat` — match existing flush-plan tests: `entry.name` is the relative path from the listed root).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_path_projector_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/work_path_projector.dart client/test/services/launch/work_path_projector_test.dart
git commit -m "feat(launch): project LaunchManifest to ApplyPlan with provided-link"
```

---

### Task 4: WorkPlaneApplier (local / in-process)

**Files:**
- Create: `client/lib/services/launch/work_plane_applier.dart`
- Test: `client/test/services/launch/work_plane_applier_test.dart`

**Interfaces:**
- Consumes: `ApplyPlan`, `BlobStore`, `Filesystem`
- Produces:

```dart
final class WorkPlaneApplier {
  WorkPlaneApplier({required Filesystem fs, required BlobStore blobs, required String workRoot});
  Future<void> apply(ApplyPlan plan);
}
```

`apply`:

1. If `plan.protocolVersion != 1` throw `StateError('unsupported protocolVersion')`.
2. If normalized `plan.workRoot != workRoot` throw `StateError`.
3. Sandbox every path (`assertApplyPath`) including symlink targets, rename ends, tree `dest/rel`.
4. Ops in order:
   - `ensureDir` → `fs.ensureDir`
   - `remove` → `fs.removeRecursive`
   - `rename` → `fs.rename`
   - `writeInline` → `ensureDir(dirname)` + `writeString`
   - `writeBlob` → `blobs.open` then `ensureDir(dirname)` + `writeBytes`
   - `tree` → `ensureDir(dest)`; each entry `ensureDir(dirname(join(dest,rel)))` + `writeBytes`
   - `symlink` → `removeRecursive(linkPath)` then `createSymlink` (leftover-dir rule)

Missing blob: do not skip; let `open` throw.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/blob_store.dart';
import 'package:teampilot/services/launch/work_plane_applier.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('rm then writeBlob leaves file; writeBlob then rm removes it', () async {
    final fs = InMemoryFilesystem();
    final blobs = MemoryBlobStore();
    final bytes = utf8.encode('x');
    final hash = contentSha256Hex(bytes);
    await blobs.put(hash, bytes);
    const root = '/w';

    await WorkPlaneApplier(fs: fs, blobs: blobs, workRoot: root).apply(
      ApplyPlan(
        workRoot: root,
        ops: [
          ApplyRemove('$root/a.txt'),
          ApplyWriteBlob(path: '$root/a.txt', sha256: hash),
        ],
      ),
    );
    expect(await fs.readString('$root/a.txt'), 'x');

    await WorkPlaneApplier(fs: fs, blobs: blobs, workRoot: root).apply(
      ApplyPlan(
        workRoot: root,
        ops: [
          ApplyWriteBlob(path: '$root/a.txt', sha256: hash),
          ApplyRemove('$root/a.txt'),
        ],
      ),
    );
    expect((await fs.stat('$root/a.txt')).exists, isFalse);
  });

  test('symlink replaces leftover directory', () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/w/link');
    await fs.writeString('/w/link/stale.txt', 'old');
    await fs.ensureDir('/w/target');
    await WorkPlaneApplier(
      fs: fs,
      blobs: MemoryBlobStore(),
      workRoot: '/w',
    ).apply(
      ApplyPlan(
        workRoot: '/w',
        ops: [ApplySymlink(linkPath: '/w/link', target: '/w/target')],
      ),
    );
    expect(await fs.readSymlinkTarget('/w/link'), '/w/target');
  });

  test('escapes workRoot fail closed before later ops', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/w/keep.txt', 'keep');
    expect(
      () => WorkPlaneApplier(
        fs: fs,
        blobs: MemoryBlobStore(),
        workRoot: '/w',
      ).apply(
        ApplyPlan(
          workRoot: '/w',
          ops: [
            ApplyRemove('/etc/passwd'),
            ApplyRemove('/w/keep.txt'),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await fs.readString('/w/keep.txt'), 'keep');
  });
}
```

Add `import 'dart:convert';`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_plane_applier_test.dart`

Expected: FAIL compile — applier missing.

- [ ] **Step 3: Write minimal implementation**

`work_plane_applier.dart` as specified. Use `fs.pathContext` for join/dirname.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_plane_applier_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/work_plane_applier.dart client/test/services/launch/work_plane_applier_test.dart
git commit -m "feat(launch): apply ApplyPlan in-process with leftover-dir symlinks"
```

---

### Task 5: SSH compiler (≤2 execs from ApplyPlan)

**Files:**
- Create: `client/lib/services/launch/apply_plan_ssh_compiler.dart`
- Test: `client/test/services/launch/apply_plan_ssh_compiler_test.dart`
- Reuse: `posixShellQuote` from `manifest_ssh_flush_plan.dart`, overlay helpers from `manifest_ssh_overlay.dart`

**Interfaces:**
- Consumes: `ApplyPlan`, `BlobStore`, overlay encode/add, `posixShellQuote`
- Produces:

```dart
final class ApplyPlanSshPayload {
  const ApplyPlanSshPayload({this.script, this.gzipTar, this.extractCommand});
  final String? script;
  final Uint8List? gzipTar;
  final String? extractCommand;
}

Future<ApplyPlanSshPayload> compileApplyPlanForSsh({
  required ApplyPlan plan,
  required BlobStore blobs,
});
```

**Rules:**

- Mutation script (`set -e`) in **plan order** for `ensureDir`, `remove`, `rename`, `symlink` (`rm -rf` then `ln -sfn`), `writeInline` (heredoc like `buildMutationApplyScript`). Skip blob/tree ops in the script.
- One overlay tar: all `writeBlob` / `tree` files as members relative to `plan.workRoot` via `manifestOverlayRelativePath`. Last write per relative path wins. Use `addOverlayFile`. Missing overlay relative path → `StateError`.
- **Blob compaction before tar:** if a later `ApplyRemove` path equals or is a prefix of a blob dest (`pathContext.isWithin(removePath, dest) || dest == removePath`) and no later `writeBlob`/`tree` writes that dest again, drop that blob/tree from the tar. This makes **script then tar** correct for write-then-rm and rm-then-write.
- Execution order for the executor (Task 6): **script first (if any), then tar (if any)**. Never more than those two.
- Interleaved `ensureDir` / `symlink` / `writeInline` → **one** script, **zero** tars.
- Empty script and empty tar: payload with both null is allowed (no-op plan).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/apply_plan_ssh_compiler.dart';
import 'package:teampilot/services/launch/blob_store.dart';

void main() {
  test('ensureDir symlink writeInline is one script and no tar', () async {
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyEnsureDir('/w/a'),
          ApplySymlink(linkPath: '/w/a/l', target: '/w/t'),
          ApplyWriteInline(path: '/w/a/f.txt', content: 'hi'),
          ApplyEnsureDir('/w/b'),
          ApplySymlink(linkPath: '/w/b/l', target: '/w/t'),
        ],
      ),
      blobs: MemoryBlobStore(),
    );
    expect(payload.script, isNotNull);
    expect(payload.gzipTar, isNull);
    expect(payload.script, contains("ln -sfn"));
    expect(payload.script, contains('hi'));
  });

  test('blobs become one tar; script then tar order is encoded as script plus tar', () async {
    final blobs = MemoryBlobStore();
    final hash = contentSha256Hex([9, 8]);
    await blobs.put(hash, [9, 8]);
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyRemove('/w/pool'),
          ApplyWriteBlob(path: '/w/pool/a.bin', sha256: hash),
        ],
      ),
      blobs: blobs,
    );
    expect(payload.script, contains("rm -rf '/w/pool'"));
    expect(payload.gzipTar, isNotNull);
    expect(payload.extractCommand, contains("tar -x -C '/w'"));
    final tar = GZipDecoder().decodeBytes(payload.gzipTar!);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(decoded.findFile('pool/a.bin'), isNotNull);
  });

  test('writeBlob then remove of same path omits tar member', () async {
    final blobs = MemoryBlobStore();
    final hash = contentSha256Hex([1]);
    await blobs.put(hash, [1]);
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyWriteBlob(path: '/w/a.bin', sha256: hash),
          ApplyRemove('/w/a.bin'),
        ],
      ),
      blobs: blobs,
    );
    expect(payload.gzipTar, isNull);
    expect(payload.script, contains("rm -rf '/w/a.bin'"));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/apply_plan_ssh_compiler_test.dart`

Expected: FAIL compile — compiler missing.

- [ ] **Step 3: Write minimal implementation**

`apply_plan_ssh_compiler.dart`: build script with `posixShellQuote`; put tar members only for compacted blobs; `extractCommand: launchOverlayExtractCommand(plan.workRoot)` when tar non-empty.

If `plan.protocolVersion != 1` throw.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/apply_plan_ssh_compiler_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/apply_plan_ssh_compiler.dart client/test/services/launch/apply_plan_ssh_compiler_test.dart
git commit -m "feat(launch): compile ApplyPlan to at most one script and one tar"
```

---

### Task 6: Wire ManifestExecutor + homeRoot

**Files:**
- Modify: `client/lib/services/launch/manifest_executor.dart` (`flush`)
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart` (flush call ~346)
- Modify: `client/test/services/launch/manifest_executor_ssh_test.dart`
- Test: add cases in `manifest_executor_ssh_test.dart` (or `manifest_executor_apply_plan_test.dart` if the ssh test file would exceed comfort)

**Interfaces:**
- Consumes: `buildApplyPlan`, `WorkPlaneApplier`, `compileApplyPlanForSsh`, `SshWorkPlaneScriptRunner`
- Produces: `flush` gains `homeRoot`:

```dart
Future<void> flush({
  required LaunchManifest manifest,
  required Filesystem targetFs,
  required Filesystem sourceFs,
  String? sshProfileId,
  String? symlinkProjectionRoot,
  String? homeRoot,
});
```

**Behavior:**

```
workRoot = symlinkProjectionRoot trimmed
home = (homeRoot ?? workRoot)  // same-host / local default
built = await buildApplyPlan(..., workFs: targetFs, homeRoot: home, workRoot: workRoot or home if empty local)
log: [session-launch] apply-plan protocol=1 ops=… provided=… blobs=… blobBytes=… inlineBytes=…
if SSH runner != null:
  if !sameHost && workRoot empty → existing StateError
  payload = compileApplyPlanForSsh(plan: built.plan, blobs: built.blobs)
  log existing manifest flush via ssh line with ops=
  if payload.script != null → runScript
  if payload.gzipTar != null → runStdinCommand extract
  log done with epochs= (0-2), scriptEpochs, tarEpochs, stdinBytes
else:
  await WorkPlaneApplier(fs: targetFs, blobs: built.blobs, workRoot: workRoot or first path root).apply(built.plan)
```

For local flush with empty `symlinkProjectionRoot`, use `built.plan.workRoot` (projector must get a non-empty workRoot — orchestrator always passes `workContext.appDataRoot`). If both empty, throw `StateError`.

Do **not** call `buildManifestSshFlushPlan` from `flush`. Leave `manifest_ssh_flush_plan.dart` in tree for `posixShellQuote` / `buildMutationApplyScript` until a later cleanup; compiler should import `posixShellQuote` only.

Orchestrator:

```dart
await manifestExecutor.flush(
  manifest: staged.manifest,
  targetFs: workContext.fs,
  sourceFs: offHome ? homeContext().fs : workContext.fs,
  symlinkProjectionRoot: workContext.appDataRoot,
  homeRoot: homeContext().appDataRoot,
  sshProfileId: ...,
);
```

Local path no longer uses `_expandCopies` for the SSH-less branch when `workRoot` is set; `WorkPlaneApplier` handles copies via the plan. Keep `_flushLocal` only if some caller flushes without `workRoot` — after orchestrator always passes it, switch local to applier and keep `_flushLocal` as a private fallback for empty-root tests **or** require workRoot in all flush tests.

Update same-host ssh test: identical source/target, `homeRoot`/`symlinkProjectionRoot` `/dst`. `copyTree` `/src/tree` → `/dst/tree` is **not** provided (source outside roots) → `ApplyTree` + tar or files in tar; command is `bash -s` and/or gzip|tar, not `cp -R` in exec. Assert exec commands stay short (`length < 1024`) and stdin is non-empty.

Add test: off-home provided copyTree → single `bash -s` whose stdin contains `ln -sfn` and **no** tar exec.

Compute log fields: `blobs` = count of writeBlob+tree entries; `blobBytes` = sum of open() lengths; `inlineBytes` = utf8 lengths of writeInline; `provided` = `built.providedLinks`.

- [ ] **Step 1: Write/update failing tests**

In `manifest_executor_ssh_test.dart` add (using the existing `_RunnableClient` / `_RecordedExec` pattern in that file):

```dart
test('off-home provided copyTree flushes one ln script without tar exec', () async {
  final execs = <_RecordedExec>[];
  // same factory harness as 'same-host ssh flush' but sourceFs != targetFs
  final sourceFs = InMemoryFilesystem();
  final workFs = InMemoryFilesystem();
  await sourceFs.writeString('/h/plugins/installed/foo/a.txt', 'A');
  await workFs.ensureDir('/w/plugins/installed/foo');
  final manifest = LaunchManifest()
    ..copyTree(
      source: '/h/plugins/installed/foo',
      destination: '/w/sessions/pool/foo',
    );
  await ManifestExecutor(
    sshClientFactory: factory,
    profileById: (_) => profile,
  ).flush(
    manifest: manifest,
    targetFs: workFs,
    sourceFs: sourceFs,
    sshProfileId: profile.id,
    symlinkProjectionRoot: '/w',
    homeRoot: '/h',
  );
  expect(execs, hasLength(1));
  expect(execs.single.command, 'bash -s');
  expect(utf8.decode(execs.single.stdin!), contains("ln -sfn"));
});
```

Wire `factory` like the existing recording test (`runWithResult` records command+stdin).

Update tests that still call `flush` without `homeRoot`/`symlinkProjectionRoot` so off-home cases pass roots; same-host may omit `homeRoot`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_executor_ssh_test.dart`

Expected: FAIL — `flush` has no `homeRoot` and still uses epoch planner (multiple execs / no provided ln).

- [ ] **Step 3: Write minimal implementation**

Change `flush` as specified. Add `homeRoot` parameter. Orchestrator passes `homeContext().appDataRoot`.

Local: `WorkPlaneApplier` when `runner == null`.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```
cd client && dart run tool/run_tests.dart \
  test/services/launch/manifest_executor_ssh_test.dart \
  test/services/launch/work_path_projector_test.dart \
  test/services/launch/work_plane_applier_test.dart \
  test/services/launch/apply_plan_ssh_compiler_test.dart
```

Expected: All tests passed. Fix any same-host assertions that still require `cp -R` in the exec command.

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/manifest_executor.dart \
  client/lib/services/launch/session_connect_orchestrator.dart \
  client/test/services/launch/manifest_executor_ssh_test.dart
git commit -m "feat(launch): flush ApplyPlan with provided-link SSH compile"
```

---

### Task 7: Logging, analyze, retire epoch flush from executor

**Files:**
- Modify: `client/lib/services/launch/manifest_executor.dart` (log lines if not done in Task 6)
- Modify: `docs/superpowers/specs/2026-09-16-work-plane-apply-design.md` status `草案，待审阅` → `已批准`
- Test: extend executor test to capture logs **or** assert log by wrapping `appLogger` if existing tests already inspect logs (`manifest_executor_ssh_test` looks for `tarEpochs=` — update to `apply-plan` + `scriptEpochs=` / `tarEpochs=` 0 or 1)

**Interfaces:**
- Consumes: Task 6 flush
- Produces: debug logs

```
[session-launch] apply-plan protocol=1 ops=${plan.ops.length} provided=$providedLinks blobs=$blobCount blobBytes=$blobBytes inlineBytes=$inlineBytes
[session-launch] manifest flush via ssh ops=${manifest.entries.length}
[session-launch] manifest flush via ssh ops=… epochs=… scriptEpochs=… tarEpochs=… stdinBytes=…
```

Do not log sha256 lists at this logger.d call.

- [ ] **Step 1: Update failing log assertion**

If `manifest_executor_ssh_test.dart` contains `l.contains('tarEpochs=')`, also expect `apply-plan protocol=1` and `provided=`.

- [ ] **Step 2: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_executor_ssh_test.dart`

Expected: FAIL on missing `apply-plan` substring if Task 6 omitted logs.

- [ ] **Step 3: Add logs + spec status**

Insert the `apply-plan` log after `buildApplyPlan`. Set spec header status to `已批准`.

- [ ] **Step 4: Analyze + targeted tests**

Run:

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart \
  test/services/launch/apply_plan_test.dart \
  test/services/launch/blob_store_test.dart \
  test/services/launch/work_path_projector_test.dart \
  test/services/launch/work_plane_applier_test.dart \
  test/services/launch/apply_plan_ssh_compiler_test.dart \
  test/services/launch/manifest_executor_ssh_test.dart \
  test/services/launch/manifest_ssh_flush_plan_test.dart
```

Expected: analyze clean enough to ship; flush-plan unit tests still pass (helpers unused by executor may remain). `manifest_executor.dart` stays near ~600 lines — if over, move log field counting into `apply_plan.dart` (`ApplyPlanStats.measure(plan, blobs)`).

- [ ] **Step 5: Commit** (skip unless asked)

```bash
git add client/lib/services/launch/manifest_executor.dart \
  docs/superpowers/specs/2026-09-16-work-plane-apply-design.md \
  client/test/services/launch/manifest_executor_ssh_test.dart
git commit -m "feat(launch): log ApplyPlan flush stats"
```

---

## Self-review (spec coverage)

| Spec phase 1 requirement | Task |
|---|---|
| ApplyPlan v1 JSON + sandbox | 1 |
| Inline ≤4096 / else blob | 3 |
| Provided-link copyTree/copyFile/symlink | 3 |
| Same path string, different bytes → not provided | 3 |
| Fail unprojectable symlink (no silent `_copyExternal`) | 3 |
| In-memory blobs, no on-disk cas | 2, 3 |
| WorkPlaneApplier order + leftover dir | 4 |
| SSH ≤2 execs; kind-switch retired | 5, 6 |
| Interleaved mkdir/ln/inline → one script | 5 |
| script then tar + compaction | 5 |
| Orchestrator homeRoot | 6 |
| Logging apply-plan fields | 7 |
| Local in-process applier | 6 |
| No teampilot-apply / provision rewrite / GC | omitted (phase 2) |

Phase 2 is **not** in this plan.
