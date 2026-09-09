# Auto Git Fetch in Source Control Panel — Design

Date: 2026-09-09

## Problem

The source-control panel polls `git status --porcelain=v2 --branch` on a timer
(watcher fast path + 5s/15s poll backstop in `RightToolsLifecycleHost`), but
nothing ever runs `git fetch`. The ahead/behind counts shown in the panel are
computed against the locally cached remote-tracking branch, so they stay stale
until the user manually clicks the Git Graph toolbar fetch button or fetches
in a terminal.

## Goal

Periodically run `git fetch --all --prune` for the repository the
source-control panel is currently showing, so ahead/behind counts stay fresh
without manual action.

## Decisions (confirmed with user)

- **Scope:** only the currently selected repo root (fallback: first root) —
  the repo whose ahead/behind the panel displays.
- **Gating:** runs while the right-tools panel lifecycle is active with the
  git tool enabled (`preferences.gitVisible`), matching the existing
  `_diskPollTimer` gating. Suspends on background; fetches immediately once
  on resume.
- **Backends:** all storage backends (native / WSL / SSH). The fetch executes
  on the host that owns the repository, same as every other git command.
- **Default:** enabled, configurable.

## Design

### 1. Settings model (`SessionPreferences`)

Two new fields, same pattern as `reclaimIdleTerminals`:

- `gitAutoFetchEnabled` — `bool`, default `true`
- `gitAutoFetchIntervalMinutes` — `int`, default `5`; UI offers 1 / 5 / 15

Settings UI goes in `session_config_section.dart` (existing session
preferences section). l10n strings added to `app_en.arb` / `app_zh.arb` only.

### 2. Non-interactive fetch (`GitHistoryActions.fetchAllQuiet`)

`fetchAllQuiet(String dir)` differs from the existing manual `fetchAll`:

- Passes `GIT_TERMINAL_PROMPT=0` via a new optional `environment` parameter on
  `GitCommandRunner.runInDirectory` (threaded through to the existing
  `HostRunRequest.environment`; one-line passthrough in each of the three
  runner implementations). A credential prompt must never hang the scheduler.
- A 60s timeout is enforced by the scheduler via `.timeout()` — the abandoned
  process may linger, which is acceptable and logged.

The Git Graph toolbar fetch button keeps using `fetchAll`; a user-initiated
action may legitimately prompt.

### 3. Scheduler (`services/git/git_auto_fetch_scheduler.dart`, new)

Pure Dart class, no Flutter dependencies, constructor-injected for testing:

```dart
GitAutoFetchScheduler({
  required Future<void> Function(String dir) fetch, // = actions.fetchAllQuiet
  required void Function() onFetched,                // = refresh status + graphs
  required Duration interval,
})
```

- API: `start(root)` / `stop()` / `tick()` (`@visibleForTesting`) / `dispose()`.
  `start(root)` is a no-op when already running on the same root; otherwise
  (first start, resume after `stop`, or target change) it resets the timer
  and fetches immediately once.
- A tick while a fetch is still in flight is skipped (no pile-up).
- Failures (`GitException`, `TimeoutException`) are swallowed and logged via
  `appLogger.w`; no user-facing error surface.

### 4. Lifecycle wiring (`RightToolsLifecycleHost`)

The host owns and drives the scheduler through the existing gating signals:

- **Active** when `_lifecycleActive && preferences.gitVisible` — same
  suspend/resume paths as `_diskPollTimer` (`_suspendDiskSideEffects` /
  `_resumeDiskSideEffects` / `_setupDiskRefresh`). On resume, the scheduler's
  immediate first fetch keeps counts fresh.
- **Target** = `_selectedGitRoot.value ?? first root` (same fallback
  semantics as `GitRepoStore.refreshAll`'s `activeRoot`). The host listens to
  the `_selectedGitRoot` `ValueNotifier` and calls `replaceTarget`.
- **Refresh hookup:** `onFetched` calls `_warmGit()` (`store.refreshAll` +
  `refreshGraphs`) so ahead/behind and any open Git Graph pane update at once,
  not on the next poll tick.
- **Settings changes** (toggle / interval) flow through `didUpdateWidget` →
  `_setupDiskRefresh`, which rebuilds the scheduler with the new
  configuration.

### 5. Error handling

Background auto-fetch never surfaces errors to the UI. Non-zero exit
(`GitException`), timeout, and scheduler skips are diagnostics for
`AppLogger`. l10n strings are needed only for the settings UI labels.

## Testing

- `git_auto_fetch_scheduler_test.dart` (pure unit tests, injected
  `fetch`/`tick`): immediate fetch on start, periodic fetch, in-flight skip,
  target replacement resets and fetches, failures swallowed, no fetch after
  `stop`.
- `GitHistoryActions` tests: `fetchAllQuiet` passes `GIT_TERMINAL_PROMPT=0`
  in the environment (and plain `fetchAll` does not).
- `right_tools_lifecycle` widget tests: scheduler starts when the git tool is
  visible, suspends on background, retargets on selection change.

## Non-goals

- Auto-pull / auto-push. Only `fetch --all --prune`.
- Auto-fetch for non-selected roots (no background-root low-frequency tier).
- Any fetch activity when the right-tools git tool is disabled or the panel
  lifecycle is suspended.
