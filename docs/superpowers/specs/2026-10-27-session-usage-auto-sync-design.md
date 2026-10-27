# Agent CLI Usage Auto Sync and Sync Reliability

**Date:** 2026-10-27
**Status:** Approved design, pending spec review
**Parent feature:** `docs/superpowers/specs/2026-10-26-agent-cli-usage-tracking-design.md`

## Goal

Make the existing agent-CLI usage pipeline update itself while the `Token 用量`
page is open, and make long-running scans controllable. This slice adds
foreground auto sync, progress, cooperative cancellation, per-source timeouts,
and bounded concurrency without changing the extraction, storage, or
aggregation contracts.

## Scope

- Auto sync when the usage page opens and its cache is stale.
- Auto sync when the app returns to the foreground while the usage page is
  mounted.
- Auto sync every 10 minutes while the usage page is mounted and the app is
  active.
- Progress reporting during a scan.
- A cancel affordance while a scan is running.
- Per-source timeout and bounded target concurrency.
- Per-source failure isolation and a non-fatal cancelled result.
- Unit, cubit, and widget tests for the above.

## Non-goals

- OS-level background execution (Android WorkManager, desktop background
  service, background isolates).
- Full startup scan. Opening the app still only loads the cached JSONL.
- Cost/pricing, additional CLIs, global transcript roots, session-header
  meter, per-message usage, and ACP live usage. These remain separate
  milestones.
- Per-source error-detail UI. This slice reports the failure count; a detail
  list is a follow-up.
- JSONL compaction or retention changes.

## Decisions

| Decision | Value |
|---|---|
| Auto-sync stale threshold | 5 minutes since the last completed sync |
| Auto-sync interval while visible | 10 minutes |
| Per-source I/O step timeout | 30 seconds per read/scan/upsert/cursor save, injectable for tests |
| Target concurrency | 4 workers, injectable for tests |
| Auto-sync default | On for the production page; tests pass `autoSync: false` |
| Startup scan | Never; only cache load |
| Background scan while page is not mounted | Never in this slice |
| Cancellation granularity | Cooperative at target/source/step boundaries |
| Timeout behavior | Best-effort; an in-flight SFTP read may finish after timeout |
| Cursor on cancel/timeout | Never advance without a successful upsert |
| Manual sync | Always runs, even if the cache is fresh |
| Auto-sync failure | Updates the existing banner; no success/cancel toast |
| Last-sync timestamp | Updated after a completed scan, including cancelled scans |

### Why page-scoped auto sync

The usage page is the only consumer of this data. Syncing while the page is
not mounted adds remote I/O and can surprise users on metered or SSH
connections. Page-scoped auto sync gives predictable behavior without taking
on OS background-task constraints.

## Architecture

### Sync control, progress, and handle

New types live in `services/usage/session_usage_sync_service.dart` or a small
adjacent file:

```dart
final class UsageSyncControl {
  bool get isCancelled;
  void cancel();
  void throwIfCancelled();
}

final class UsageSyncCancelled implements Exception {}

@immutable
final class UsageSyncProgress {
  final int targetsTotal;
  final int targetsDone;
  final int sourcesDone;
  final int inserted;
  final int updated;
  final int skipped;
  final int errors;
  final String? currentSourceId;
  final bool isCancelled;
}

final class UsageSyncHandle {
  Stream<UsageSyncProgress> get progress;
  Future<UsageSyncResult> get done;
  void cancel();
}
```

`UsageSyncProgress` is best-effort. `targetsTotal` is known after target
enumeration; `sourcesDone` counts processed sources. The source total is not
known up front because discovery differs per CLI.

`UsageSyncResult` gains `cancelled`. Per-source timeouts are recorded in
`errors`; cancellation is not an error.

### `SessionUsageSyncService`

```dart
Future<UsageSyncResult> syncAll({
  UsageSyncControl? control,
  void Function(UsageSyncProgress)? onProgress,
});
```

- Keep the existing process-wide static lock.
- Enumerate targets through `UsageScanTargetProvider`.
- Process targets with a bounded worker pool (`maxConcurrentTargets`, default
  4).
- For each source:
  1. Check cancellation.
  2. Read the cursor.
  3. Scan with `sourceTimeout`.
  4. Check cancellation.
  5. Upsert events with `sourceTimeout`.
  6. Check cancellation.
  7. Save the cursor with `sourceTimeout`.
- Check cancellation before each target and between each step.
- A source error is appended to `errors` and does not abort other sources.
- Cancellation stops new work; sources already in flight are allowed to finish
  or time out. The result has `cancelled = true`.
- Never save a cursor after cancellation or timeout. If an upsert succeeded but
  cancellation arrived before the cursor save, the next scan re-reads the same
  source and the idempotent store skips duplicate `requestId`s.
- Progress is emitted at start, after target enumeration, before/after each
  source, and at completion.

The static lock means a second caller waits. A cancel request made while
waiting is observed as soon as the lock is acquired.

### `SessionUsageServices`

Add:

```dart
UsageSyncHandle startSync();
```

`startSync` builds a service for the current home plane and returns a handle.
`SessionUsageServices.syncAll` remains for existing callers and tests.

### `SessionUsageCubit`

Constructor gains an optional `startSync`:

```dart
UsageSyncHandle Function()? startSync,
```

`SessionUsageState` gains:

- `UsageSyncProgress? syncProgress`
- `bool isCancelling`
- `bool syncCancelled`

`SessionUsageCubit` gains:

- `Future<void> syncIfStale({Duration ttl = const Duration(minutes: 5)})`
- `void cancelSync()`

Behavior:

- `sync()` stays single-flight. A second call reuses the in-flight future.
- When `startSync` is present, `sync()` subscribes to the handle's progress,
  emits `syncProgress`, awaits `done`, and reloads cached events/attribution.
- When `startSync` is absent, the existing `syncAll` path remains, with
  `syncProgress = null`.
- `syncIfStale` returns immediately if a sync is in flight, or if
  `lastSyncAtMs` is newer than `ttl`; otherwise it calls `sync()`.
- `cancelSync()` sets `isCancelling`, calls the active handle's `cancel()`, and
  is a no-op when nothing is running.
- On completion, `isSyncing`/`isCancelling` clear, `lastSyncAtMs` updates,
  `syncCancelled` reflects the result, and `syncErrors` comes from the result.
- On fatal errors, keep the old dashboard, set `syncFailed`, and do not update
  `lastSyncAtMs`.
- `close()` cancels the active handle, cancels the progress subscription, and
  then closes the cubit. Pending completions check `isClosed` before emitting.

### Page auto sync

`SessionUsagePage` gains `autoSync` (default `true`).

When `autoSync` is true:

- After `ensureLoaded()`, call `syncIfStale()`.
- Observe app lifecycle. On `resumed`, call `syncIfStale()` if the page is
  mounted and the app is active.
- Start a 10-minute periodic timer. The timer calls `syncIfStale()` only while
  the app is active.
- Cancel the timer and remove the observer in `dispose`.

The page tests pass `autoSync: false` except for dedicated auto-sync tests.

### UI

- While syncing, the header button becomes **Cancel**.
- While cancelling, the button is disabled and labelled **Cancelling**.
- A progress line appears under the scope subtitle, for example:
  `Scanning 3/20 sessions · 12 new events`.
- Cancellation shows an info toast and keeps existing data.
- Automatic sync failures use the existing error banner; no toast.
- Manual sync success keeps the existing success toast.

New l10n keys:

- `sessionUsageCancelSync`
- `sessionUsageCancelling`
- `sessionUsageSyncCancelled`
- `sessionUsageSyncProgress` with `done`, `total`, `inserted` placeholders

New AppKeys:

- `sessionUsageCancelSyncButton`
- `sessionUsageSyncProgress`

## Data flow

1. Usage page mounts.
2. `ensureLoaded()` reads the cached JSONL and attribution.
3. If auto sync is enabled, `syncIfStale()` checks `lastSyncAtMs`.
4. Stale or never-synced pages call `sync()`.
5. Cubit calls `SessionUsageServices.startSync()`.
6. Service acquires the process lock, enumerates targets, and scans with
   bounded concurrency.
7. Progress events update the header.
8. On completion, cubit reloads the cached JSONL and recomputes the dashboard.
9. On cancel, cubit keeps the old dashboard, marks the attempt cancelled, and
   updates `lastSyncAtMs`.

## Error handling

- Target enumeration failure returns a single `*` error, as today.
- Capability discovery failure is recorded per target and continues.
- Source timeout is recorded as `UsageSyncError(sourceId, 'timed out')`.
- Cancellation is not recorded in `errors`; it sets `cancelled`.
- Store/cursor failures are source errors; the cursor stays behind.
- Fatal cubit errors keep the old dashboard and `syncFailed = true`.
- Auto sync does not retry immediately after failure; the next timer tick,
  page open, or app resume can retry.
- Cancelled scans update `lastSyncAtMs` so a resume does not immediately
  restart the scan the user just cancelled.

## Testing

### Service

- Emits progress with target/source counts and inserted/updated/skipped totals.
- Honours `maxConcurrentTargets` (use a fake capability with active counters).
- Records a per-source timeout and continues other sources.
- Cancels before target discovery and between sources.
- Returns `cancelled = true` without error entries on cancellation.
- Never advances the cursor when the upsert fails or cancellation arrives
  before the cursor save.
- Keeps per-source error isolation.

### Cubit

- `syncIfStale` syncs when never synced and when older than the ttl.
- `syncIfStale` skips when fresh or already syncing.
- Progress events update state.
- `cancelSync` cancels the active handle and sets `syncCancelled`.
- Fatal sync keeps the old dashboard and does not update `lastSyncAtMs`.
- `close` cancels the active handle without emitting after close.

### Page

- `autoSync: false` never scans on open.
- `autoSync: true` syncs after cache load when stale.
- The sync button becomes Cancel while syncing.
- Progress text renders.
- Cancel calls `cancelSync` and the toast appears.
- Existing page tests continue to pass with `autoSync: false`.

### Verification

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart \
  test/services/usage/session_usage_sync_service_test.dart \
  test/cubits/session_usage_cubit_test.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/home_workspace/home_usage_navigation_test.dart
dart run tool/run_tests.dart
```

## Risks

- **Timeout cannot abort a single SFTP read.** The future may continue after
  the timeout. The cursor is not advanced, and the store is idempotent, so a
  later scan is safe.
- **Concurrency increases remote load.** Default 4 targets; make it
  injectable and revisit if SSH profiles report saturation.
- **Auto sync can surprise users.** It only runs while the page is mounted and
  the app is active, with a 5-minute stale threshold.
- **Desktop lifecycle differences.** Track app-active state from
  `AppLifecycleState`; do not rely on the timer alone.
- **Progress totals.** Source counts are only known as discovery proceeds;
  the UI must tolerate `targetsTotal == 0` and partial counts.
- **Cancellation in a queued sync.** The control is checked immediately after
  the static lock is acquired, so a cancel while waiting does not start work.

## Follow-ups

1. OS-level background sync.
2. Per-source error-detail UI and retry-one-source.
3. Cost engine and pricing table.
4. JSONL compaction and retention.
5. Additional CLIs and global roots.
6. Session-header meter, per-message usage, and ACP live usage.
