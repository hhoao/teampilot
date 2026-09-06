# Mobile Startup & Storage Architecture Optimization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut Android SSH-home cold start from ~58s (still loading at +65s) to ≤10s-to-ready, eliminate in-flight `SSH client closed` failures and the redundant second bootstrap, and fix the underlying storage/global-singleton architecture — no backward compatibility constraints.

**Architecture:** Three coordinated changes: (1) expert/team materialization becomes a single-snapshot batch resolve (one catalog fetch per boot, caches on device-local disk); (2) the `AppStorage` global singleton is replaced by an injected, versioned, drain-safe `HomeStorage` facade; (3) storage-plane invalidation moves out of the widget tree into a bootstrap-owned service with level-based reload granularity.

**Tech Stack:** Flutter/Dart, flutter_bloc, dartssh2, SFTP `Filesystem` abstraction.

## Global Constraints

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (from AGENTS.md).
- Layering: logic in `cubits/` + `services/` + `repositories/`; no storage-reload orchestration in `widgets/` or `pages/`.
- No `print`; diagnostics via `AppLogger` with `[boot]`-style tagged messages.
- New user-facing strings → `client/lib/l10n/app_en.arb` + `app_zh.arb` (expected: none in this plan).
- File size soft limits: services ~600, cubits ~500 lines — split when exceeded.
- Tests mock filesystem/subprocess via constructor injection (never real IO).
- Work in a worktree (superpowers:using-git-worktrees) — `main` is the merge target.

## Context: root causes (from log analysis, 2026-09-06)

Timeline: first paint ≈ +5s, then `bootstrapHomeIndex` blocks **42s** — of which `LaunchProfileCubit.load` = **35.3s** — then a redundant full second bootstrap fires at +56.5s (log ends mid-load at +65s).

1. **35.3s materialization**: `LaunchProfileCubit.load` → `_materializeTeams` (`client/lib/cubits/launch_profile_cubit.dart:284`) → `ExpertMemberMaterializer.attachMaterializedMembersAll` (`client/lib/services/expert_hub/expert_member_materializer.dart:132`) resolves each roster slot serially via `ExpertMemberResolver.resolveMember` (`client/lib/services/expert_hub/expert_member_resolver.dart:43`), which — with no `hubState`/cached `localStore` — falls through to `source.fetchMembers()`. `CompositeExpertHubSource.fetchMemberSources` (`client/lib/services/expert_hub/composite_expert_hub_source.dart:94`) re-runs `_localStore.loadAll()` (SFTP `find` + per-file reads) on **every call** — no memoization. Cost = teams × slots × full catalog fetch over SFTP.
2. **Redundant full bootstrap**: `bootstrapAppData` → `reconnectHomeSshIfNeeded` (`client/lib/app/app_shell.dart:2213`) → `SshConnectionCubit.connect` → (Android) `selectProfileOnConnect` (`client/lib/cubits/ssh_connection_cubit.dart:185`) → `applyAndroidSshConnectHome` → `homeTargetController.select('ssh:<same>')` → `switchHomeTarget` (`client/lib/app/app_shell.dart:2477`) with **no same-target guard** → `setHomeTarget` evicts the live home context (`runtimeContextRegistry.dispose`) → kills in-flight `prepareInteractiveShell` remote CLI probes (`SSHStateError(SSH client closed)` × ~20, log +54.6s `reason=runtimeContextEvicted`) → `reloadAllAppData` reruns the whole boot chain a second time.
3. **Architectural**: `AppStorage` is a runtime-mutable global (312 call sites over 117 files) — every consumer re-reads the global per call, so eviction can pull the floor out from under in-flight operations. Invalidation is triggered from a **widget** (`HomeSshProfileBinder`, `client/lib/widgets/ssh/home_ssh_profile_binder.dart`) and always does a full reload. Registry caches live under the SSH home root, so "cached" reads still cost SFTP round trips on Android.

Post-fix target timeline (Android, SSH home, Wi-Fi): +3.5s SSH connect (floor), +5s first paint, +6–8s index ready, ≤10s app ready; exactly one `bootstrapHomeIndex start` per cold boot; zero `runtimeContextEvicted` during boot.

---

### Task 1: Expert hub catalog snapshot + batch materialization (kills the 35s)

**Files:**
- Create: `client/lib/services/expert_hub/expert_hub_catalog.dart`
- Create: `client/test/services/expert_hub/expert_hub_catalog_test.dart`
- Modify: `client/lib/services/expert_hub/expert_member_materializer.dart` (rewrite resolution path)
- Modify: `client/lib/cubits/launch_profile_cubit.dart` (`_materializeTeams`/`_materializeTeam`, `attachExpertHubSource`)
- Modify: `client/lib/app/app_shell.dart:1423,1495` (wire catalog)
- Test: `client/test/services/expert_hub/expert_member_materializer_test.dart` (update/extend)

**Interfaces:**
- Produces: `class ExpertHubCatalog` with `Future<MemberCatalogSnapshot> snapshot()`, `void invalidate()`, `Future<MemberCatalogSnapshot> refresh()`; `class MemberCatalogSnapshot` with `DiscoverableMember? lookup(String? key)`; `ExpertMemberMaterializer.materializeAll(List<TeamProfile>, MemberCatalogSnapshot) → List<TeamProfile>` (sync); `LaunchProfileCubit.attachCatalog(ExpertHubCatalog)`.

- [ ] **Step 1: Write the failing test for ExpertHubCatalog**

```dart
// client/test/services/expert_hub/expert_hub_catalog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';

class _FakeSource implements ExpertHubSource {
  int fetchCount = 0;
  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    fetchCount++;
    return [
      DiscoverableMember.fromJson({
        'key': 'teampilot/builtin/pm',
        'name': 'PM',
      }),
    ];
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => [];
}

void main() {
  test('snapshot() is single-flight: concurrent callers fetch once', () async {
    final source = _FakeSource();
    final catalog = ExpertHubCatalog(source: source);
    final a = catalog.snapshot();
    final b = catalog.snapshot();
    expect(identical(await a, await b), isTrue);
    expect(source.fetchCount, 1);
  });

  test('invalidate() forces the next snapshot() to refetch', () async {
    final source = _FakeSource();
    final catalog = ExpertHubCatalog(source: source);
    await catalog.snapshot();
    catalog.invalidate();
    await catalog.snapshot();
    expect(source.fetchCount, 2);
  });

  test('lookup trims and hits by key', () async {
    final catalog = ExpertHubCatalog(source: _FakeSource());
    final snap = await catalog.snapshot();
    expect(snap.lookup(' teampilot/builtin/pm ')?.name, 'PM');
    expect(snap.lookup('missing'), isNull);
  });
}
```

Note: `ExpertHubCatalog` constructor takes `ExpertHubSource` (interface — not just the composite) so tests stay trivial; app wiring passes the composite.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/expert_hub/expert_hub_catalog_test.dart`
Expected: FAIL — `expert_hub_catalog.dart` does not exist.

- [ ] **Step 3: Implement ExpertHubCatalog**

```dart
// client/lib/services/expert_hub/expert_hub_catalog.dart
import '../../models/discoverable_member.dart';
import 'expert_hub_source.dart';

/// Immutable resolved view of every discoverable expert, keyed by catalog key.
/// Precedence (local clone > registry > builtin) is whatever the backing
/// source's `fetchMembers` merge produces.
class MemberCatalogSnapshot {
  const MemberCatalogSnapshot(this.byKey);

  final Map<String, DiscoverableMember> byKey;

  DiscoverableMember? lookup(String? key) => byKey[key?.trim() ?? ''];
}

/// One catalog load per process, shared by every consumer. Single-flight:
/// concurrent callers await the same fetch. [invalidate] clears the snapshot
/// (call after local expert mutations); [refresh] reloads immediately.
class ExpertHubCatalog {
  ExpertHubCatalog({required ExpertHubSource source}) : _source = source;

  final ExpertHubSource _source;
  MemberCatalogSnapshot? _snapshot;
  Future<MemberCatalogSnapshot>? _pending;

  Future<MemberCatalogSnapshot> snapshot() {
    final cached = _snapshot;
    if (cached != null) return Future.value(cached);
    return _pending ??= _load();
  }

  Future<MemberCatalogSnapshot> refresh() {
    invalidate();
    return snapshot();
  }

  void invalidate() {
    _snapshot = null;
    _pending = null;
  }

  Future<MemberCatalogSnapshot> _load() async {
    final pending = _pending!;
    try {
      final members = await _source.fetchMembers();
      final snap = MemberCatalogSnapshot({
        for (final m in members) m.key: m,
      });
      if (identical(_pending, pending)) _snapshot = snap;
      return snap;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }
}
```

- [ ] **Step 4: Run catalog test — PASS**

Run: `cd client && flutter test test/services/expert_hub/expert_hub_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing batch-materialization test**

Extend `client/test/services/expert_hub/expert_member_materializer_test.dart` (create if absent; build `TeamProfile`/`TeamRosterSlot` via existing test helpers — grep `materializeRosterSlot` in `client/test/` for fixtures):

```dart
test('materializeAll resolves every slot from one snapshot — no per-slot fetch',
    () async {
  final snapshot = MemberCatalogSnapshot({
    for (var i = 0; i < 5; i++)
      'key$i': _member('key$i'), // _member builds a DiscoverableMember
  });
  final teams = [
    _team(roster: [_slot('key0'), _slot('key1'), _slot('key2')]),
    _team(roster: [_slot('key1'), _slot('key3'), _slot('missing')]),
  ];
  final resolved = ExpertMemberMaterializer.materializeAll(teams, snapshot);
  expect(resolved.first.members, hasLength(3));
  expect(resolved.last.members, hasLength(2)); // 'missing' dropped
});
```

- [ ] **Step 6: Rewrite the materializer**

In `client/lib/services/expert_hub/expert_member_materializer.dart`:

- Add `materializeAll(List<TeamProfile> teams, MemberCatalogSnapshot snapshot) → List<TeamProfile>` — a plain sync loop calling `materializeTeam`.
- Add `materializeTeam(TeamProfile, MemberCatalogSnapshot)`: `team.copyWith(members: [for (final slot in team.roster) if (snapshot.lookup(slot.expertKey) case final expert?) materializeRosterSlot(slot: slot, expert: expert, team: team)])`.
- Replace `attachMaterializedMembers`/`attachMaterializedMembersAll`/`materializeRosterAsync` bodies (or delete them and migrate their callers — grep callers first: `client/lib/cubits/launch_profile_cubit.dart:167,284` plus any others). No backward compatibility required: prefer deletion over delegation.
- `ExpertMemberResolver.resolveMember` remains only for genuine one-off single-key async resolution; its per-key `source.fetchMembers` fallback must route through an injected `ExpertHubCatalog` (add optional `catalog` param) so even that path is single-flight.

- [ ] **Step 7: Update LaunchProfileCubit**

`client/lib/cubits/launch_profile_cubit.dart`:

- Replace field `_expertHubSource` + `attachExpertHubSource` with `ExpertHubCatalog? _catalog` + `void attachCatalog(ExpertHubCatalog catalog)`.
- In `load()` (line ~284): `teams = ExpertMemberMaterializer.materializeAll(teams, await _catalog!.snapshot());` (guard null catalog by falling back to no materialization + a `appLogger.w` — keeps simple-mode unit tests alive).
- Same change for the other `_materializeTeam` site (line ~573 region) and any `reload` path that materializes.

- [ ] **Step 8: Wire in app_shell**

`client/lib/app/app_shell.dart` after `compositeExpertHubSource` (~line 1423):

```dart
final expertHubCatalog = ExpertHubCatalog(source: compositeExpertHubSource);
// replaces: teamCubit.attachExpertHubSource(compositeExpertHubSource)
teamCubit.attachCatalog(expertHubCatalog);
```

Local expert mutation sites must invalidate: grep `putClone(`/`LocalExpertStore().save(` in `client/lib/` (notably `ExpertCloneService`, `ExpertHubCubit` create/edit) and call `expertHubCatalog.invalidate()` after each write. Pass the catalog into those services via constructor (never a global).

- [ ] **Step 9: Run tests + analyze; commit**

Run: `cd client && flutter test test/services/expert_hub/ test/cubits/ && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS (update existing tests that referenced `attachExpertHubSource`).

```bash
git add -A && git commit -m "perf(expert-hub): single-snapshot batch materialization for team rosters

Replaces per-slot serial full-catalog resolution (teams x slots x SFTP
round trips, ~35s on Android SSH home) with one single-flight catalog
snapshot per boot. Local expert mutations invalidate the snapshot."
```

---

### Task 2: Device-local catalog caches (registry + team hub)

**Files:**
- Modify: `client/lib/services/expert_hub/git_registry_expert_hub_source.dart` (cache dir plumbing — already has `cacheDirOverride`)
- Modify: `client/lib/services/team_hub/git_registry_team_hub_source.dart` (same; verify it has an override — if not, add one mirroring the expert one)
- Modify: `client/lib/app/app_shell.dart:1416-1423` (pass device-local dirs)
- Test: extend existing source tests (`client/test/services/...` grep `GitRegistryExpertHubSource`)

**Interfaces:**
- Consumes: `nativeAppDataPath` (already threaded in `buildAppShell`), `deviceLocalSshProfileRepository` pattern at `client/lib/app/app_shell.dart:692`.

- [ ] **Step 1: Device-local cache root helper**

Add (in `app_shell.dart` near the `deviceLocalSshProfileRepository` call, or a small new `client/lib/services/catalog/catalog_cache_layout.dart` if app_shell exceeds size limits):

```dart
// Catalog caches are device-local: on Android the home root is remote (SFTP),
// so a cache under it costs a network round trip per read — defeating itself.
String deviceLocalCatalogCacheDir(String nativeAppDataPath) =>
    p.Context(style: Platform.isWindows ? p.Style.windows : p.Style.posix)
        .join(nativeAppDataPath, 'catalog-cache');
```

- [ ] **Step 2: Thread overrides at construction**

```dart
final memberHubCache = p.join(deviceLocalCatalogCacheDir(nativeAppDataPath), 'member-hub');
final teamHubCache = p.join(deviceLocalCatalogCacheDir(nativeAppDataPath), 'team-hub');
final teamHubSource = CompositeTeamHubSource.withDefaults(
  GitRegistryTeamHubSource(cacheDirOverride: teamHubCache),
);
final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
  registry: GitRegistryExpertHubSource(cacheDirOverride: memberHubCache),
  teamIndex: teamHubSource.fetchTeams,
  localStore: localExpertStore,
);
```

(Adapt exact constructor params to what the sources actually expose; add `cacheDirOverride` to `GitRegistryTeamHubSource` if missing, copying the expert source's `_cacheFile` logic.)

- [ ] **Step 3: Verify + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Also verify `LocalFilesystem` is used for the cache (the sources default to `AppStorage.fs` — for a device-local dir they must use native fs; if the source has no fs override, add `fs: LocalFilesystem()` — local-only cache is the point).

```bash
git add -A && git commit -m "perf(catalog): registry caches device-local, not under remote home"
```

---

### Task 3: Same-target home-switch guard + single-flight profile load

**Files:**
- Modify: `client/lib/services/storage/home_target_controller.dart:32` (guard)
- Modify: `client/lib/cubits/ssh_profile_cubit.dart:75` (single-flight `load`)
- Test: `client/test/cubits/ssh_profile_cubit_test.dart` (create/extend); `client/test/services/storage/home_target_controller_test.dart` (create)

**Interfaces:**
- Produces: `HomeTargetController.select` becomes a no-op when `id == currentId`; `SshProfileCubit.load` coalesces concurrent calls.

- [ ] **Step 1: Failing tests**

```dart
// home_target_controller_test.dart
test('select(currentId) is a no-op — no registry churn, no reload', () async {
  var switches = 0;
  final controller = HomeTargetController(
    registry: fakeRegistry, // implements RuntimeTargetRegistry minimally
    current: () => RuntimeTarget.ssh(profileId: 'p1'), // use real factory
    switchTo: (id) async => switches++,
  );
  await controller.select(controller.currentId);
  expect(switches, 0);
  await controller.select('ssh:p2');
  expect(switches, 1);
});

// ssh_profile_cubit_test.dart
test('concurrent load() runs the repository load once', () async {
  final repo = _SlowFakeRepo(); // loadAll completes after 200ms, counts calls
  final cubit = SshProfileCubit(profileRepository: repo, credentialStore: fakeStore);
  await Future.wait([cubit.load(), cubit.load(), cubit.load()]);
  expect(repo.loadAllCalls, 1);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/storage/home_target_controller_test.dart test/cubits/ssh_profile_cubit_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// home_target_controller.dart
/// Persist + rebind the home target, then reinstall + reload app data.
/// Same-target select is a no-op: Android Connect auto-selects the profile it
/// just connected as home; re-selecting it must not evict the live context.
Future<void> select(String id) {
  if (_current().id == id) return Future.value();
  return _switchTo(id);
}
```

```dart
// ssh_profile_cubit.dart
Future<void>? _loadFuture;
@override
Future<void> load() =>
    _loadFuture ??= _doLoad().whenComplete(() => _loadFuture = null);
Future<void> _doLoad() async { /* existing load() body */ }
```

Note: `bootstrapHomeIndex`, `warmAuxiliaryData`→`prepareInteractiveShell`, and `reconnectHomeSshIfNeeded` all call `sshProfileCubit.load()` concurrently — the single-flight collapses these into one repository read (the log shows it loading 3×: +6.6s inside bootstrapHomeIndex, +2.6s, +6.8s again).

- [ ] **Step 4: Tests pass + full suite + commit**

```bash
git add -A && git commit -m "fix(ssh): same-target home select no-op + single-flight profile load

Kills the redundant second full bootstrap on Android (Connect success
re-selected the current home → evicted live context → killed in-flight
CLI probes → reran the entire boot chain)."
```

---

### Task 4: Remote CLI discovery — background, cached, non-blocking

**Files:**
- Create: `client/lib/services/cli/remote_cli_path_cache.dart`
- Create: `client/test/services/cli/remote_cli_path_cache_test.dart`
- Modify: `client/lib/cubits/ssh_profile_cubit.dart` (`load`/`selectProfile` stop awaiting `_discoverRemoteCliPath`; discovery consults cache)
- Modify: `client/lib/app/app_shell.dart:737` (wire cache into cubit)

**Interfaces:**
- Produces: `class RemoteCliPathCache` — `Future<Map<CliTool, String>> load(String profileId)`, `Future<void> save(String profileId, Map<CliTool, String> paths)`, `void invalidate(String profileId)`; storage at `<nativeAppDataPath>/remote-cli-paths.json` via `LocalFilesystem` (device-local). `SshProfileCubit` gains optional `remoteCliPathCache` constructor param.

- [ ] **Step 1: Failing test for the cache** — round-trip save/load, invalidate, corrupt-JSON resilience (return empty map, never throw). Use constructor-injected `Filesystem` (in-memory fake from existing test helpers — grep `FakeFilesystem`/`MemoryFilesystem` in `client/test/`).

- [ ] **Step 2: Implement cache** — plain JSON map `{profileId: {cliValue: path}}`, atomic write (`fs.atomicWrite`), pure constructor-injected fs.

- [ ] **Step 3: Make discovery non-blocking**

In `SshProfileCubit`: `_discoverRemoteCliPath` becomes fire-and-forget (`unawaited(...)`) from `load`/`selectProfile`; before locating it checks `cache.load(profileId)` — hit ⇒ apply cached paths via `_onRemoteCliLocated` and return; miss ⇒ locate, `cache.save`, apply. Invalidate on `saveProfile` when the connection fingerprint (`sshHomeConnectionFingerprint` from `client/lib/services/storage/home_ssh_profile_impact.dart:17`) changed.

- [ ] **Step 4: Test the non-blocking behavior** — fake locator returns a `Completer`-backed future that never completes; assert `load()` completes and emits `isLoading: false`.

- [ ] **Step 5: Full suite + commit**

```bash
git add -A && git commit -m "perf(cli): remote CLI path discovery non-blocking with device-local cache

load() no longer awaits 7-shell-per-CLI probe loops (sshProfiles was
+2.6s and blocked prepareInteractiveShell); cached paths apply
instantly, refresh happens in background."
```

---

### Task 5: Drain-safe SSH transport eviction

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart` (in-flight tracking + delayed close)
- Modify: `client/lib/services/storage/remote_file_store.dart` (route ops through the tracker)
- Test: `client/test/services/ssh/ssh_client_factory_test.dart` (extend)

**Interfaces:**
- Produces: `SshClientFactory.disconnectProfile` never closes a transport with in-flight storage ops: it removes the profile from the pool immediately (new callers dial fresh) and closes the old client once in-flight ops drain (or after a 5s timeout). Internal: `<T> Future<T> _tracked(String profileId, Future<T> Function() op)`.

- [ ] **Step 1: Failing test**

```dart
test('disconnectProfile waits for in-flight storage op before closing',
    () async {
  final factory = buildFactoryWithFakeConnector(); // existing test pattern
  final release = Completer<void>();
  final op = factory.runOnStorage(profile, 'sleep 1'); // fake connector delays
  unawaited(factory.disconnectProfile(profile.id));
  await Future.delayed(Duration(milliseconds: 50));
  expect(factory.hasLiveStorageClient(profile.id), isFalse); // evicted now…
  // …but the op must still complete instead of SSHStateError.
  await expectLater(op, completes);
  await release.future; // cleanup
});
```

(Adapt to the existing fake-connector test scaffolding in `ssh_client_factory_test.dart`; if `runOnStorage` isn't directly testable, test via `clientForStorage` + a tracked SFTP op.)

- [ ] **Step 2: Implement in-flight tracking**

In `SshClientFactory`:

```dart
final Map<String, int> _inFlight = {};

Future<T> _tracked<T>(String profileId, Future<T> Function() op) async {
  final n = (_inFlight[profileId] ?? 0) + 1;
  _inFlight[profileId] = n;
  try {
    return await op();
  } finally {
    final left = (_inFlight[profileId] ?? 1) - 1;
    if (left <= 0) {
      _inFlight.remove(profileId);
    } else {
      _inFlight[profileId] = left;
    }
  }
}
```

Wrap every public op that runs work on the pooled storage client: `runOnStorage`, the SFTP-wrapper paths used by `RemoteFileStore` (locate them in `remote_file_store.dart` — every `_clientFactory.*` call that carries user data), and `clientForStorage`'s keepalive probe excluded (it's a health check, not user data). Simplest correct seam: have `RemoteFileStore` wrap each method body in `_clientFactory._tracked`-equivalent — expose a public `Future<T> runTrackedOnStorage(...)` on the factory if direct wrapping is awkward.

- [ ] **Step 3: Delayed close in `_evictProfile`**

```dart
void _evictProfile(String profileId, {required bool closePooled, SshTransportCloseReason? reason}) {
  _sftpByProfile.remove(profileId);
  final cached = _pool.remove(profileId);
  final wasLive = cached != null && cached.readyCompleted;
  if (closePooled && cached != null && !cached.client.isClosed) {
    final lifecycle = _clientLifecycle[cached.client];
    if (lifecycle != null && reason != null) {
      lifecycle.pendingLocalCloseReason = reason;
    }
    final inflight = _inFlight[profileId] ?? 0;
    if (inflight > 0) {
      appLogger.i('[ssh] deferring close of $profileId: $inflight in-flight op(s)');
      unawaited(_closeWhenDrained(profileId, cached.client, const Duration(seconds: 5)));
    } else {
      unawaited(cached.client.disconnect());
    }
  }
  if (wasLive) _notifyPoolChange(profileId);
}

Future<void> _closeWhenDrained(String profileId, SSHClient client, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while ((_inFlight[profileId] ?? 0) > 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!client.isClosed) await client.disconnect();
}
```

- [ ] **Step 4: Tests pass + full suite + commit**

```bash
git add -A && git commit -m "fix(ssh): drain-safe storage transport eviction

Home-context evictions no longer abort in-flight SFTP/exec ops with
SSHStateError; the pooled client is removed from the pool immediately
(new callers dial fresh) but closes only after ops drain (5s cap)."
```

---

### Task 6: `HomeStorage` — injected, versioned, drain-safe facade; AppStorage deleted

**Files:**
- Create: `client/lib/services/storage/home_storage.dart`
- Create: `client/test/services/storage/home_storage_test.dart`
- Modify: all 117 files currently referencing `AppStorage` (`grep -rl "AppStorage\." client/lib --include=*.dart`), pattern below
- Modify: `client/lib/app/app_shell.dart` (construction + `setHomeTarget`/`reinstallStorageContext` route through `homeStorage.swap`)
- Modify: `client/test/support/post_frame_test_harness.dart` (`setUpTestAppStorage`)

**Interfaces:**
- Produces:

```dart
class HomeStorage {
  HomeStorage(RuntimeContext context) : _current = context;
  RuntimeContext get context;      // current published context (immutable value)
  Filesystem get fs;                // context.filesystem
  AppPaths get paths;               // context.paths
  String get home, cwd, appDataRoot; bool get usesPosixPaths;
  int get generation;               // increments per swap
  Stream<StoragePlaneChange> get changes; // broadcast: {oldContext, newContext, generation}
  Future<void> swap(RuntimeContext next, {Duration drainTimeout = const Duration(seconds: 5)});
}
```

`swap` publishes the new context **synchronously** (new operations see it immediately), emits `changes`, then awaits drain of the old transport (Task 5 machinery: old context's profile evicted with deferred close). Migration is staged in three sub-commits so the app stays green:

- [ ] **Step 1: Failing HomeStorage test** — swap publishes immediately (`fs` getter returns new context's fs before drain completes), generation increments, `changes` fires once with old+new, swap with identical context is a no-op (no emit).

- [ ] **Step 2: Implement HomeStorage** (code shape as above; drain = call the registry/ssh factory eviction with the Task 5 deferred close — accept a `Future<void> Function(RuntimeContext old)` retire callback injected from app_shell so the class stays pure/testable).

- [ ] **Step 3: Bootstrap wiring (sub-commit A)** — `final homeStorage = HomeStorage(runtimeContextRegistry.home());` right after `AppStorage.bindHome(homeCtx)` is today; every repository constructed in `buildAppShell` gains `storage: homeStorage`; `setHomeTarget`/`reinstallStorageContext` call `await homeStorage.swap(freshContext)` instead of manual dispose/rebind/bind. `AppStorage` temporarily becomes a forwarder to a mutable `HomeStorage.current` so unmigrated call sites keep working during the sweep:

```dart
// temporary migration shim — deleted in sub-commit C
static HomeStorage? _current;
static void bindHomeStorage(HomeStorage storage) => _current = storage;
static RuntimeContext get context => _current!.context;
```

- [ ] **Step 4: Sweep (sub-commit B)** — for every file in the grep list, apply the pattern:

```dart
// BEFORE
class WorkspaceFavoritesStore {
  final Filesystem? _fsOverride;
  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
// AFTER
class WorkspaceFavoritesStore {
  WorkspaceFavoritesStore({required HomeStorage storage, Filesystem? fs})
    : _fs = fs ?? storage.fs;
  final Filesystem? fs; // test override stays
  late final Filesystem _fs;
```

Representative files (do `repositories/` first, then `services/`, then `cubits/` — the grep list is the source of truth): `client/lib/repositories/launch_profile_repository.dart`, `session_repository.dart`, `plugin_repository.dart`, `services/storage/runtime_layout.dart`, `services/expert_hub/local_expert_store.dart` (note: `LocalExpertStore` must keep taking plain `Filesystem` — it is also used from device-local scopes; inject `homeStorage.fs` at its construction site in app_shell), `services/home_workspace/*_store.dart`. Every migrated class gains a required `HomeStorage storage` (or `Filesystem fs` where the class is context-agnostic) constructor param. No defaults to globals anywhere. Watch for eager field initializers capturing paths at construction (`final x = AppStorage.paths.y;` → `late final x = storage.paths.y;` — home may swap).

- [ ] **Step 5: Test harness (sub-commit C)** — rewrite `setUpTestAppStorage()` in `client/test/support/post_frame_test_harness.dart` to construct `HomeStorage.forTesting(fs, root)` (a `@visibleForTesting` factory building a native `RuntimeContext`) and return it so tests pass it into constructors; sweep `client/test/` updating constructors (same mechanical pattern). Delete `client/lib/services/storage/app_storage.dart` and the shim. `AppPaths`/`AppPathsBootstrapper` stay (pure path math, no runtime binding).

- [ ] **Step 6: Full suite + analyze + commit (three commits: A wiring, B sweep, C delete)**

```bash
git add -A && git commit -m "refactor(storage): HomeStorage injected facade replaces AppStorage global

Versioned, drain-safe, constructor-injected control-plane storage; home
switch publishes synchronously and retires the old transport only after
in-flight ops drain."
```

---

### Task 7: Level-based invalidation service (out of the widget tree)

**Files:**
- Create: `client/lib/services/storage/home_invalidation_service.dart`
- Create: `client/test/services/storage/home_invalidation_service_test.dart`
- Modify: `client/lib/app/app_shell.dart:2486` (construct/subscribe at bootstrap; `reloadAllAppData` gains a level param)
- Modify: `client/lib/main.dart` + router — remove `HomeSshProfileBinder` from the widget tree
- Delete: `client/lib/widgets/ssh/home_ssh_profile_binder.dart`
- Keep: `home_storage_invalidator.dart`, `home_ssh_profile_impact.dart` (policy stays; the service wraps them)

**Interfaces:**
- Consumes: `HomeSshProfileImpact` (`home_ssh_profile_impact.dart:21`), `HomeStorage.changes` (Task 6).
- Produces: `class HomeInvalidationService { void start(); void stop(); }` subscribing to `SshProfileCubit` via an injected `Stream<SshProfileState>` (cubit state stream — no widget, no context.read) and to `HomeStorage.changes`; `enum ReloadLevel { none, indexOnly, full }`; `reloadAllAppData({bool reinstallSshHome, ReloadLevel level})`.

- [ ] **Step 1: Failing test** — feed profile-state diffs into the service: unrelated profile churn ⇒ `ReloadLevel.none` (no reload call); `homeConnectionChanged` ⇒ `full`; home-swap change event ⇒ `full`; a same-context re-emit ⇒ `none`. Use fake callback recorders.

- [ ] **Step 2: Implement** — the service drains/coalesces bursts (reuse the pending/`_applying` pattern from `home_ssh_profile_binder.dart:41-67`, minus the widget `mounted` checks — a service never silently drops a pending invalidation), resolves `HomeSshProfileImpact`, and invokes an injected `Future<void> Function(ReloadLevel)` that app_shell binds to `reloadAllAppData`.

- [ ] **Step 3: app_shell changes** — construct after `sshProfileCubit` + `homeStorage` exist; `service.start()` before `bootstrapAppData` runs; delete the `HomeSshProfileBinder` usage (grep `HomeSshProfileBinder` in `client/lib/`, `client/lib/main.dart`, router). `reloadAllAppData` level plumbing: `indexOnly` runs `bootstrapHomeIndex` only (skip `warmAuxiliaryData` — cubits are single-flight/idempotent and already loaded); `full` keeps current behavior.

- [ ] **Step 4: Full suite + commit**

```bash
git add -A && git commit -m "refactor(storage): invalidation moved from widget binder to bootstrap-owned service

Storage-plane lifecycle no longer hangs off widget-tree mount state
(pending invalidations could be silently dropped by !mounted); reloads
are level-based instead of always-full."
```

---

### Task 8: End-to-end verification + boot timeline

- [ ] **Step 1: Static gates** — `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`. Expected: zero warnings/errors, all tests pass.

- [ ] **Step 2: Desktop SSH-home smoke** — run the app with an SSH home target (`flutter run -d linux` with home set to an SSH profile; if desktop SSH-home isn't reachable in this environment, verify on the Android device per DEVELOPMENT.md). Drive: cold start → home list renders → open the 748-session workspace (d938aa90) → open a session.

- [ ] **Step 3: Log assertions** — capture `adb logcat | grep '\[boot\]'` (or run console) and assert:
  - exactly **one** `bootstrapHomeIndex start` per cold start;
  - zero `runtimeContextEvicted` lines before `bootstrapAppData complete`;
  - zero `Remote CLI lookup failed ... SSH client closed` lines;
  - `LaunchProfileCubit load done` under **2s** (was 35.3s);
  - `bootstrap complete` under **10s** on Wi-Fi (was 58s+).

- [ ] **Step 4: Second-boot check** — relaunch (caches warm): registry catalogs and CLI paths come from device-local cache; `bootstrapHomeIndex` must not re-fetch over SFTP beyond the one index snapshot.

- [ ] **Step 5: Final commit + PR**

```bash
git add -A && git commit -m "perf(boot): mobile SSH-home cold start 58s -> <10s"
```

PR body summarizing: root causes, per-task changes, measured before/after timeline.

---

## Self-review notes

- Task 1 collapses the 35s (analysis root cause 1); Tasks 2–4 the auxiliary stalls; Task 3 kills the second bootstrap (root cause 2); Task 5 fixes the in-flight kill (root cause 2's error spam); Tasks 6–7 are the structural fix (architecture problems 1–2–4 from the analysis); Task 8 verifies. Hub cache-contract (analysis problem 3) is solved structurally by `ExpertHubCatalog` being *the* cache contract — resolution paths that bypass it are deleted in Task 1 Step 6.
- Ordered so each task ships independently and the app stays green after every commit; biggest win first.
- Risk notes for executors: Task 5's tracker must wrap **all** data-carrying paths through the pooled client (verify by grepping `_clientFactory.` in `remote_file_store.dart`); Task 6 Step 4's sweep must not convert eager path capture into stale values (`late final` from injected storage, not field initializers).
