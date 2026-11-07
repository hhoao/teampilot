# Home Plane Runtime Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every home storage plane its own identity value object and its own cache instances, so no plane-derived snapshot can be read by another plane even when their `appDataRoot` strings are identical.

**Architecture:** This is Plan 1 of the home-plane isolation program defined in `docs/superpowers/specs/2026-11-07-home-plane-runtime-isolation-design.md`. It removes the two `static` snapshot maps that key by path string and replaces them with instance-owned `PlaneSnapshotCache<T>` values. `HomeRuntime` (the per-plane composition root) arrives in Plan 2 and will own these repository instances; the cache lifetime then falls out structurally — cache dies with the repository, repository dies with the runtime. Plan 1 also adds the `WorkspaceSearchIndexes.clear()` seam that Plan 2's transport rebind calls, plus a source-level guard that prevents new static plane caches.

**Tech Stack:** Dart 3 / Flutter, `flutter_test`, `InMemoryFilesystem` + `fakeHomeStorage` test doubles.

## Scope and follow-up plans

Plan 1 (this document) delivers:

- `HomeRuntimeIdentity` value object.
- `PlaneSnapshotCache<T>`.
- Instance-scoped workspace index cache in `SessionRepository`.
- Instance-scoped launch profile cache in `LaunchProfileRepository`.
- `WorkspaceSearchIndexes.clear()`.
- A source guard against new static plane caches in `lib/repositories/`, `lib/services/storage/`, `lib/services/search/`.

Not in this plan (later plans, in order):

1. **Plan 2 — runtime skeleton:** `HomeRuntime` + `HomeRuntimeFactory`, per-plane construction of repositories, `transportGeneration`/rebind, isolation tests through the runtime.
2. **Plan 3 — data layer:** move every plane repository/store/index/cache into the runtime; delete the `reloadAll` catch-up paths.
3. **Plan 4 — cubits and UI:** plane cubits into the runtime; `HomeRuntimeHost`; two-level Provider tree; `ShortcutCubit` to the device plane.
4. **Plan 5 — cleanup and docs:** delete `HomeInvalidationService` family; lease-based `RuntimeContextRegistry`; update `docs/ARCHITECTURE.md` and `docs/workspace-storage-layout.md`.

## Global Constraints

- Never run `flutter test` directly. Always `cd client && dart run tool/run_tests.dart <paths/options>`.
- Fast inner loop is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (full suite, once).
- No backward-compatibility shims, deprecated re-exports, or migration adapters. Delete replaced code outright.
- No new `static` mutable plane cache anywhere under `lib/repositories/`, `lib/services/storage/`, or `lib/services/search/`. Instance state only.
- No `print`; diagnostics go through `AppLogger`.
- User-facing copy goes through l10n (`client/lib/l10n/app_en.arb`, `app_zh.arb` only).
- Respect file soft limits (`services/` ~600 lines, `cubits/` ~500 lines); prefer focused files.
- Commit only the files listed in each task. The working tree contains unrelated changes.
- `docs/superpowers/specs/2026-11-07-home-plane-runtime-isolation-design.md` is the source of truth for the broader architecture.

---

## File Structure

| File | Responsibility |
|---|---|
| `client/lib/services/storage/home_runtime_identity.dart` | Immutable plane identity (`targetId`, `appDataRoot`) with value equality. |
| `client/lib/services/storage/plane_snapshot_cache.dart` | Small mutable holder for one plane-scoped immutable snapshot list. |
| `client/lib/repositories/session_repository.dart` | Replace static path-keyed workspace index map with an instance cache. |
| `client/lib/repositories/launch_profile_repository.dart` | Replace static path-keyed launch profile map with an instance cache. |
| `client/lib/services/search/workspace_search_indexes.dart` | Add `clear()` to drop fs-bound file/content indexes. |
| `client/test/app/home_runtime_identity_test.dart` | Identity equality/hash/string semantics. |
| `client/test/services/storage/plane_snapshot_cache_test.dart` | Cache freeze/replace/invalidate semantics. |
| `client/test/repositories/session_repository_plane_isolation_test.dart` | Same root string, different filesystem: no workspace index leak. |
| `client/test/repositories/launch_profile_repository_plane_isolation_test.dart` | Same root string, different filesystem: no launch profile leak. |
| `client/test/services/search/workspace_search_indexes_test.dart` | `clear()` drops both index kinds. |
| `client/test/app/plane_cache_ownership_guard_test.dart` | Source guard for static plane caches. |

---

### Task 1: HomeRuntimeIdentity

**Files:**
- Create: `client/lib/services/storage/home_runtime_identity.dart`
- Test: `client/test/app/home_runtime_identity_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `HomeRuntimeIdentity({required String targetId, required String appDataRoot})`
  - `String toString()` returns `'$targetId\u0000$appDataRoot'`.
  - Value equality and matching `hashCode`.

- [ ] **Step 1: Write the failing test**

Create `client/test/app/home_runtime_identity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/home_runtime_identity.dart';

void main() {
  test('same target and app-data root are equal', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('same target with a different app-data root is a different plane', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/srv/team',
    );

    expect(a, isNot(b));
  });

  test('same app-data root on different targets is a different plane', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:laptop',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(a, isNot(b));
  });

  test('toString encodes both fields for ValueKey use', () {
    const identity = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(identity.toString(), 'ssh:studio\u0000/home/ubuntu/team');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/app/home_runtime_identity_test.dart
```

Expected: FAIL — `home_runtime_identity.dart` cannot be found (URI does not exist).

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/storage/home_runtime_identity.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Stable identity of one home storage plane.
///
/// Two runtimes with the same identity may rebind transport to each other;
/// any difference (including only [appDataRoot]) means a different plane that
/// must be constructed and disposed independently.
@immutable
final class HomeRuntimeIdentity {
  const HomeRuntimeIdentity({
    required this.targetId,
    required this.appDataRoot,
  });

  /// `'local'`, `'ssh:<profileId>'`, `'wsl:<distro>'`, `'termux:default'`.
  final String targetId;

  /// Resolved `<teampilotRoot>` on the host that owns [targetId].
  final String appDataRoot;

  @override
  bool operator ==(Object other) =>
      other is HomeRuntimeIdentity &&
      other.targetId == targetId &&
      other.appDataRoot == appDataRoot;

  @override
  int get hashCode => Object.hash(targetId, appDataRoot);

  @override
  String toString() => '$targetId\u0000$appDataRoot';
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/app/home_runtime_identity_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/home_runtime_identity.dart \
  client/test/app/home_runtime_identity_test.dart
git commit -m "feat(storage): add home runtime identity value object"
```

---

### Task 2: PlaneSnapshotCache

**Files:**
- Create: `client/lib/services/storage/plane_snapshot_cache.dart`
- Test: `client/test/services/storage/plane_snapshot_cache_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `PlaneSnapshotCache<T>()`
  - `List<T>? get snapshot`
  - `List<T> write(Iterable<T> values)` — stores and returns an unmodifiable copy.
  - `void invalidate()`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/storage/plane_snapshot_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/plane_snapshot_cache.dart';

void main() {
  test('starts empty', () {
    final cache = PlaneSnapshotCache<int>();

    expect(cache.snapshot, isNull);
  });

  test('write freezes a copy and returns the stored snapshot', () {
    final source = [1, 2, 3];
    final cache = PlaneSnapshotCache<int>();

    final stored = cache.write(source);
    source.add(4);

    expect(stored, [1, 2, 3]);
    expect(cache.snapshot, [1, 2, 3]);
    expect(identical(cache.snapshot, stored), isTrue);
    expect(() => stored.add(5), throwsUnsupportedError);
  });

  test('a second write replaces the snapshot', () {
    final cache = PlaneSnapshotCache<String>()
      ..write(['a'])
      ..write(['b', 'c']);

    expect(cache.snapshot, ['b', 'c']);
  });

  test('invalidate drops the snapshot', () {
    final cache = PlaneSnapshotCache<int>()..write([1]);

    cache.invalidate();

    expect(cache.snapshot, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/services/storage/plane_snapshot_cache_test.dart
```

Expected: FAIL — `plane_snapshot_cache.dart` cannot be found.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/storage/plane_snapshot_cache.dart`:

```dart
/// One immutable snapshot owned by a single plane object.
///
/// This type exists so plane caches are instance state by construction: the
/// snapshot dies with its owner, and two owners can never observe each other's
/// entries regardless of path strings. Never hold one of these in a `static`
/// field.
final class PlaneSnapshotCache<T> {
  List<T>? _snapshot;

  /// The current frozen snapshot, or `null` when nothing has been loaded.
  List<T>? get snapshot => _snapshot;

  /// Replaces the snapshot with an unmodifiable copy of [values].
  List<T> write(Iterable<T> values) {
    final frozen = List<T>.unmodifiable(values);
    _snapshot = frozen;
    return frozen;
  }

  /// Drops the snapshot so the next read reloads from the plane.
  void invalidate() {
    _snapshot = null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/services/storage/plane_snapshot_cache_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/plane_snapshot_cache.dart \
  client/test/services/storage/plane_snapshot_cache_test.dart
git commit -m "feat(storage): add plane-scoped snapshot cache"
```

---

### Task 3: Make the SessionRepository workspace index cache instance-scoped

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/test/repositories/session_list_load_test.dart:168`
- Test: `client/test/repositories/session_repository_plane_isolation_test.dart`

**Interfaces:**
- Consumes: `PlaneSnapshotCache<T>` from Task 2.
- Produces:
  - `SessionRepository` holds `PlaneSnapshotCache<Workspace>`; caches are no longer shared across instances.
  - `SessionRepository.debugResetWorkspacesIndexCache()` is deleted.

- [ ] **Step 1: Write the failing isolation test**

Create `client/test/repositories/session_repository_plane_isolation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('same root string on another plane does not leak the workspace index',
      () async {
    final fsA = InMemoryFilesystem();
    final fsB = InMemoryFilesystem();
    // Two remote hosts with the same user name resolve the same root string.
    const root = '/home/ubuntu/.teampilot';

    final repoA = SessionRepository(
      rootDir: root,
      storage: fakeHomeStorage(filesystem: fsA, appDataRoot: root),
    );
    final repoB = SessionRepository(
      rootDir: root,
      storage: fakeHomeStorage(filesystem: fsB, appDataRoot: root),
    );

    final workspace = await repoA.createWorkspace([
      const WorkspaceFolder(path: '/srv/app-a'),
    ]);
    final indexA = await repoA.loadWorkspacesIndex();
    expect(indexA.map((w) => w.workspaceId), [workspace.workspaceId]);

    final indexB = await repoB.loadWorkspacesIndex();
    expect(indexB, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/repositories/session_repository_plane_isolation_test.dart
```

Expected: FAIL — `indexB` contains the workspace created through `repoA`, because both repositories hit the static map keyed by `/home/ubuntu/.teampilot`.

- [ ] **Step 3: Replace the static map with an instance cache**

In `client/lib/repositories/session_repository.dart`:

Add the import near the other storage imports:

```dart
import '../services/storage/plane_snapshot_cache.dart';
```

Replace lines 62-71 (the static map, `debugResetWorkspacesIndexCache`, and `_workspacesIndexCacheKey`) with:

```dart
  final PlaneSnapshotCache<Workspace> _workspaceIndexCache =
      PlaneSnapshotCache<Workspace>();
```

Replace `_rememberWorkspacesIndex`:

```dart
  List<Workspace> _rememberWorkspacesIndex(List<Workspace> workspaces) {
    return _workspaceIndexCache.write([
      for (final workspace in workspaces)
        _withInferredMemberPlacementInit(workspace),
    ]);
  }
```

Replace `_rememberWorkspace`:

```dart
  Future<void> _rememberWorkspace(Workspace workspace) async {
    final current = _workspaceIndexCache.snapshot;
    if (current != null) {
      final inferred = _withInferredMemberPlacementInit(workspace);
      final exists = current.any(
        (existing) => existing.workspaceId == workspace.workspaceId,
      );
      _workspaceIndexCache.write(
        exists
            ? [
                for (final existing in current)
                  if (existing.workspaceId == workspace.workspaceId)
                    inferred
                  else
                    existing,
              ]
            : [...current, inferred],
      );
    }
    await WorkspaceIndexStore(await _fs()).upsert(workspace);
  }
```

Replace `_forgetWorkspace`:

```dart
  Future<void> _forgetWorkspace(String workspaceId) async {
    final current = _workspaceIndexCache.snapshot;
    if (current != null) {
      _workspaceIndexCache.write(
        current.where((existing) => existing.workspaceId != workspaceId),
      );
    }
    await WorkspaceIndexStore(await _fs()).remove(workspaceId);
  }
```

Replace the first read in `loadWorkspacesIndex`:

```dart
    final cached = _workspaceIndexCache.snapshot;
```

In `createSession` (around line 969), delete `final key = _workspacesIndexCacheKey();` and change the loop to:

```dart
    for (final w in _workspaceIndexCache.snapshot ?? const <Workspace>[]) {
```

In `findSessionById` (around line 1024), change the collection-for source (there is no local cache-key variable in this method):

```dart
      for (final workspace
          in _workspaceIndexCache.snapshot ?? const <Workspace>[])
        workspace.workspaceId,
```

In `deleteSession` (around line 1418), change:

```dart
        final cachedList = _workspaceIndexCache.snapshot;
```

In `forkSession` (around line 1528), delete `final key = _workspacesIndexCacheKey();` and change the loop to:

```dart
      for (final w in _workspaceIndexCache.snapshot ?? const <Workspace>[]) {
```

Verify no stale references remain:

```bash
cd client && grep -n "_workspacesIndexByRoot\|_workspacesIndexCacheKey\|debugResetWorkspacesIndexCache" lib/repositories/session_repository.dart
```

Expected: no output.

- [ ] **Step 4: Remove the obsolete test reset call**

In `client/test/repositories/session_list_load_test.dart`, delete line 168:

```dart
    SessionRepository.debugResetWorkspacesIndexCache();
```

The following `SessionRepository fresh = ...` already starts with an empty instance cache, which is exactly what the test needs.

- [ ] **Step 5: Run the affected tests**

```bash
cd client && dart run tool/run_tests.dart \
  test/repositories/session_repository_plane_isolation_test.dart \
  test/repositories/session_list_load_test.dart
```

Expected: PASS. The isolation test now sees an empty `repB` index; the index-rebuild test still reads the snapshot from disk because `fresh` is a new instance.

- [ ] **Step 6: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/test/repositories/session_repository_plane_isolation_test.dart \
  client/test/repositories/session_list_load_test.dart
git commit -m "refactor(session): scope workspace index cache to the repository instance"
```

---

### Task 4: Make the LaunchProfileRepository cache instance-scoped

**Files:**
- Modify: `client/lib/repositories/launch_profile_repository.dart`
- Test: `client/test/repositories/launch_profile_repository_plane_isolation_test.dart`

**Interfaces:**
- Consumes: `PlaneSnapshotCache<T>` from Task 2.
- Produces:
  - `LaunchProfileRepository` holds `PlaneSnapshotCache<LaunchProfile>`; caches are no longer shared across instances.
  - `_loadAllCacheKey()` and `_invalidateLoadAllCache()` are deleted.
  - `_scheduleRevalidation` / `_revalidateLaunchProfilesSnapshot` no longer take a cache key.

- [ ] **Step 1: Write the failing isolation test**

Create `client/test/repositories/launch_profile_repository_plane_isolation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('same root string on another plane does not leak launch profiles',
      () async {
    final fsA = InMemoryFilesystem();
    final fsB = InMemoryFilesystem();
    const root = '/home/ubuntu/.teampilot/launch-profiles';

    final repoA = LaunchProfileRepository(
      rootDir: root,
      storage: fakeHomeStorage(
        filesystem: fsA,
        appDataRoot: '/home/ubuntu/.teampilot',
      ),
    );
    final repoB = LaunchProfileRepository(
      rootDir: root,
      storage: fakeHomeStorage(
        filesystem: fsB,
        appDataRoot: '/home/ubuntu/.teampilot',
      ),
    );

    await repoA.save(const TeamProfile(id: 'alpha', name: 'Alpha'));
    expect((await repoA.loadAll()).map((p) => p.id), ['alpha']);

    expect(await repoB.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/repositories/launch_profile_repository_plane_isolation_test.dart
```

Expected: FAIL — `repoB.loadAll()` returns `alpha` from the static map keyed by the shared root string.

- [ ] **Step 3: Replace the static map with an instance cache**

In `client/lib/repositories/launch_profile_repository.dart`:

Add the import:

```dart
import '../services/storage/plane_snapshot_cache.dart';
```

Replace line 28 with:

```dart
  final PlaneSnapshotCache<LaunchProfile> _cache =
      PlaneSnapshotCache<LaunchProfile>();
```

Delete `_loadAllCacheKey()` and `_invalidateLoadAllCache()`, and replace `_rememberLoadAll` with a direct write. The region that currently contains those three members becomes:

```dart
  Future<({String dir, Filesystem fs})> _paths() async {
```

Change `_scheduleRevalidation` to drop the `cacheKey` parameter:

```dart
  void _scheduleRevalidation(
    ({String dir, Filesystem fs}) paths,
    LaunchProfileIndexStore store,
    List<LaunchProfile> snapshot,
  ) {
    Future<void>? pending;
    pending =
        _revalidateLaunchProfilesSnapshot(
          paths,
          store,
          snapshot,
        ).whenComplete(() {
          if (identical(_revalidationFuture, pending)) {
            _revalidationFuture = null;
          }
        });
    _revalidationFuture = pending;
    unawaited(pending);
  }
```

Rewrite `loadAll` to use the instance cache:

```dart
  Future<List<LaunchProfile>> loadAll() async {
    final cached = _cache.snapshot;
    if (cached != null) {
      appLogger.i(
        '[boot] loadLaunchProfiles from memory count=${cached.length}',
      );
      return cached;
    }
    final paths = await _paths();
    final store = _indexStore(paths);
    final readSw = Stopwatch()..start();
    final snapshot = await store.tryRead();
    final readMs = readSw.elapsedMilliseconds;
    if (snapshot != null) {
      appLogger.i(
        '[boot] loadLaunchProfiles from snapshot count=${snapshot.length} '
        'read=${readMs}ms (validate deferred)',
      );
      _scheduleRevalidation(paths, store, snapshot);
      return _cache.write(_sorted(snapshot));
    } else {
      appLogger.i(
        '[boot] loadLaunchProfiles rebuilding snapshot read=${readMs}ms',
      );
    }
    final profiles = await _scanAll(paths);
    await store.writeAll(profiles);
    return _cache.write(profiles);
  }
```

Change `_revalidateLaunchProfilesSnapshot` to drop `cacheKey` and write through the cache:

```dart
  Future<void> _revalidateLaunchProfilesSnapshot(
    ({String dir, Filesystem fs}) paths,
    LaunchProfileIndexStore store,
    List<LaunchProfile> snapshot,
  ) async {
    final validateSw = Stopwatch()..start();
    final diskIds = await _listProfileIds(paths);
    final validateMs = validateSw.elapsedMilliseconds;
    if (_sameProfileIds(diskIds, snapshot)) {
      appLogger.i('[boot] loadLaunchProfiles validate ok +${validateMs}ms');
      return;
    }
    appLogger.i(
      '[boot] loadLaunchProfiles snapshot stale '
      'disk=${diskIds.length} index=${snapshot.length} '
      'validate=${validateMs}ms',
    );
    final profiles = await _scanAll(paths);
    await store.writeAll(profiles);
    _cache.write(profiles);
  }
```

In `save`, replace `_invalidateLoadAllCache();` with `_cache.invalidate();`.

In `delete`, replace `_invalidateLoadAllCache();` with `_cache.invalidate();`.

Verify no stale references remain:

```bash
cd client && grep -n "_loadAllByRoot\|_loadAllCacheKey\|_invalidateLoadAllCache\|_rememberLoadAll" lib/repositories/launch_profile_repository.dart
```

Expected: no output.

- [ ] **Step 4: Run the affected tests**

```bash
cd client && dart run tool/run_tests.dart \
  test/repositories/launch_profile_repository_plane_isolation_test.dart \
  test/repositories/launch_profile_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/launch_profile_repository.dart \
  client/test/repositories/launch_profile_repository_plane_isolation_test.dart
git commit -m "refactor(profiles): scope launch profile cache to the repository instance"
```

---

### Task 5: Add WorkspaceSearchIndexes.clear()

**Files:**
- Modify: `client/lib/services/search/workspace_search_indexes.dart`
- Test: `client/test/services/search/workspace_search_indexes_test.dart`

**Interfaces:**
- Consumes: `WorkspaceFileIndexRegistry.clear()` and `WorkspaceSessionContentIndex.dispose()`.
- Produces:
  - `void WorkspaceSearchIndexes.clear()` — drops every fs-bound file index and content index.
  - Plan 2's `HomeRuntime.rebindTransport` calls this after incrementing `transportGeneration`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/search/workspace_search_indexes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/search/workspace_search_indexes.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('clear drops both file and content indexes', () {
    final indexes = WorkspaceSearchIndexes(
      storage: fakeHomeStorage(filesystem: InMemoryFilesystem()),
    );

    final fileIndex = indexes.fileIndexFor('/srv/app');
    final contentIndex = indexes.contentIndexFor('ws-1');

    indexes.clear();

    expect(identical(indexes.fileIndexFor('/srv/app'), fileIndex), isFalse);
    expect(
      identical(indexes.contentIndexFor('ws-1'), contentIndex),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/services/search/workspace_search_indexes_test.dart
```

Expected: FAIL — `clear` is not defined on `WorkspaceSearchIndexes`.

- [ ] **Step 3: Implement clear()**

In `client/lib/services/search/workspace_search_indexes.dart`, add below `disposeWorkspace`:

```dart
  /// Drops every index bound to the current transport.
  ///
  /// Called on a same-identity transport rebind: the plane and its value caches
  /// survive, but indexes that captured the old `fs` must be rebuilt against
  /// the new one. An identity change disposes the whole runtime instead.
  void clear() {
    _fileIndexes.clear();
    for (final index in _contentByWorkspace.values) {
      index.dispose();
    }
    _contentByWorkspace.clear();
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/services/search/workspace_search_indexes_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/search/workspace_search_indexes.dart \
  client/test/services/search/workspace_search_indexes_test.dart
git commit -m "feat(search): add clear() for transport rebinds"
```

---

### Task 6: Guard against new static plane caches

**Files:**
- Test: `client/test/app/plane_cache_ownership_guard_test.dart`

**Interfaces:**
- Consumes: the repository layouts produced by Tasks 3-4.
- Produces: a failing check whenever a `static` `Map`/`List`/`Set` field is added under the guarded layers, unless allowlisted.

- [ ] **Step 1: Write the guard test**

Create `client/test/app/plane_cache_ownership_guard_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Invariant I1 of the home-plane isolation spec: plane-derived state must be
/// instance state owned by the runtime, never a static cache.
void main() {
  test('no static collection caches in plane-derived layers', () {
    const guardedDirs = [
      'lib/repositories',
      'lib/services/storage',
      'lib/services/search',
    ];

    // Coordination primitives keyed by path/id that self-clean when idle and
    // hold no plane data. Add an entry only with a comment explaining why it is
    // not a plane cache.
    const allowlist = {
      // Serializes concurrent writers per storage path; entries are removed
      // when the mutation finishes.
      'lib/repositories/managed_provider_storage_lock.dart:_tails',
      // Tracks in-flight provider-id deletions; entries are removed at idle.
      'lib/repositories/managed_provider_id_deletion_barrier.dart:_states',
    };

    final declaration = RegExp(
      r'^\s*static\s+(?:final\s+)?(?:Map|List|Set)<[^=;\n]*>'
      r'\s+([A-Za-z_]\w*)\s*=',
      multiLine: true,
    );

    final violations = <String>[];
    for (final dir in guardedDirs) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        for (final match in declaration.allMatches(text)) {
          final id =
              '${entity.path.replaceAll(r'\', '/')}:${match.group(1)}';
          if (!allowlist.contains(id)) violations.add(id);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plane-derived caches must be instance state owned by HomeRuntime. '
          'If the entry is coordination-only, add it to the allowlist with a '
          'reason.',
    );
  });
}
```

- [ ] **Step 2: Run the guard test**

```bash
cd client && dart run tool/run_tests.dart test/app/plane_cache_ownership_guard_test.dart
```

Expected: PASS. If it fails, the named static field is a real violation — fix the code rather than adding an allowlist entry.

- [ ] **Step 3: Commit**

```bash
git add client/test/app/plane_cache_ownership_guard_test.dart
git commit -m "test: guard plane layers against static cache regressions"
```

---

### Task 7: Final verification

**Files:** none (verification only; commit only if a check requires a fix).

- [ ] **Step 1: Run the analyzer**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors.

- [ ] **Step 2: Run the full unit/widget suite**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: PASS. The static map removal can expose tests that relied on cross-instance cache sharing; fix those tests by constructing a single repository per test or by letting the fresh instance read the index snapshot from disk. Do not restore a static cache to make a test pass.

- [ ] **Step 3: Commit any fallout fixes**

```bash
git status --short
# Stage only the files changed for fallout fixes, then:
git commit -m "test: align repository tests with instance-scoped caches"
```

If no files changed, skip this step.

---

## Self-Review

**Spec coverage (Plan 1 slice):**

- Spec §2 identity: Task 1 (`HomeRuntimeIdentity`, `targetId` + `appDataRoot` equality).
- Spec §7 value caches: Tasks 2-4 (static maps removed, instance-owned snapshots).
- Spec §7 fs-bound caches: Task 5 (`WorkspaceSearchIndexes.clear()` seam for rebind).
- Spec §13 I1: Task 6 source guard.
- Spec §12 deletions: Task 3 removes `debugResetWorkspacesIndexCache`; Task 4 removes the launch-profile static map.
- Remaining spec items (runtime, factory, UI host, lease broker, deletion of `HomeInvalidationService`) are explicitly assigned to Plans 2-5 above; they are not silently dropped.

**Placeholder scan:** no TBD/TODO; every step has exact code or an exact command with expected output.

**Type consistency:** `PlaneSnapshotCache<T>.write(Iterable<T>)` returns `List<T>` and is used identically in both repositories. `HomeRuntimeIdentity` fields are `targetId`/`appDataRoot` everywhere. `WorkspaceSearchIndexes.clear()` matches the spec's rebind step naming.

**Known behavior change:** `main.dart:500` calls `prefetchHomeIndexSnapshots`, which constructs throwaway repositories. After this plan those instances still warm the on-disk index snapshots but no longer populate the app repositories' in-memory caches. Plan 2 replaces that prefetch with `HomeRuntime.warm()` on the runtime-owned repositories, restoring the in-memory warm path.
