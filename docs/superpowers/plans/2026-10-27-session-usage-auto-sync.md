# Session Usage Auto Sync and Sync Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `Token 用量` page sync itself while it is visible, and make scans cancellable, observable, time-bounded, and concurrency-bounded without changing extraction or storage semantics.

**Architecture:** Add a sync control token, progress snapshot, and handle to the usage service. The service scans targets with a bounded worker pool, applies a per-source timeout, and checks cancellation between steps. The cubit consumes the handle stream, exposes progress/cancel state, and keeps single-flight semantics. The page triggers stale checks on open, on app resume, and every 10 minutes while mounted.

**Tech Stack:** Flutter, `flutter_bloc`, `equatable`, `synchronized`, existing `Filesystem` usage store/cursor store, `dart run tool/run_tests.dart`.

## Global Constraints

- Work in `/home/hhoa/git/hhoa/teampilot` on `main`.
- Never run `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths>`.
- Do not use `git add -A` or `git commit -a`.
- Do not touch pre-existing uncommitted user changes. At the time of writing these include chat/history files, work-path files, `client/packages/shared_ui`, `client/third_party/fastforge`, `.idea/`, `docs/workspace-storage-layout.md`, and:
  - `client/lib/pages/usage/widgets/usage_summary_cards.dart`
  - `client/test/pages/usage/usage_summary_cards_test.dart`
- Do not change the extraction capabilities, JSONL event schema, pricing, or UI layout in this plan.
- Auto sync only while the usage page is mounted and the app is active. No OS background task.
- Source timeout default: 30 seconds. Target concurrency default: 4. Stale threshold: 5 minutes. Visible interval: 10 minutes.
- Cursor advances only after `UsageStore.upsert` succeeds.
- Existing `SessionUsageSyncService.syncAll()` and `SessionUsageCubit.sync()` call sites must keep working.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `client/lib/services/usage/usage_sync_control.dart` | Create | Cancel token, progress model, cancellation exception |
| `client/lib/services/usage/session_usage_sync_service.dart` | Modify | Bounded scan, timeout, cancellation, progress, handle |
| `client/lib/app/session_usage_services.dart` | Modify | `startSync()` factory for the current home plane |
| `client/lib/app/app_shell.dart` | Modify | Pass `startSync` into the cubit |
| `client/lib/cubits/session_usage_cubit.dart` | Modify | Progress/cancel state, `syncIfStale`, handle consumption |
| `client/lib/pages/usage/session_usage_page.dart` | Modify | Auto sync on open/resume/timer, cancel toast |
| `client/lib/pages/usage/widgets/usage_page_chrome.dart` | Modify | Progress line and cancel button |
| `client/lib/utils/ui/app_keys.dart` | Modify | Cancel/progress keys |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Modify | New strings; update footer label |
| `client/lib/l10n/app_localizations*.dart` | Regenerate | Generated l10n |
| `client/test/services/usage/session_usage_sync_service_test.dart` | Modify | Progress, timeout, cancel, concurrency, cursor safety |
| `client/test/cubits/session_usage_cubit_test.dart` | Modify | `syncIfStale`, progress, cancel, manual flag |
| `client/test/pages/usage/session_usage_page_test.dart` | Modify | Auto sync, progress, cancel, existing tests disabled auto |

---

## Task 1: Sync control, progress, cancel, timeout, and concurrency

**Files:**
- Create: `client/lib/services/usage/usage_sync_control.dart`
- Modify: `client/lib/services/usage/session_usage_sync_service.dart`
- Test: `client/test/services/usage/session_usage_sync_service_test.dart`

**Interfaces:**
- Produces: `UsageSyncControl`, `UsageSyncCancelled`, `UsageSyncProgress`
- Produces: `UsageSyncHandle`, `SessionUsageSyncService.syncAll({control, onProgress})`
- Produces: `SessionUsageSyncService.sourceTimeout`, `maxConcurrentTargets`
- Extends: `UsageSyncResult.cancelled`

- [ ] **Step 1: Write the failing service tests**

Add these tests to `client/test/services/usage/session_usage_sync_service_test.dart`. Keep the existing tests.

```dart
  test('reports progress from start to completion', () async {
    final progress = <UsageSyncProgress>[];
    final capability = _FakeCapability(sources: [_source('a'), _source('b')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));

    final result = await SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: _FakeStore(),
      cursors: _FakeCursors(),
      registry: registry,
    ).syncAll(onProgress: progress.add);

    expect(result.inserted, 2);
    expect(progress.first.targetsTotal, 0);
    expect(progress.any((p) => p.targetsTotal == 1), isTrue);
    expect(progress.last.targetsDone, 1);
    expect(progress.last.sourcesDone, 2);
    expect(progress.last.inserted, 2);
    expect(progress.last.isCancelled, isFalse);
  });

  test('cancels before discovery starts', () async {
    final capability = _FakeCapability(sources: [_source('a')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final control = UsageSyncControl()..cancel();

    final result = await SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: _FakeStore(),
      cursors: _FakeCursors(),
      registry: registry,
    ).syncAll(control: control);

    expect(result.cancelled, isTrue);
    expect(capability.scans, 0);
  });

  test('records a source timeout and continues', () async {
    final capability = _DelayedCapability(
      sources: [_source('slow'), _source('fast')],
      slowSource: 'slow',
      delay: const Duration(milliseconds: 50),
    );
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final cursors = _FakeCursors();
    final store = _FakeStore();

    final result = await SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: store,
      cursors: cursors,
      registry: registry,
      sourceTimeout: const Duration(milliseconds: 5),
    ).syncAll();

    expect(result.errors, hasLength(1));
    expect(result.errors.single.sourceId, 'slow');
    expect(result.errors.single.message, contains('timed out'));
    expect(store.events, hasLength(1));
    expect(cursors.saved.keys, contains('fast'));
    expect(cursors.saved.keys, isNot(contains('slow')));
  });

  test('honours the target concurrency cap', () async {
    final capability = _PerContextCapability();
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final contexts = [
      for (var i = 0; i < 4; i++) _ctx(sessionId: 's$i'),
    ];

    await SessionUsageSyncService(
      targets: _FakeTargets(contexts),
      store: _FakeStore(),
      cursors: _FakeCursors(),
      registry: registry,
      maxConcurrentTargets: 2,
    ).syncAll();

    expect(capability.maxActive, 2);
  });

  test('does not advance the cursor when the store fails', () async {
    final capability = _FakeCapability(sources: [_source('a')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final cursors = _FakeCursors();

    final result = await SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: _ThrowingStore(),
      cursors: cursors,
      registry: registry,
    ).syncAll();

    expect(result.errors, hasLength(1));
    expect(cursors.saved, isEmpty);
  });
```

Add the test fakes below the existing fakes. Modify `_ctx` and `_FakeCapability` only as needed.

```dart
final class _DelayedCapability implements SessionUsageCapability {
  _DelayedCapability({
    required this.sources,
    required this.slowSource,
    required this.delay,
  });

  final List<SessionUsageSource> sources;
  final String slowSource;
  final Duration delay;

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async => sources;

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    if (source.id == slowSource) await Future<void>.delayed(delay);
    return UsageScanResult(
      events: [_event(source.id)],
      nextCursor: const UsageCursor(byteOffset: 7),
    );
  }
}

final class _PerContextCapability implements SessionUsageCapability {
  int active = 0;
  int maxActive = 0;

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async {
    return [
      SessionUsageSource(
        id: 'source-${ctx.sessionId}',
        path: '/tp/${ctx.sessionId}.jsonl',
        kind: UsageSourceKind.jsonl,
        sessionId: ctx.sessionId,
        memberId: '',
        teamId: '',
      ),
    ];
  }

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    active--;
    return UsageScanResult(
      events: [_event(source.id)],
      nextCursor: const UsageCursor(byteOffset: 7),
    );
  }
}

final class _ThrowingStore implements UsageStore {
  @override
  Future<UsageAppendResult> upsert(
    Iterable<SessionUsageEvent> events,
  ) async => throw StateError('write failed');

  @override
  Future<List<SessionUsageEvent>> readLatest() async => const [];
}
```

Update `_ctx` to accept a session id:

```dart
UsageScanContext _ctx({String sessionId = 's1'}) => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.claude,
  env: const {},
  transcriptRoots: const [],
  taskId: 'task',
  nativeSessionId: 'native',
  sessionId: sessionId,
  memberId: '',
  teamId: '',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart test/services/usage/session_usage_sync_service_test.dart
```

Expected: compilation fails because `UsageSyncControl`, `UsageSyncProgress`, `cancelled`, `sourceTimeout`, and `maxConcurrentTargets` do not exist.

- [ ] **Step 3: Create the control and progress types**

Create `client/lib/services/usage/usage_sync_control.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

final class UsageSyncControl {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const UsageSyncCancelled();
  }
}

final class UsageSyncCancelled implements Exception {
  const UsageSyncCancelled();

  @override
  String toString() => 'Usage sync cancelled';
}

@immutable
final class UsageSyncProgress extends Equatable {
  const UsageSyncProgress({
    this.targetsTotal = 0,
    this.targetsDone = 0,
    this.sourcesDone = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
    this.currentSourceId,
    this.isCancelled = false,
  });

  final int targetsTotal;
  final int targetsDone;
  final int sourcesDone;
  final int inserted;
  final int updated;
  final int skipped;
  final int errors;
  final String? currentSourceId;
  final bool isCancelled;

  @override
  List<Object?> get props => [
    targetsTotal,
    targetsDone,
    sourcesDone,
    inserted,
    updated,
    skipped,
    errors,
    currentSourceId,
    isCancelled,
  ];
}
```

- [ ] **Step 4: Rewrite the sync service**

Replace `client/lib/services/usage/session_usage_sync_service.dart` with the implementation below. It preserves the existing `UsageSyncError`/`UsageSyncResult` shape, adds `cancelled`, and adds the handle.

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../cli/registry/capabilities/session_usage_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'usage_cursor_store.dart';
import 'usage_scan_target_provider.dart';
import 'usage_store.dart';
import 'usage_sync_control.dart';

@immutable
class UsageSyncError {
  const UsageSyncError({required this.sourceId, required this.message});

  final String sourceId;
  final String message;
}

@immutable
class UsageSyncResult {
  const UsageSyncResult({
    this.targetsScanned = 0,
    this.sourcesScanned = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
    this.cancelled = false,
  });

  final int targetsScanned;
  final int sourcesScanned;
  final int inserted;
  final int updated;
  final int skipped;
  final List<UsageSyncError> errors;
  final bool cancelled;
}

final class UsageSyncHandle {
  UsageSyncHandle({
    required this.done,
    required this.progress,
    required void Function() cancel,
  }) : _cancel = cancel;

  final Future<UsageSyncResult> done;
  final Stream<UsageSyncProgress> progress;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// One-shot scanner with optional progress, cancellation, timeout, and
/// bounded target concurrency.
class SessionUsageSyncService {
  SessionUsageSyncService({
    required UsageScanTargetProvider targets,
    required UsageStore store,
    required UsageCursorStore cursors,
    required CliToolRegistry registry,
    this.sourceTimeout = const Duration(seconds: 30),
    this.maxConcurrentTargets = 4,
  }) : _targets = targets,
       _store = store,
       _cursors = cursors,
       _registry = registry;

  final UsageScanTargetProvider _targets;
  final UsageStore _store;
  final UsageCursorStore _cursors;
  final CliToolRegistry _registry;
  final Duration sourceTimeout;
  final int maxConcurrentTargets;

  /// Process-wide: a plane swap can briefly keep an old service alive.
  static final Lock _syncLock = Lock();

  Future<UsageSyncResult> syncAll({
    UsageSyncControl? control,
    void Function(UsageSyncProgress)? onProgress,
  }) {
    final token = control ?? UsageSyncControl();
    return _syncLock.synchronized(
      () => _syncAll(control: token, onProgress: onProgress),
    );
  }

  Future<UsageSyncResult> _syncAll({
    required UsageSyncControl control,
    void Function(UsageSyncProgress)? onProgress,
  }) async {
    final errors = <UsageSyncError>[];
    final seenSources = <String>{};
    var targetsTotal = 0;
    var targetsDone = 0;
    var sourcesDone = 0;
    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    void report({String? currentSourceId}) {
      onProgress?.call(
        UsageSyncProgress(
          targetsTotal: targetsTotal,
          targetsDone: targetsDone,
          sourcesDone: sourcesDone,
          inserted: inserted,
          updated: updated,
          skipped: skipped,
          errors: errors.length,
          currentSourceId: currentSourceId,
          isCancelled: control.isCancelled,
        ),
      );
    }

    report();

    late final List<UsageScanContext> targets;
    try {
      control.throwIfCancelled();
      targets = await _targets.targets();
    } on UsageSyncCancelled {
      return const UsageSyncResult(cancelled: true);
    } on Object catch (error) {
      return UsageSyncResult(
        errors: [UsageSyncError(sourceId: '*', message: '$error')],
      );
    }

    targetsTotal = targets.length;
    report();

    final workerCount = math.min(
      math.max(1, maxConcurrentTargets),
      math.max(1, targets.length),
    );
    var nextTarget = 0;

    Future<void> worker() async {
      while (true) {
        if (control.isCancelled) return;
        final index = nextTarget++;
        if (index >= targets.length) return;
        final ctx = targets[index];
        try {
          control.throwIfCancelled();
          final capability = _registry
              .capability<SessionUsageCapability>(ctx.cli);
          if (capability == null) continue;

          late final List<SessionUsageSource> sources;
          try {
            sources = await capability.discoverUsageSources(ctx);
          } on Object catch (error) {
            errors.add(
              UsageSyncError(
                sourceId: '${ctx.sessionId}/${ctx.memberId}',
                message: '$error',
              ),
            );
            continue;
          }

          for (final source in sources) {
            if (control.isCancelled) return;
            if (!seenSources.add(source.id)) continue;
            sourcesDone++;
            try {
              final cursor = await _cursors
                  .read(source.id)
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              final scan = await capability
                  .scanUsageSource(
                    ctx: ctx,
                    source: source,
                    cursor: cursor,
                  )
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              final appended = await _store
                  .upsert(scan.events)
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              await _cursors
                  .save(source.id, scan.nextCursor)
                  .timeout(sourceTimeout);
              inserted += appended.inserted;
              updated += appended.updated;
              skipped += appended.skipped;
            } on UsageSyncCancelled {
              report(currentSourceId: source.id);
              return;
            } on TimeoutException {
              errors.add(
                UsageSyncError(
                  sourceId: source.id,
                  message:
                      'timed out after ${sourceTimeout.inMilliseconds}ms',
                ),
              );
            } on Object catch (error) {
              errors.add(
                UsageSyncError(sourceId: source.id, message: '$error'),
              );
            }
            report(currentSourceId: source.id);
          }
        } on UsageSyncCancelled {
          return;
        } finally {
          targetsDone++;
          report();
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
    report();

    return UsageSyncResult(
      targetsScanned: targetsDone,
      sourcesScanned: sourcesDone,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: List.unmodifiable(errors),
      cancelled: control.isCancelled,
    );
  }
}
```

- [ ] **Step 5: Run the service tests**

```bash
cd client
dart run tool/run_tests.dart test/services/usage/session_usage_sync_service_test.dart
```

Expected: all tests pass. If the concurrency test is flaky due to the 20 ms delay, keep the delay but assert `maxActive <= 2` and `maxActive >= 2`, not an exact second count.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/services/usage/usage_sync_control.dart \
  client/lib/services/usage/session_usage_sync_service.dart \
  client/test/services/usage/session_usage_sync_service_test.dart
git commit -m "feat(usage): add cancellable bounded sync" -- \
  client/lib/services/usage/usage_sync_control.dart \
  client/lib/services/usage/session_usage_sync_service.dart \
  client/test/services/usage/session_usage_sync_service_test.dart
```

---

## Task 2: Expose a sync handle from app services and wire the shell

**Files:**
- Modify: `client/lib/app/session_usage_services.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/usage/session_usage_services_test.dart` (create)

**Interfaces:**
- Consumes: `SessionUsageSyncService`, `UsageSyncHandle`, `UsageSyncControl`, `UsageSyncProgress`
- Produces: `SessionUsageServices.startSync`

- [ ] **Step 1: Write the failing service factory test**

Create `client/test/services/usage/session_usage_services_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/session_usage_services.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpTestAppStorage();
  tearDownTestAppStorage();

  test('startSync returns a handle for the current home plane', () async {
    final services = SessionUsageServices.forStorage(
      storage: testHomeStorage,
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
    );

    final handle = services.startSync();
    final result = await handle.done;

    expect(result.targetsScanned, 0);
    expect(result.cancelled, isFalse);
  });
}
```

If `testHomeStorage` is not exported by `post_frame_test_harness.dart`, use the existing `setUpTestAppStorage()` helper pattern from `client/test/pages/usage/session_usage_page_test.dart` and the shared `testHomeStorage` symbol. Check the harness imports before running; do not introduce a second home storage.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client
dart run tool/run_tests.dart test/services/usage/session_usage_services_test.dart
```

Expected: compile error, `startSync` is not defined.

- [ ] **Step 3: Add `startSync` to `SessionUsageServices`**

Modify `client/lib/app/session_usage_services.dart`:

```dart
import 'dart:async';

import '../models/app_session.dart';
import '../models/session_usage.dart';
import '../models/team_config.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/storage/home_storage.dart';
import '../services/usage/json_usage_cursor_store.dart';
import '../services/usage/json_usage_store.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/team_pilot_usage_scan_target_provider.dart';
import '../services/usage/usage_sync_control.dart';

final class SessionUsageServices {
  SessionUsageServices._({
    required this.syncAll,
    required this.startSync,
    required this.loadEvents,
    required this.loadSessions,
    required this.loadTeams,
  });

  final Future<UsageSyncResult> Function() syncAll;
  final UsageSyncHandle Function() startSync;
  final Future<List<SessionUsageEvent>> Function() loadEvents;
  final Future<List<AppSession>> Function() loadSessions;
  final Future<List<TeamProfile>> Function() loadTeams;

  factory SessionUsageServices.forStorage({
    required HomeStorage storage,
    CliToolRegistry? registry,
    SessionRepository? sessions,
    LaunchProfileRepository? teams,
    Future<List<AppSession>> Function()? loadSessions,
    Future<List<TeamProfile>> Function()? loadTeams,
  }) {
    final registryForPlane = registry ?? CliToolRegistry.builtIn();

    Future<List<AppSession>> defaultLoadSessions() =>
        (sessions ?? SessionRepository(storage: storage)).loadSessions();
    Future<List<TeamProfile>> defaultLoadTeams() =>
        (teams ?? LaunchProfileRepository(storage: storage)).loadTeamProfiles();
    final loadSessionsFn = loadSessions ?? defaultLoadSessions;
    final loadTeamsFn = loadTeams ?? defaultLoadTeams;

    JsonUsageStore newStore() =>
        JsonUsageStore(fs: storage.fs, filePath: storage.paths.usageEventsFile);

    SessionUsageSyncService newSync() => SessionUsageSyncService(
      targets: TeamPilotUsageScanTargetProvider(
        storage: storage,
        loadSessions: loadSessionsFn,
        loadTeams: loadTeamsFn,
      ),
      store: newStore(),
      cursors: JsonUsageCursorStore(
        fs: storage.fs,
        filePath: storage.paths.usageCursorsFile,
      ),
      registry: registryForPlane,
    );

    UsageSyncHandle startSync() {
      final control = UsageSyncControl();
      final progress = StreamController<UsageSyncProgress>(sync: true);
      final service = newSync();
      final done = Future.microtask(
        () => service.syncAll(control: control, onProgress: progress.add),
      ).whenComplete(progress.close);
      return UsageSyncHandle(
        done: done,
        progress: progress.stream,
        cancel: control.cancel,
      );
    }

    return SessionUsageServices._(
      syncAll: () => newSync().syncAll(),
      startSync: startSync,
      loadEvents: () => newStore().readLatest(),
      loadSessions: loadSessionsFn,
      loadTeams: loadTeamsFn,
    );
  }
}
```

- [ ] **Step 4: Pass `startSync` into the app cubit**

In `client/lib/app/app_shell.dart`, find the `SessionUsageCubit` construction and add the field:

```dart
    final sessionUsageCubit = SessionUsageCubit(
      loadEvents: sessionUsageServices.loadEvents,
      syncAll: sessionUsageServices.syncAll,
      startSync: sessionUsageServices.startSync,
      loadSessions: sessionUsageServices.loadSessions,
      loadTeams: sessionUsageServices.loadTeams,
      storageChanges: homeStorage.changes.map<void>((_) {}),
    );
```

Keep the existing `unawaited(sessionUsageCubit.ensureLoaded());`.

- [ ] **Step 5: Run the factory test and analyzer**

```bash
cd client
dart run tool/run_tests.dart test/services/usage/session_usage_services_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: the test passes and analyzer has no new usage errors.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/app/session_usage_services.dart \
  client/lib/app/app_shell.dart \
  client/test/services/usage/session_usage_services_test.dart
git commit -m "feat(usage): expose startSync handle" -- \
  client/lib/app/session_usage_services.dart \
  client/lib/app/app_shell.dart \
  client/test/services/usage/session_usage_services_test.dart
```

---

## Task 3: Cubit progress, cancel, and stale sync policy

**Files:**
- Modify: `client/lib/cubits/session_usage_cubit.dart`
- Test: `client/test/cubits/session_usage_cubit_test.dart`

**Interfaces:**
- Consumes: `UsageSyncHandle`, `UsageSyncProgress`
- Produces: `SessionUsageState.syncProgress`, `isCancelling`, `syncCancelled`, `lastSyncManual`
- Produces: `SessionUsageCubit.sync({manual})`, `cancelSync()`, `syncIfStale({ttl})`

- [ ] **Step 1: Write the failing cubit tests**

Add these tests to `client/test/cubits/session_usage_cubit_test.dart`. Add the `usage_sync_control.dart` import.

```dart
  test('syncIfStale only scans when never synced or stale', () async {
    var now = DateTime(2026, 10, 26, 18);
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    await cubit.syncIfStale();
    expect(syncCount, 1);

    await cubit.syncIfStale();
    expect(syncCount, 1);

    now = now.add(const Duration(minutes: 6));
    await cubit.syncIfStale();
    expect(syncCount, 2);
  });

  test('syncIfStale reuses an in-flight sync', () async {
    final syncCompleter = Completer<UsageSyncResult>();
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => const <SessionUsageEvent>[],
      syncAll: () {
        syncCount++;
        return syncCompleter.future;
      },
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    final first = cubit.syncIfStale();
    final second = cubit.syncIfStale();
    expect(syncCount, 1);
    syncCompleter.complete(const UsageSyncResult());
    await Future.wait([first, second]);
  });

  test('consumes progress and cancels the active handle', () async {
    final progress = StreamController<UsageSyncProgress>(sync: true);
    final done = Completer<UsageSyncResult>();
    var cancelCalls = 0;
    final handle = UsageSyncHandle(
      done: done.future,
      progress: progress.stream,
      cancel: () => cancelCalls++,
    );
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      startSync: () => handle,
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(() async {
      await progress.close();
      await cubit.close();
    });

    final future = cubit.sync();
    progress.add(
      const UsageSyncProgress(
        targetsTotal: 2,
        targetsDone: 1,
        inserted: 3,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.syncProgress?.targetsDone, 1);

    cubit.cancelSync();
    expect(cubit.state.isCancelling, isTrue);
    expect(cancelCalls, 1);

    done.complete(const UsageSyncResult(cancelled: true));
    await future;

    expect(cubit.state.isSyncing, isFalse);
    expect(cubit.state.isCancelling, isFalse);
    expect(cubit.state.syncCancelled, isTrue);
    expect(cubit.state.lastSyncAtMs, _now.millisecondsSinceEpoch);
    expect(cubit.state.syncProgress, isNull);
  });

  test('tracks whether the completed sync was manual', () async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => _now,
    );
    addTearDown(cubit.close);

    await cubit.sync(manual: false);
    expect(cubit.state.lastSyncManual, isFalse);

    await cubit.sync();
    expect(cubit.state.lastSyncManual, isTrue);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart test/cubits/session_usage_cubit_test.dart
```

Expected: compile errors for `syncIfStale`, `startSync`, `syncProgress`, `cancelSync`, `lastSyncManual`.

- [ ] **Step 3: Add state fields and copyWith**

In `client/lib/cubits/session_usage_cubit.dart`, import:

```dart
import '../services/usage/usage_sync_control.dart';
```

Add fields to `SessionUsageState`:

```dart
    this.syncProgress,
    this.isCancelling = false,
    this.syncCancelled = false,
    this.lastSyncManual = true,
```

Add the final fields:

```dart
  final UsageSyncProgress? syncProgress;
  final bool isCancelling;
  final bool syncCancelled;
  final bool lastSyncManual;
```

Add to `copyWith` parameters:

```dart
    UsageSyncProgress? syncProgress,
    bool clearSyncProgress = false,
    bool? isCancelling,
    bool? syncCancelled,
    bool? lastSyncManual,
```

Add to the returned state:

```dart
      syncProgress: clearSyncProgress
          ? null
          : (syncProgress ?? this.syncProgress),
      isCancelling: isCancelling ?? this.isCancelling,
      syncCancelled: syncCancelled ?? this.syncCancelled,
      lastSyncManual: lastSyncManual ?? this.lastSyncManual,
```

Add the new fields to `props` in declaration order.

- [ ] **Step 4: Add handle support to the cubit**

In the constructor add:

```dart
    UsageSyncHandle Function()? startSync,
```

and initialize:

```dart
       _startSync = startSync,
```

Add fields:

```dart
  final UsageSyncHandle Function()? _startSync;
  UsageSyncHandle? _activeHandle;
  StreamSubscription<UsageSyncProgress>? _syncProgressSub;
  bool _syncManual = true;
```

Replace `sync()` with:

```dart
  Future<void> sync({bool manual = true}) {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    _syncManual = manual;
    final future = _syncInternal();
    _syncFlight = future;
    return future.whenComplete(() {
      if (identical(_syncFlight, future)) _syncFlight = null;
    });
  }

  Future<void> syncIfStale({
    Duration ttl = const Duration(minutes: 5),
  }) {
    final inFlight = _syncFlight;
    if (inFlight != null) return inFlight;

    final last = state.lastSyncAtMs;
    if (last != null &&
        _now().millisecondsSinceEpoch - last < ttl.inMilliseconds) {
      return Future<void>.value();
    }
    return sync(manual: false);
  }

  void cancelSync() {
    final handle = _activeHandle;
    if (handle == null || state.isCancelling) return;
    emit(state.copyWith(isCancelling: true));
    handle.cancel();
  }

  Future<UsageSyncResult> _runSync() async {
    final starter = _startSync;
    if (starter == null) return _syncAll();

    final handle = starter();
    _activeHandle = handle;
    _syncProgressSub = handle.progress.listen((progress) {
      if (isClosed) return;
      emit(state.copyWith(syncProgress: progress));
    });
    try {
      return await handle.done;
    } finally {
      await _syncProgressSub?.cancel();
      _syncProgressSub = null;
      _activeHandle = null;
    }
  }
```

Replace the start of `_syncInternal` with:

```dart
  Future<void> _syncInternal() async {
    if (isClosed) return;
    emit(
      state.copyWith(
        isSyncing: true,
        isCancelling: false,
        syncCancelled: false,
        clearSyncProgress: true,
        syncFailed: false,
        syncErrors: const [],
        clearError: true,
      ),
    );

    try {
      final result = await _runSync();
```

In the success `emit`, add/update:

```dart
          isSyncing: false,
          isCancelling: false,
          clearSyncProgress: true,
          lastSyncAtMs: _now().millisecondsSinceEpoch,
          lastSyncResult: result,
          syncErrors: result.errors,
          syncFailed: false,
          syncCancelled: result.cancelled,
          lastSyncManual: _syncManual,
```

In the fatal catch `emit`, add/update:

```dart
        isSyncing: false,
        isCancelling: false,
        clearSyncProgress: true,
        syncFailed: true,
        syncCancelled: false,
        clearLastSyncResult: true,
```

In `close()`, cancel the active handle and progress subscription before closing:

```dart
  @override
  Future<void> close() async {
    _activeHandle?.cancel();
    _activeHandle = null;
    await _syncProgressSub?.cancel();
    _syncProgressSub = null;
    await _storageSub?.cancel();
    _storageSub = null;
    return super.close();
  }
```

- [ ] **Step 5: Run the cubit tests**

```bash
cd client
dart run tool/run_tests.dart test/cubits/session_usage_cubit_test.dart
```

Expected: all tests pass. If `close()` is called while `done` is pending, ensure the test completes the completer before closing; do not emit after `super.close()`.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/cubits/session_usage_cubit.dart \
  client/test/cubits/session_usage_cubit_test.dart
git commit -m "feat(usage): add sync progress and cancellation state" -- \
  client/lib/cubits/session_usage_cubit.dart \
  client/test/cubits/session_usage_cubit_test.dart
```

---

## Task 4: Page auto sync, progress UI, and cancel affordance

**Files:**
- Modify: `client/lib/pages/usage/session_usage_page.dart`
- Modify: `client/lib/pages/usage/widgets/usage_page_chrome.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart`
- Test: `client/test/pages/usage/session_usage_page_test.dart`

**Interfaces:**
- Consumes: `SessionUsageCubit.syncIfStale`, `cancelSync`, `SessionUsageState.syncProgress`, `isCancelling`, `syncCancelled`, `lastSyncManual`
- Produces: `SessionUsagePage(autoSync:)`, cancel button, progress line

- [ ] **Step 1: Add l10n keys and AppKeys**

In `client/lib/l10n/app_en.arb`, add near the existing `sessionUsageSync` entries:

```json
  "sessionUsageCancelSync": "Cancel",
  "sessionUsageCancelling": "Cancelling…",
  "sessionUsageCancelSyncTooltip": "Cancel usage sync",
  "sessionUsageSyncCancelled": "Usage sync cancelled.",
  "sessionUsageSyncPreparing": "Preparing scan…",
  "sessionUsageSyncProgress": "Scanning {done}/{total} sessions · {inserted} new events",
  "@sessionUsageSyncProgress": {
    "placeholders": {
      "done": { "type": "int" },
      "total": { "type": "int" },
      "inserted": { "type": "int" }
    }
  },
```

Change the existing footer string:

```json
  "sessionUsageFooterManual": "Auto + manual sync",
```

In `client/lib/l10n/app_zh.arb`, add:

```json
  "sessionUsageCancelSync": "取消",
  "sessionUsageCancelling": "正在取消…",
  "sessionUsageCancelSyncTooltip": "取消用量同步",
  "sessionUsageSyncCancelled": "已取消用量同步。",
  "sessionUsageSyncPreparing": "正在准备扫描…",
  "sessionUsageSyncProgress": "正在扫描 {done}/{total} 个会话 · 新增 {inserted} 条",
  "@sessionUsageSyncProgress": {
    "placeholders": {
      "done": { "type": "int" },
      "total": { "type": "int" },
      "inserted": { "type": "int" }
    }
  },
```

Change the footer string:

```json
  "sessionUsageFooterManual": "自动 + 手动同步",
```

In `client/lib/utils/ui/app_keys.dart`, add:

```dart
  static const sessionUsageCancelSyncButton = Key(
    'session-usage-cancel-sync-button',
  );
  static const sessionUsageSyncProgress = Key(
    'session-usage-sync-progress',
  );
```

- [ ] **Step 2: Update the header for progress and cancel**

In `client/lib/pages/usage/widgets/usage_page_chrome.dart`, import the progress type:

```dart
import '../../../services/usage/usage_sync_control.dart';
```

Change the constructor:

```dart
  const UsagePageHeader({
    required this.state,
    required this.onSync,
    required this.onCancel,
    super.key,
  });

  final SessionUsageState state;
  final Future<void> Function() onSync;
  final VoidCallback onCancel;
```

In the header subtitle `Wrap`, after `sessionUsageScopeHint`, add:

```dart
                  if (state.isSyncing)
                    Text(
                      key: AppKeys.sessionUsageSyncProgress,
                      _progressLabel(context, state.syncProgress),
                      style: styles.xs.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
```

Replace the sync button with:

```dart
        Tooltip(
          message: state.isSyncing
              ? l10n.sessionUsageCancelSyncTooltip
              : l10n.sessionUsageSyncTooltip,
          child: FilledButton.icon(
            key: state.isSyncing
                ? AppKeys.sessionUsageCancelSyncButton
                : AppKeys.sessionUsageSyncButton,
            onPressed: state.isSyncing
                ? (state.isCancelling ? null : onCancel)
                : () => onSync(),
            icon: state.isSyncing
                ? (state.isCancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close, size: 18))
                : const Icon(Icons.sync, size: 18),
            label: Text(
              state.isSyncing
                  ? (state.isCancelling
                        ? l10n.sessionUsageCancelling
                        : l10n.sessionUsageCancelSync)
                  : l10n.sessionUsageSync,
            ),
          ),
        ),
```

Add this helper at the bottom of the file:

```dart
String _progressLabel(BuildContext context, UsageSyncProgress? progress) {
  final l10n = context.l10n;
  if (progress == null || progress.targetsTotal == 0) {
    return l10n.sessionUsageSyncPreparing;
  }
  return l10n.sessionUsageSyncProgress(
    progress.targetsDone,
    progress.targetsTotal,
    progress.inserted,
  );
}
```

- [ ] **Step 3: Add page auto sync**

In `client/lib/pages/usage/session_usage_page.dart`, add top-level constants:

```dart
const Duration _autoSyncTtl = Duration(minutes: 5);
const Duration _autoSyncInterval = Duration(minutes: 10);
```

Change the constructor:

```dart
  const SessionUsagePage({
    this.embedded = false,
    this.autoSync = true,
    super.key,
  });

  /// When true, the workspace-home shell already applied pane padding.
  final bool embedded;

  /// Runs stale checks on open, on app resume, and every 10 minutes.
  final bool autoSync;
```

Change the state class:

```dart
class _SessionUsagePageState extends State<SessionUsagePage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  Timer? _autoSyncTimer;
  bool _appActive = true;
```

Replace `initState` with:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;

    if (widget.autoSync) {
      _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
        if (!mounted || !_appActive) return;
        unawaited(
          context.read<SessionUsageCubit>().syncIfStale(ttl: _autoSyncTtl),
        );
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cubit = context.read<SessionUsageCubit>();
      await cubit.ensureLoaded();
      if (!mounted || !widget.autoSync || !_appActive) return;
      await cubit.syncIfStale(ttl: _autoSyncTtl);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && widget.autoSync) {
      unawaited(
        context.read<SessionUsageCubit>().syncIfStale(ttl: _autoSyncTtl),
      );
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Update the page listener and header call**

Replace the `BlocListener` with:

```dart
      listenWhen: (previous, current) =>
          previous.isSyncing && !current.isSyncing,
      listener: (context, state) {
        if (state.syncCancelled) {
          AppToast.show(
            context,
            message: context.l10n.sessionUsageSyncCancelled,
            variant: TpToastVariant.info,
          );
          return;
        }
        if (state.lastSyncManual &&
            !state.syncFailed &&
            state.syncErrors.isEmpty &&
            state.lastSyncResult != null) {
          AppToast.show(
            context,
            message: context.l10n.sessionUsageSyncedToast,
            variant: TpToastVariant.success,
          );
        }
      },
```

Pass the cancel callback to the header:

```dart
                UsagePageHeader(
                  state: state,
                  onSync: () => cubit.sync(),
                  onCancel: cubit.cancelSync,
                ),
```

- [ ] **Step 5: Regenerate l10n**

```bash
cd client
flutter gen-l10n
```

Expected: generated `app_localizations*.dart` include the new keys. Keep them staged in the commit.

- [ ] **Step 6: Update page tests**

In `client/test/pages/usage/session_usage_page_test.dart`, add the progress type import:

```dart
import 'package:teampilot/services/usage/usage_sync_control.dart';
```

Change `_wrap` to accept `autoSync` and default it off:

```dart
Widget _wrap(
  SessionUsageCubit cubit, {
  Brightness brightness = Brightness.light,
  bool autoSync = false,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness),
        scale: 1,
      ),
      child: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: SessionUsagePage(embedded: true, autoSync: autoSync),
        ),
      ),
    ),
  );
}
```

Replace the old `sync button is disabled while syncing` test with:

```dart
  testWidgets('sync shows progress and cancels the active handle', (
    tester,
  ) async {
    final progress = StreamController<UsageSyncProgress>(sync: true);
    final done = Completer<UsageSyncResult>();
    var cancelCalls = 0;
    final handle = UsageSyncHandle(
      done: done.future,
      progress: progress.stream,
      cancel: () => cancelCalls++,
    );
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async => const UsageSyncResult(),
      startSync: () => handle,
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(() async {
      await progress.close();
      await cubit.close();
    });

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageSyncButton));
    await tester.pump();
    expect(find.byKey(AppKeys.sessionUsageCancelSyncButton), findsOneWidget);

    progress.add(
      const UsageSyncProgress(
        targetsTotal: 2,
        targetsDone: 1,
        inserted: 3,
      ),
    );
    await tester.pump();
    expect(find.byKey(AppKeys.sessionUsageSyncProgress), findsOneWidget);
    expect(find.textContaining('Scanning 1/2'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.sessionUsageCancelSyncButton));
    expect(cancelCalls, 1);
    expect(cubit.state.isCancelling, isTrue);

    done.complete(const UsageSyncResult(cancelled: true));
    await tester.pumpAndSettle();
    expect(cubit.state.syncCancelled, isTrue);
    expect(find.byKey(AppKeys.sessionUsageSyncButton), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
```

Add auto sync tests at the end:

```dart
  testWidgets('auto sync scans once on open when stale', (tester) async {
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();

    expect(syncCount, 1);
  });

  testWidgets('auto sync timer rechecks stale data while visible', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 26, 18);
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();
    expect(syncCount, 1);

    now = now.add(const Duration(minutes: 11));
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(syncCount, 2);
  });

  testWidgets('auto sync rechecks stale data on app resume', (tester) async {
    var now = DateTime(2026, 10, 26, 18);
    var syncCount = 0;
    final cubit = SessionUsageCubit(
      loadEvents: () async => [_event()],
      syncAll: () async {
        syncCount++;
        return const UsageSyncResult();
      },
      loadSessions: () async => [_session('s1', 'Alpha')],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit, autoSync: true));
    await tester.pumpAndSettle();
    expect(syncCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 11));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(syncCount, 2);
  });
```

Ensure the existing `load reads cache once and never scans on open` test still passes because `_wrap` defaults to `autoSync: false`.

- [ ] **Step 7: Run the page and navigation tests**

```bash
cd client
dart run tool/run_tests.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/home_workspace/home_usage_navigation_test.dart
```

Expected: all tests pass. If the cancel toast leaves a pending timer, pump 3 seconds before the test ends.

- [ ] **Step 8: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/pages/usage/session_usage_page.dart \
  client/lib/pages/usage/widgets/usage_page_chrome.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/pages/usage/session_usage_page_test.dart
git commit -m "feat(usage): add foreground auto sync and cancel UI" -- \
  client/lib/pages/usage/session_usage_page.dart \
  client/lib/pages/usage/widgets/usage_page_chrome.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/pages/usage/session_usage_page_test.dart
```

---

## Task 5: Verification and plan completion

**Files:**
- Modify: `docs/superpowers/plans/2026-10-27-session-usage-auto-sync.md`
- Modify (checkbox updates only): this plan

- [ ] **Step 1: Run the focused suite**

```bash
cd client
dart run tool/run_tests.dart \
  test/services/usage/session_usage_sync_service_test.dart \
  test/services/usage/session_usage_services_test.dart \
  test/cubits/session_usage_cubit_test.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/home_workspace/home_usage_navigation_test.dart
```

Expected: every test passes.

- [ ] **Step 2: Run the analyzer**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit code 0. Pre-existing repo diagnostics may still be printed; no new diagnostics in the files touched by this plan.

- [ ] **Step 3: Run the full suite once in the background**

```bash
cd client
dart run tool/run_tests.dart
```

Expected: all tests pass. Do not run a second concurrent test command while this is running.

- [ ] **Step 4: Mark plan checkboxes and commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
perl -pi -e 's/- \[ \]/- [x]/g' \
  docs/superpowers/plans/2026-10-27-session-usage-auto-sync.md
git add docs/superpowers/plans/2026-10-27-session-usage-auto-sync.md
git commit -m "docs: mark usage auto sync plan complete" -- \
  docs/superpowers/plans/2026-10-27-session-usage-auto-sync.md
```

---

## Self-Review

### Spec coverage

- Auto sync on open: Task 4, Step 3.
- Auto sync on resume: Task 4, Step 3 (`didChangeAppLifecycleState`).
- Auto sync every 10 minutes while visible: Task 4, Step 3 timer.
- Prompts/cancel/progress: Task 1 service, Task 3 cubit, Task 4 UI.
- Per-source timeout: Task 1 service.
- Bounded target concurrency: Task 1 service.
- Cursor safety: Task 1 service ordering and `_ThrowingStore` test.
- Manual/auto toast distinction: Task 3 `lastSyncManual`, Task 4 listener.
- Existing tests remain usable: Task 3 fallback `syncAll`, Task 4 `autoSync: false` default in `_wrap`.
- No OS background: Task 4 schedules only while page mounted.

### Placeholder scan

No `TBD`, `TODO`, or “add error handling” steps. Every code step names the file and shows the intended code.

### Type consistency

- `UsageSyncProgress` is defined in `usage_sync_control.dart` and imported by the service, cubit, and header.
- `UsageSyncHandle` is defined in `session_usage_sync_service.dart` and returned by `SessionUsageServices.startSync`.
- `UsageSyncResult.cancelled` is the only new result field.
- `SessionUsageState.lastSyncManual` is set by `sync(manual:)` and consumed by the page listener.
- The cancel button key is `AppKeys.sessionUsageCancelSyncButton`; the progress key is `AppKeys.sessionUsageSyncProgress`.

### Known execution notes

- Do not touch `usage_summary_cards.dart` or its new test; they are separate user work.
- If `testHomeStorage` is not available from the suggested harness import, reuse the exact home-storage setup already used by other service tests rather than creating a second storage.
- If the concurrency test is timing-sensitive, use an active counter and assert the cap instead of asserting exact interleaving.
