# Task 9 Report: Layout snapshot persistence

**Status:** Complete. All tests pass, analyze clean for touched files.

## What the interrupted draft had

The predecessor's uncommitted draft was substantially complete and architecturally
sound. It contained:

- `client/lib/repositories/workbench_layout_snapshot_repository.dart` — the
  repository (save / restore / delete, version check, corrupt-file fallback,
  landing revival, constructor-injected `Filesystem` + `WorkspaceLayout`).
- `client/lib/services/workbench/workbench_layout_persistence.dart` — an
  app-lifetime coordinator (`WorkbenchLayoutPersistence`) owning one debounced
  `WorkbenchCubit.stream` subscription and the at-most-once per-workspace
  restore, with the session-id `tabResolves` resolver against `ChatCubit`.
- Wiring: `app_shell.dart` (construct + `start()` the coordinator, expose it on
  `AppShell`), `main.dart` (`RepositoryProvider.value`), `workspace_page.dart`
  (restore hooks after session rehydration), `workspace_layout.dart`
  (`workbenchLayoutFile` path accessor), `docs/workspace-storage-layout.md` doc
  line.
- Three test files (repository, cubit-level restore, coordinator-level
  persistence with `fakeAsync` debounce driving).

## What I verified / changed and why

I reviewed the draft line-by-line against the brief and the binding rulings and
verified every API it consumes against the current tree:

- **Ruling 1 (storage pattern):** repository mirrors `AutomationRepository`
  exactly — constructor-injected `Filesystem` + `WorkspaceLayout`, defaulting to
  `AppStorage.fs` / `WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath)`,
  the same defaults `app_shell.dart` uses for `automationRepo` (verified at
  `app_shell.dart:1702-1704`). Path is
  `<teampilotRoot>/workspace/workspaces/{id}/workbench-layout.json` via
  `WorkspaceLayout.workbenchLayoutFile`. No change needed.
- **Ruling 2 (API + format):** `WorkbenchLayoutSnapshotRepository({required
  this.workspaceId})` with `save(center, floating)`, `restore(WorkbenchCubit
  workbench, {tabResolves})`, `delete()`; JSON is
  `{"center": <Task 1 snapshot>, "floating": <…>, "version": 1}` via Task 1's
  `toSnapshot` / `layoutFromSnapshot` (verified in
  `cubits/workbench/workbench_split_layout.dart:449-500`). Matches.
- **Ruling 3 (tabResolves + hook after rehydration):** session ids resolve
  against `ChatCubit.state.sessions` (sessionId + workspaceId match) and
  `ChatCubit.tabStore.openTabs` (`tab.info.id`); all other kinds return true.
  Verified `tabStore` is a public getter (`chat_cubit.dart:502`). Hook points
  verified (below).
- **Ruling 4 (debounced save):** 500 ms debounce; instead of a literal
  "skip first emission" the coordinator seeds the diff baseline from
  `state.byWorkspace` at `start()` and diffs every emission
  (`WorkspaceTabBar` is `Equatable`, so `!=` is structural). Since bloc
  `stream` is a broadcast controller that does not replay current state, the
  seed is exactly equivalent to skipping the first emission — and strictly
  better, because it also suppresses no-op re-saves. Emissions during a restore
  only refresh the baseline; the debounce is re-armed in the restore's
  `finally` when the dirty set is non-empty. Flushes are re-entrancy guarded
  (`_flushInFlight` / `_flushAgain`). The `app_shell.dart` edit is minimal
  (one construction site, one constructor field, one import). I judged the
  draft's interpretation compliant and kept it.
- **Ruling 5 (never throws):** every IO and decode path is wrapped in
  `on Object catch` with `appLogger.w`; missing/empty file is a silent no-op;
  version mismatch and non-object JSON are logged as corrupt and fall back.
- **Ruling 6 (tests via fake filesystem):** all three test files use the
  existing `test/support/in_memory_filesystem.dart` fake (same harness pattern
  as the automation / launch-profile repository tests). No real disk IO.
- **Ruling 7 (workspace removal):** verified
  `ChatCubit.deleteWorkspace` (`chat_cubit.dart:2658`) →
  `SessionRepository.deleteWorkspace` (`session_repository.dart:1466`) →
  `SessionRepositoryFs.deleteWorkspaceDir` (`session_repository_fs.dart:60`)
  → `fs.removeRecursive(workspaceDir(workspaceId))`, which removes
  `workbench-layout.json` with the rest of the workspace directory. No extra
  wiring needed; `WorkbenchCubit.clearWorkspace` (workspace tab close) is
  observed by the coordinator's stream listener, which drops the workspace from
  the dirty set and re-arms its restore for reopen. There is exactly **one**
  app-lifetime stream subscription (no per-workspace subscriptions to leak).

Things I checked and deliberately kept from the draft:

- `_withoutRuntimeLanding` revival: `toSnapshot` drops landing runtime fields and
  encodes "landing shown" as `activeId: null`; restoring that verbatim would
  resurrect a degraded, draft-less landing. The repository activates the first
  tab of such strips instead (same "neighbor → first" fallback the strip reducer
  applies when the active tab disappears). Covered by a dedicated test.
- `delete()` uses `removeRecursive` on the file path — matches the existing
  single-file removal convention in `ssh_profile_repository.dart:64`.

**I made no code changes to the draft.** It passed review, analyze, and all
tests as-is; the predecessor simply never got to run them.

## Exact restore hook point

`client/lib/pages/home_workspace/workspace/workspace_page.dart`:

1. **Workspace activation (primary):**
   `_WorkspacePageState._activateRoute()` → chains
   `ChatCubit.ensureSessionsForWorkspace(widget.workspaceId)` `.then((_) =>
   _restoreWorkbenchLayoutSnapshot())`. This is the post-frame route-activation
   path from `_scheduleActivation()` (initState / route re-activation), so the
   snapshot lands **after** the workspace's sessions are rehydrated and
   `tabResolves` is accurate.
2. **Session deep link (`?session=`):**
   `_applySessionFromRoute()` awaits `ensureSessionsForWorkspace`, then **awaits**
   `_restoreWorkbenchLayoutSnapshot()` before `_resolveSessionForDeepLink` /
   `openWorkspaceSessionTab`, so a deep-linked session tab can never be reset
   away by the restore landing after it.

Both funnel into `WorkbenchLayoutPersistence.restoreForWorkspace(workspaceId)`,
which is at-most-once per workspace (re-armed on bar clear) and shares the
in-flight future across concurrent callers. The provider is missing in pure
widget tests (`ProviderNotFoundException` caught → no-op).

## Save wiring

`app_shell.dart` (`buildAppShell`, after `workbenchCubit` is created):

```dart
final workbenchLayoutPersistence = WorkbenchLayoutPersistence(
  workbench: workbenchCubit,
  chat: chatCubit,
)..start();
```

exposed as `AppShell.workbenchLayoutPersistence` and provided in `main.dart`
via `RepositoryProvider.value`. One broadcast subscription on
`WorkbenchCubit.stream` covers every workspace; per-emission structural diff
against the baseline marks dirty workspaces; a 500 ms debounce flushes each
dirty workspace's `bar.center` / `bar.floating` through its (cached)
`WorkbenchLayoutSnapshotRepository`.

## Test list

- `test/repositories/workbench_layout_snapshot_repository_test.dart` (13 tests)
  — save format/versioning, workspace-dir scoping, round-trip into a fresh
  cubit, landing fields not leaking, missing file / corrupt JSON / non-object
  JSON / version mismatch / missing center-fallback, unresolved-session prune
  with group roll-up, no-surviving-group fallback, delete + delete no-op.
- `test/cubits/workbench/snapshot_restore_test.dart` (3 tests) — cubit-level
  save → `clearWorkspace` + reopen → restore (split structure, pins, floating
  groups intact), prune via rejecting resolver, corrupt snapshot leaves the
  reset bar untouched.
- `test/services/workbench/workbench_layout_persistence_test.dart` (6 tests) —
  coordinator: first-change debounce save, coalescing, dispose cancels pending
  flush, at-most-once restore + re-arm after bar clear, session-tab pruning via
  ChatCubit resolver, no-snapshot no-op. Debounce driven deterministically with
  `fakeAsync`; ChatCubit under `setUpTestAppStorage`/`tearDownTestAppStorage`.

Regression suites run around the touched files (all green): all of
`test/cubits/workbench/` (122), `test/pages/home_workspace/workspace/` (89),
`test/pages/home_workspace/` (231), `test/smoke/` (5), `test/repositories/`
(238), `test/services/workbench/` (138).

## Commands run and outputs

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
  → 351 issues found (all pre-existing baseline warnings/infos in unrelated
    files; zero issues in any file touched by this task — verified by grep of
    the analyzer output for workbench_layout / snapshot_restore /
    workspace_page.dart / app_shell.dart / workspace_layout.dart / main.dart)

cd client && dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart
  → +13: All tests passed!

cd client && dart run tool/run_tests.dart test/cubits/workbench/snapshot_restore_test.dart
  → +3: All tests passed!

cd client && dart run tool/run_tests.dart test/services/workbench/workbench_layout_persistence_test.dart
  → +6: All tests passed!

cd client && dart run tool/run_tests.dart test/cubits/workbench/
  → +122: All tests passed!
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/
  → +89: All tests passed!
cd client && dart run tool/run_tests.dart test/pages/home_workspace/
  → +231: All tests passed!
cd client && dart run tool/run_tests.dart test/smoke/
  → +5: All tests passed!
cd client && dart run tool/run_tests.dart test/repositories/
  → +238: All tests passed!
cd client && dart run tool/run_tests.dart test/services/workbench/
  → +138: All tests passed!
```

(Logged `[workbench-layout]` warnings in test output are the expected
corrupt/fallback logging paths being exercised, not failures.)

## Notes / residual observations

- The restore's own emission is baseline-refreshed during the in-flight restore
  and re-saved once 500 ms later (idempotent write of identical data). Kept:
  it also guarantees any user change that raced the restore is persisted.
- The coordinator retains small per-workspace bookkeeping (baseline entry,
  repository cache) for the app's lifetime; a removed workspace's entry is
  dropped from the dirty/restored sets on bar clear. No subscription leaks.
- `WorkbenchLayoutPersistence.dispose()` exists but is not called anywhere —
  the coordinator is app-lifetime, matching `WorkbenchCubit` itself.
