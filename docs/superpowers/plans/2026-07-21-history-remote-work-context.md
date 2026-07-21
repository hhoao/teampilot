# History remote work-context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make History locate/parse/live-refresh use the same per-seat work-plane `RuntimeContext` as launch (`launchWorkContext`), so remote mixed / project-remote seats show transcripts without mirroring files to home.

**Architecture:** Inject `lifecycle.launchWorkContext` into `AiHistoryLoader`; resolve async per load/watch-meta from a `WorkspaceLaunchContext` (merged folder catalog). Keep existing in-memory `cacheToken` cache. Live refresh caches the seat `Filesystem` after resolve. On SSH target evict, invalidate the loader cache.

**Tech Stack:** Flutter/Dart, `AiHistoryLoader` / `AiHistoryCubit`, `SessionLifecycleService`, `RuntimeContextRegistry`, existing widget/unit tests under `client/test/`.

**Spec:** `docs/superpowers/specs/2026-07-21-history-remote-work-context-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/services/session/ai_history_loader.dart` | Async work-context resolve; build history ctx from seat FS/layout/root |
| `client/lib/cubits/ai_history_cubit.dart` | Plumb `WorkspaceLaunchContext` into loader calls; remember for softReload |
| `client/lib/pages/chat/session_history_review.dart` | folderCatalog cwd; resolve seat FS for live refresh |
| `client/lib/pages/chat_workbench.dart` | Pass workspace into `SessionHistoryReview` |
| `client/lib/services/session/ai_history_live_refresh_controller.dart` | Dartdoc / seat FS usage (sync getter after bind) |
| `client/lib/app/app_shell.dart` | Wire `resolveWorkContext` + `onEvict` → cache clear |
| `client/test/services/session/ai_history_loader_test.dart` | Remote vs home FS + cache clear |
| `client/test/services/session/ai_history_live_refresh_controller_test.dart` | Seat FS binding / constructor updates |
| `client/test/cubits/ai_history_cubit_test.dart` | LaunchContext plumbing |
| `client/test/pages/chat/session_history_*` | Fix constructor breakages |

---

### Task 1: Loader resolves work-plane FS (TDD)

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/test/services/session/ai_history_loader_test.dart`

- [ ] **Step 1: Write failing tests for seat FS selection**

Add to `ai_history_loader_test.dart` (keep existing tests compiling by providing a default resolver that returns a fixed `RuntimeContext` built from current temp `fs` / `layout` / `base.path`):

```dart
test('load uses work-context FS from resolver, not home FS', () async {
  // Arrange two roots: homeFs and workFs (InMemoryFilesystem or two temp dirs).
  // Write Claude fixture only under workFs session runtime paths (same as existing
  // parse test layout).
  // Resolver returns RuntimeContext(filesystem: workFs, layout: workLayout,
  //   appDataRoot: workRoot, …).
  final loader = AiHistoryLoader(
    contextBuilder: const SessionHistoryContextBuilder(),
    resolveWorkContext: (launchCtx, {String? memberId}) async => workRuntime,
    locator: locator,
    adapters: adapters,
    resolveCacheToken: (_) async => 't1',
  );
  final messages = await loader.load(
    session: session,
    memberId: 'lead',
    launchContext: WorkspaceLaunchContext(
      session: session,
      workspace: workspace,
    ),
  );
  expect(messages, isNotEmpty);
  // Assert home paths were never opened (read counters / locate roots).
});

test('resolve failure does not fall back to home FS', () async {
  final loader = AiHistoryLoader(
    resolveWorkContext: (_, {String? memberId}) async =>
        throw StateError('ssh down'),
    // …
  );
  await expectLater(
    () => loader.load(
      session: session,
      memberId: 'lead',
      launchContext: ctx,
    ),
    throwsA(isA<StateError>()),
  );
});
```

Use `InMemoryFilesystem` from `client/test/support/in_memory_filesystem.dart` when it supports needed ops; otherwise two temp `LocalFilesystem` roots.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/session/ai_history_loader_test.dart --name "work-context"
```

Expected: compile error or fail (`resolveWorkContext` / `launchContext` missing).

- [ ] **Step 3: Implement loader API**

Replace single-source `fs` / `layout` / `appDataRoot` with:

```dart
typedef AiHistoryWorkContextResolver = Future<RuntimeContext> Function(
  WorkspaceLaunchContext ctx, {
  String? memberId,
});

final class AiHistoryLoader {
  AiHistoryLoader({
    SessionHistoryContextBuilder contextBuilder =
        const SessionHistoryContextBuilder(),
    required AiHistoryWorkContextResolver resolveWorkContext,
    AiHistoryLocator? locator,
    Map<CliTool, AiTranscriptAdapter>? adapters,
    SessionHistoryCacheTokenResolver? resolveCacheToken,
    List<CliPreset> Function()? globalPresets,
  }) : ...
```

Make `_resolveSeat` async:

```dart
Future<_AiHistorySeat> _resolveSeat({
  required WorkspaceLaunchContext launchContext,
  required String memberId,
  TeamProfile? team,
  String? workingDirectory,
}) async {
  // existing CLI / effectiveMemberId logic …
  final mid = effectiveMemberId.isEmpty ? null : effectiveMemberId;
  final roots = await _resolveWorkContext(launchContext, memberId: mid);
  final ctx = _contextBuilder.build(
    fs: roots.filesystem,
    layout: roots.layout,
    appDataRoot: roots.appDataRoot,
    session: launchContext.session,
    memberId: effectiveMemberId,
    cli: cli,
    workingDirectory: workingDirectory,
    teamId: teamId.isEmpty ? null : teamId,
  );
  return _AiHistorySeat(...);
}
```

Update `load` / `resolveWatchMeta` to take `required WorkspaceLaunchContext launchContext`.

Expose for live refresh:

```dart
Future<RuntimeContext> resolveSeatRuntime({
  required WorkspaceLaunchContext launchContext,
  required String memberId,
}) =>
  _resolveWorkContext(
    launchContext,
    memberId: memberId.trim().isEmpty ? null : memberId.trim(),
  );

/// Clears all seats (v1 evict). Prefer over inventing a parallel API.
void clearCache() {
  _cache.clear();
}
```

Note: production `app_shell.dart` will not compile until Task 4 wires
`resolveWorkContext`. Intermediate commits may be test-scoped only, or squash
Tasks 1–4 before pushing.

- [ ] **Step 4: Fix all test constructors of `AiHistoryLoader`**

Update grepped call sites:
- `client/test/services/session/ai_history_loader_test.dart`
- `client/test/services/session/ai_history_live_refresh_controller_test.dart`
- `client/test/cubits/ai_history_cubit_test.dart`
- any other `AiHistoryLoader(`

Helper:

```dart
AiHistoryWorkContextResolver fixedRoots(RuntimeContext roots) =>
    (ctx, {String? memberId}) async => roots;
```

- [ ] **Step 5: Run loader + related unit tests**

```bash
cd client && flutter test \
  test/services/session/ai_history_loader_test.dart \
  test/cubits/ai_history_cubit_test.dart \
  test/services/session/ai_history_live_refresh_controller_test.dart
```

Expected: PASS (cubit may still fail until Task 2 if APIs diverge — finish Task 1 loader + loader tests first; update cubit tests in Task 2 if needed for compile).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/ai_history_loader.dart \
  client/test/services/session/ai_history_loader_test.dart \
  client/test/services/session/ai_history_live_refresh_controller_test.dart \
  client/test/cubits/ai_history_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(history): resolve seat work-context FS in AiHistoryLoader

EOF
)"
```

---

### Task 2: Cubit plumbs `WorkspaceLaunchContext`

**Files:**
- Modify: `client/lib/cubits/ai_history_cubit.dart`
- Modify: `client/test/cubits/ai_history_cubit_test.dart`

- [ ] **Step 1: Extend cubit load APIs**

Add `required WorkspaceLaunchContext launchContext` to `load` and `softReloadOrLoad`.

Store `_lastLaunchContext` with `_lastSession` / `_lastWorkingDirectory`.

`softReload` reuses `_lastLaunchContext` (if null, return early).

```dart
Future<void> load({
  required AppSession session,
  required String memberId,
  required WorkspaceLaunchContext launchContext,
  TeamProfile? team,
  String? workingDirectory,
  bool force = false,
}) async {
  _lastLaunchContext = launchContext;
  // …
  final messages = await _loader.load(
    session: session,
    memberId: memberId,
    launchContext: launchContext,
    team: team,
    workingDirectory: workingDirectory,
    force: force,
  );
}

Future<void> softReload() async {
  final session = _lastSession;
  final memberId = _lastMemberId;
  final launchContext = _lastLaunchContext;
  if (session == null || memberId == null || launchContext == null) return;
  // … invalidate + _loader.load(..., launchContext: launchContext, …)
}

Future<void> softReloadOrLoad({
  required AppSession session,
  required String memberId,
  required WorkspaceLaunchContext launchContext,
  TeamProfile? team,
  String? workingDirectory,
}) async { /* softReload or load with launchContext */ }
```

Also reset `_lastLaunchContext` wherever other `_last*` fields are cleared
(`clear` / seat reset paths).

- [ ] **Step 2: Update cubit tests**

```dart
WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
  session: s,
  workspace: Workspace(
    workspaceId: s.workspaceId,
    folders: s.folders,
    createdAt: 0,
  ),
);
```

Pass into every `cubit.load` / `softReloadOrLoad`.

- [ ] **Step 3: Run cubit tests**

```bash
cd client && flutter test test/cubits/ai_history_cubit_test.dart
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add client/lib/cubits/ai_history_cubit.dart \
  client/test/cubits/ai_history_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(history): plumb WorkspaceLaunchContext through AiHistoryCubit

EOF
)"
```

---

### Task 3: SessionHistoryReview — catalog cwd + seat FS live refresh

**Files:**
- Modify: `client/lib/pages/chat/session_history_review.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/services/session/ai_history_live_refresh_controller.dart` (dartdoc if needed)
- Test: `client/test/pages/chat/session_history_*.dart`
- Test: `client/test/services/session/ai_history_live_refresh_controller_test.dart`

- [ ] **Step 1: Pass workspace into History review**

Add `required Workspace workspace` on `SessionHistoryReview`.

In `chat_workbench.dart`:

```dart
final workspace = chatCubit.state.workspaces
    .where((w) => w.workspaceId == workspaceId)
    .firstOrNull;
return SessionHistoryReview(
  session: appSession,
  workspace: workspace ??
      Workspace(
        workspaceId: workspaceId,
        folders: appSession.folders,
        createdAt: 0,
      ),
  // …
);
```

- [ ] **Step 2: Fix `_workspaceRoot` to use folderCatalog**

```dart
WorkspaceLaunchContext get _launchContext => WorkspaceLaunchContext(
  session: widget.session,
  workspace: widget.workspace,
);

String get _workspaceRoot {
  final work = widget.session.workDirsForMember(
    widget.selectedMemberId,
    folders: _launchContext.folderCatalog,
  );
  if (work.workingDirectory.isNotEmpty) return work.workingDirectory;
  return widget.session.firstFolderPath;
}
```

Pass `_launchContext` into every `cubit.load` / `softReloadOrLoad` / `resolveWatchMeta`.

- [ ] **Step 3: Bind live-refresh FS from seat runtime**

Replace `_ensureLiveRefreshController` + start so seat FS is resolved **before** attach:

```dart
Future<void> _startLiveRefresh({bool skipInitialRefresh = false}) async {
  final cubit = context.read<AiHistoryCubit>();
  final roots = await cubit.loader.resolveSeatRuntime(
    launchContext: _launchContext,
    memberId: widget.selectedMemberId,
  );
  if (!mounted) return;
  await _liveRefresh?.stop();
  _liveRefresh = AiHistoryLiveRefreshController(
    cubit: cubit,
    fs: () => roots.filesystem, // closed-over seat FS — not AppStorage.fs
    resolveWatchMeta: () => cubit.loader.resolveWatchMeta(
      session: widget.session,
      memberId: widget.selectedMemberId,
      team: widget.team,
      workingDirectory: _workspaceRoot,
      launchContext: _launchContext,
    ),
  );
  await _liveRefresh!.ensureStarted(skipInitialRefresh: skipInitialRefresh);
  if (mounted) setState(() {});
}
```

Keep seat-change stop/recreate. Do **not** fall back to `AppStorage.fs` for remote seats.

Remove or gut `_ensureLiveRefreshController()` so it no longer constructs a
controller with `() => AppStorage.fs`. Route `_maybeStartLiveRefreshForRunningPty`
through the async `_startLiveRefresh` only.

- [ ] **Step 4: Update widget/live-refresh tests**

Fix constructors; assert signal factory still receives injected FS.

- [ ] **Step 5: Run related tests**

```bash
cd client && flutter test \
  test/services/session/ai_history_live_refresh_controller_test.dart \
  test/pages/chat/session_history_thread_test.dart \
  test/pages/chat/session_history_review_messages_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart \
  test/pages/chat/session_history_review_submit_test.dart
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat/session_history_review.dart \
  client/lib/pages/chat_workbench.dart \
  client/lib/services/session/ai_history_live_refresh_controller.dart \
  client/test/pages/chat \
  client/test/services/session/ai_history_live_refresh_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(history): use launch folderCatalog and seat FS for live refresh

EOF
)"
```

---

### Task 4: Bootstrap wiring + evict invalidate

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart` (`clearCache` if not in Task 1)
- Modify: `client/test/services/session/ai_history_loader_test.dart`

- [ ] **Step 1: Wire `AiHistoryLoader` to lifecycle**

Near existing `AiHistoryLoader(` (~line 987):

```dart
final aiHistoryLoader = AiHistoryLoader(
  contextBuilder: const SessionHistoryContextBuilder(),
  resolveWorkContext: (launchCtx, {String? memberId}) =>
      sessionLifecycleService.launchWorkContext(
        launchCtx,
        memberId: memberId,
      ),
  globalPresets: () => cliPresetsCubit.state.presets,
);
```

- [ ] **Step 2: Evict → clearCache**

`RuntimeContextRegistry` is created before the loader. Use a late holder:

```dart
AiHistoryLoader? aiHistoryLoaderRef;

final runtimeContextRegistry = RuntimeContextRegistry(
  // …
  onEvict: (targetId) async {
    final pid = sshProfileIdOfId(targetId);
    if (pid != null) sshClientFactory.disconnectProfile(pid);
    // v1: clear all history memory cache on work-plane drop.
    aiHistoryLoaderRef?.clearCache();
    // Equivalent: invalidate every open session if preferred; v1 full clear is OK.
  },
);

// after constructing loader:
aiHistoryLoaderRef = aiHistoryLoader;
```

- [ ] **Step 3: Unit test `clearCache`**

```dart
test('clearCache drops token hits', () async {
  // load once → second load cache hit (locateCalls==1) → clearCache
  // → third load locateCalls==2
});
```

If you prefer not to add `clearCache`, extend existing `invalidate` with an
all-seats overload and call that from `onEvict` instead — do not keep two
divergent clear paths.

- [ ] **Step 4: Analyze touched files**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/session/ai_history_loader.dart \
  lib/cubits/ai_history_cubit.dart \
  lib/pages/chat/session_history_review.dart \
  lib/app/app_shell.dart
```

Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart \
  client/lib/services/session/ai_history_loader.dart \
  client/test/services/session/ai_history_loader_test.dart
git commit -m "$(cat <<'EOF'
feat(history): wire launchWorkContext and clear cache on target evict

EOF
)"
```

---

### Task 5: Verification sweep

**Files:** none (commands only)

- [ ] **Step 1: Targeted test suite**

```bash
cd client && flutter test \
  test/services/session/ai_history_loader_test.dart \
  test/services/session/ai_history_live_refresh_controller_test.dart \
  test/cubits/ai_history_cubit_test.dart \
  test/pages/chat/session_history_thread_test.dart \
  test/pages/chat/session_history_review_messages_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart \
  test/pages/chat/session_history_review_submit_test.dart \
  test/pages/chat/session_history_submit_gate_test.dart
```

Expected: all PASS

- [ ] **Step 2: Broader analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Fix any remaining `AiHistoryLoader(` / `cubit.load(` call-site breakages.

- [ ] **Step 3: Manual checklist**

- Local simple session: History unchanged
- Mixed workspace remote member: History shows remote transcript when SSH up
- Same seat live continue: softReload updates without loading flash
- Disconnect SSH mid-History: error/softReloadError — no silent empty local success
- Project-remote: History matches remote machine transcripts

- [ ] **Step 4: Commit analyze/test fixes if any**

Only if Step 1–2 required code fixes.

---

## Out of scope (do not implement)

- Transcript tree mirror to `AppStorage`
- Disk snapshot for offline remote History
- Changing adapter parsers / pagination windows
