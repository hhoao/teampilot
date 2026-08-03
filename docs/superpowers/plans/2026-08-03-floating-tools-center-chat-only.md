# Floating tools / center Chat-only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On compose landing (and always), Run/shellScript opens the floating workspace; when file preview is floating, center stays Chat-only; process Run logs use a floating `run` surface.

**Architecture:** Hoist `WorkbenchShellRunSync` from `ChatPageShell` to `WorkspaceSplitPane` so compose landing receives `RunUiIntent`. Route `RunToolSurface.run` to a new floating `RunFloatingSurface` and stop reconciling Run sessions onto center `WorkbenchTabKind.run`. Keep file/diff dual-host; never `dismissNewChat` for floating tool opens.

**Tech Stack:** Flutter, `flutter_bloc`, existing `FloatingWorkspaceCubit` / `RunCubit` / `WorkbenchCubit`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-03-floating-tools-center-chat-only-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/workbench/workbench_run_intent.dart` | Add `resolveFloatingTabForRunIntent` (+ `floatingRunTabId`) |
| `client/lib/services/workbench/workbench_shell_run_sync_logic.dart` | Change plan to describe floating Run sync (or replace with floating-oriented plan helpers) |
| `client/lib/widgets/workbench/workbench_shell_run_sync.dart` | Intent → floating tabs; reconcile floating Run tabs (not center) |
| `client/lib/services/floating_workspace/surfaces/run_floating_surface.dart` | New floating surface for process Run logs |
| `client/lib/services/floating_workspace/floating_surface_registry.dart` | Accept optional `run` in `withDefaults` |
| `client/lib/app/app_shell.dart` | Wire `RunFloatingSurface` |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Mount `WorkbenchShellRunSync` |
| `client/lib/pages/chat/chat_page_shell.dart` | Remove nested `WorkbenchShellRunSync` |
| `client/lib/services/floating_workspace/migrate_legacy_workbench_tabs.dart` | Migrate center `run` tabs → floating |
| `client/lib/services/workbench/workbench_editor_opener.dart` | Stop `dismissNewChat` on floating file/diff opens |
| `client/lib/pages/chat/chat_page_shell.dart` / projection | Stop advertising center run titles (safe once reconcile stops) |
| Tests under `client/test/services/workbench/`, `client/test/services/floating_workspace/`, `client/test/widgets/workbench/` | Cover resolvers, migration, bridge behavior |

---

### Task 1: Floating Run intent resolver (TDD)

**Files:**
- Modify: `client/lib/services/workbench/workbench_run_intent.dart`
- Modify: `client/test/services/workbench/workbench_run_intent_test.dart`

- [ ] **Step 1: Write failing tests for `resolveFloatingTabForRunIntent`**

Add tests covering:

```dart
test('run surface + activate → FloatingTab run surface', () {
  expect(
    resolveFloatingTabForRunIntent(
      const RunUiIntent(
        surface: RunToolSurface.run,
        activateToolWindow: true,
        focusToolWindow: false,
      ),
      runSessionId: 'r9',
      title: 'Build',
    ),
    FloatingTab(
      id: floatingRunTabId('r9'),
      surfaceId: 'run',
      title: 'Build',
      payload: 'r9',
    ),
  );
});

test('activateToolWindow false → null', () { /* ... */ });
test('empty runSessionId → null', () { /* ... */ });
test('terminal surface → null (use terminal resolver)', () { /* ... */ });
```

Also update/remove obsolete expectation that `resolveWorkbenchTabForRunIntent` returns `WorkbenchTabId.run` for run surface — change it to return `null` (center no longer owns Run).

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/workbench/workbench_run_intent_test.dart
```

Expected: FAIL (missing `resolveFloatingTabForRunIntent` / `floatingRunTabId`, or old run→center assertion).

- [ ] **Step 3: Implement resolver**

In `workbench_run_intent.dart`:

```dart
String floatingRunTabId(String runSessionId) => 'run:$runSessionId';

FloatingTab? resolveFloatingTabForRunIntent(
  RunUiIntent intent, {
  required String? runSessionId,
  required String title,
}) {
  if (!intent.activateToolWindow) return null;
  if (intent.surface != RunToolSurface.run) return null;
  final id = runSessionId?.trim();
  if (id == null || id.isEmpty) return null;
  final label = title.trim().isNotEmpty ? title.trim() : id;
  return FloatingTab(
    id: floatingRunTabId(id),
    surfaceId: 'run',
    title: label,
    payload: id,
  );
}
```

Change `resolveWorkbenchTabForRunIntent` so `RunToolSurface.run` also returns `null` (floating owns Run; keep function for compatibility or delete dead call sites later).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/workbench/workbench_run_intent_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workbench/workbench_run_intent.dart \
  client/test/services/workbench/workbench_run_intent_test.dart
git commit -m "$(cat <<'EOF'
feat(run): resolve RunUiIntent to floating run tabs

EOF
)"
```

---

### Task 2: `RunFloatingSurface` + registry wiring

**Files:**
- Create: `client/lib/services/floating_workspace/surfaces/run_floating_surface.dart`
- Modify: `client/lib/services/floating_workspace/floating_surface_registry.dart`
- Modify: `client/lib/app/app_shell.dart` (registry construction ~1522)
- Test: `client/test/services/floating_workspace/run_floating_surface_test.dart` (lightweight: tab id/title/payload)

- [ ] **Step 1: Write failing test for tab factory**

```dart
test('createTab builds run: id and payload', () {
  final surface = RunFloatingSurface(
    floating: FloatingWorkspaceCubit(),
    resolveTitle: (id) => id == 'r1' ? 'Script' : null,
    onDismiss: (_) async {},
  );
  final tab = surface.createTab(workspaceId: 'w1', payload: 'r1');
  expect(tab.id, 'run:r1');
  expect(tab.surfaceId, 'run');
  expect(tab.title, 'Script');
  expect(tab.payload, 'r1');
});
```

(Adjust constructor to match what you implement — prefer injecting title lookup + dismiss callback rather than requiring full `RunCubit` in unit test.)

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/floating_workspace/run_floating_surface_test.dart
```

- [ ] **Step 3: Implement surface**

Mirror `FilePreviewFloatingSurface` / `TerminalFloatingSurface`:

- `id => 'run'`
- `emptyAction => null` (runs are created by launcher, not empty-state CTA)
- `allowMultipleTabs => true`
- **`build` must provide `RunCubit`:** floating panel sits under `FloatingWorkspaceHost`, outside `WorkspaceSplitPane`'s `BlocProvider`. Wrap `RunPanel` with `BlocProvider.value` from `WorkspaceRunRegistry.cubitFor(tabScopeId: workspaceId, workspaceId: workspaceId, folders: ...)` (or inject a `RunCubit Function(String workspaceId)`). Without this, process-mode Run hits `ProviderNotFoundException`.
- `build` → that provider + `RunPanel(showChrome: false, activeSessionId: sessionId)` (same as `RunTabSurface`)
- Close: `canClose` may use `dismissRunSessionWithConfirm` when context present; ensure dismiss happens once (`canClose` **or** `onTabClosed`, not both).

Prefer: bridge always passes a complete `FloatingTab`; surface `createTab` is fallback only.

- [ ] **Step 4: Extend registry**

```dart
factory FloatingSurfaceRegistry.withDefaults({
  required FloatingSurface file,
  required FloatingSurface terminal,
  FloatingSurface? diff,
  FloatingSurface? run,
}) => FloatingSurfaceRegistry([
  terminal,
  file,
  if (diff != null) diff,
  if (run != null) run,
]);
```

Wire in `app_shell.dart` with a `RunFloatingSurface` that reads titles from the active workspace’s `RunCubit` via `WorkspaceRunRegistry` if available; if RunCubit is per-workspace and not global, inject a `String? Function(String sessionId) resolveTitle` that looks up from a callback set later, **or** read title from the floating tab already set by the bridge (surface `createTab` only used for empty-action paths — bridge can `ensureTab` with full `FloatingTab`). Simplest: bridge always passes complete `FloatingTab`; surface `createTab` is fallback; `build` only needs session id payload.

- [ ] **Step 5: Run tests — PASS; commit**

```bash
cd client && flutter test test/services/floating_workspace/run_floating_surface_test.dart
git add client/lib/services/floating_workspace/surfaces/run_floating_surface.dart \
  client/lib/services/floating_workspace/floating_surface_registry.dart \
  client/lib/app/app_shell.dart \
  client/test/services/floating_workspace/run_floating_surface_test.dart
git commit -m "$(cat <<'EOF'
feat(floating): add RunFloatingSurface for process logs

EOF
)"
```

---

### Task 3: Bridge routes run intents to floating + stop center reconcile

**Files:**
- Modify: `client/lib/widgets/workbench/workbench_shell_run_sync.dart`
- Modify: `client/lib/services/workbench/workbench_shell_run_sync_logic.dart`
- Modify: `client/test/services/workbench/workbench_shell_run_sync_logic_test.dart`
- Optional widget test: `client/test/widgets/workbench/workbench_shell_run_sync_test.dart`

- [ ] **Step 1: Update logic tests**

Change `planWorkbenchShellRunSync` expectations so `runIdsToEnsureAndSelect` / center run ensure are **empty always** (floating owns Run). Keep `runTabsToRemove` able to strip stale center run tabs (cleanup). Add helper used by bridge for floating reconcile, e.g.:

```dart
List<String> floatingRunIdsToEnsure({
  required Iterable<String> existingFloatingRunSessionIds,
  required Iterable<String> liveRunPanelSessionIds,
}) { /* live - existing */ }

List<String> floatingRunIdsToRemove({
  required Iterable<String> existingFloatingRunSessionIds,
  required Iterable<String> liveRunPanelSessionIds,
}) { /* existing - live */ }
```

- [ ] **Step 2: Run logic tests — FAIL then implement logic — PASS**

```bash
cd client && flutter test test/services/workbench/workbench_shell_run_sync_logic_test.dart
```

- [ ] **Step 3: Update `_onUiIntent` for run surface**

Replace center `WorkbenchCubit.ensureTab(WorkbenchTabId.run(...))` with:

```dart
final session = /* latest sessionUsesRunPanel or intent-correlated id */;
final tab = resolveFloatingTabForRunIntent(
  intent,
  runSessionId: session?.id,
  title: session?.owned.configuration.name ?? '',
);
if (tab != null) {
  floating.ensureOpen();
  floating.setActiveWorkspace(widget.workspaceId);
  floating.ensureTab(tab);
  floating.selectTab(tab.id);
}
```

Do **not** call `dismissNewChat`.

Preserve terminal branch + `focusToolWindow` → `holdHandle?.requestFocus()`.

- [ ] **Step 4: Update `_reconcile`**

- Remove center run `ensureTab` / `select` for new sessions.
- Still `workbench.removeTab` for any leftover center `WorkbenchTabKind.run` (cleanup).
- Ensure floating tabs for live `sessionUsesRunPanel` ids; remove floating run tabs whose sessions are gone (call floating `removeTab` + surface close pipeline carefully — prefer matching how terminal orphans are handled; if none, only remove floating tab id and let `RunCubit` own process lifetime until dismiss).

YAGNI: if floating orphan cleanup is risky, only ensure-on-intent + remove stale **center** run tabs in reconcile; rely on surface `onTabClosed` for user closes. Spec requires not creating center tabs — minimum is stop ensure+select on center.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/workbench/workbench_shell_run_sync.dart \
  client/lib/services/workbench/workbench_shell_run_sync_logic.dart \
  client/test/services/workbench/workbench_shell_run_sync_logic_test.dart
git commit -m "$(cat <<'EOF'
fix(run): sync Run sessions to floating tabs not center

EOF
)"
```

---

### Task 4: Hoist bridge to `WorkspaceSplitPane`

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart`

- [ ] **Step 1: Mount sync outside ChatPage**

In `WorkspaceSplitPane.build`, wrap `WorkspaceIdeShell` (or the `MultiBlocProvider` child) with:

```dart
WorkbenchShellRunSync(
  workspaceId: widget.workspace.workspaceId,
  tabScopeId: widget.tabScopeId,
  holdHandle: _terminalHold,
  child: WorkspaceIdeShell(...),
)
```

`RunCubit` is already provided above this point — good.

- [ ] **Step 2: Remove wrapper from `ChatPageShell`**

Delete the `WorkbenchShellRunSync(` nesting; keep `WorkbenchSessionSync` as today.

- [ ] **Step 3: Smoke test existing run/workbench tests**

```bash
cd client && flutter test \
  test/services/workbench/workbench_run_intent_test.dart \
  test/services/workbench/workbench_shell_run_sync_logic_test.dart \
  test/widgets/run/run_toolbar_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_split_pane.dart \
  client/lib/pages/chat/chat_page_shell.dart
git commit -m "$(cat <<'EOF'
fix(run): listen for RunUiIntent on landing and session

EOF
)"
```

---

### Task 5: Migrate leftover center Run tabs to floating

**Files:**
- Modify: `client/lib/services/floating_workspace/migrate_legacy_workbench_tabs.dart`
- Modify: `client/test/services/floating_workspace/migrate_legacy_workbench_tabs_test.dart`

- [ ] **Step 1: Failing test — center run tab migrates**

```dart
test('migrateLegacy moves run tabs to floating run surface', () {
  // seed WorkbenchCubit with WorkbenchTabId.run('r1')
  // migrateLegacyWorkbenchTabsToFloating(...)
  // expect workbench has no run tab
  // expect floating has FloatingTab id run:r1 surfaceId run
});
```

Also update any **existing** migration tests that currently assert center `run` tabs are preserved (e.g. `expect(..., [session, run])` / `moved == 2`) — those expectations will fail after this change.

- [ ] **Step 2: Implement — handle `WorkbenchTabKind.run` in switch**

```dart
case WorkbenchTabKind.run:
  floating.ensureTab(
    FloatingTab(
      id: floatingRunTabId(tab.id),
      surfaceId: 'run',
      title: tab.id,
      payload: tab.id,
    ),
  );
```

Update doc comment: run tabs migrate too. `syncFilePreviewHostTabs` already calls migrate for floating host — ensure run moves even when `migrateFiles` is false (run should always leave center). When migrating with `migrateFiles: false`, still include `WorkbenchTabKind.run` in the leftover filter.

- [ ] **Step 3: Tests PASS + commit**

```bash
cd client && flutter test test/services/floating_workspace/migrate_legacy_workbench_tabs_test.dart
git add client/lib/services/floating_workspace/migrate_legacy_workbench_tabs.dart \
  client/test/services/floating_workspace/migrate_legacy_workbench_tabs_test.dart
git commit -m "$(cat <<'EOF'
fix(floating): migrate center Run tabs into floating workspace

EOF
)"
```

---

### Task 6: Floating file/diff open must not dismiss compose

**Files:**
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`
- Modify: `client/test/services/workbench/workbench_editor_opener_test.dart`

- [ ] **Step 1: Failing test**

Assert that when `readFilePreviewInFloating` is true, `openFile` / `openDiff` do **not** call `dismissNewChat` (mock/spy ChatCubit, or track via fake). Center-host path may still dismiss if that is required for center strip — only floating paths must keep compose.

- [ ] **Step 2: Remove `_chat?.dismissNewChat()` from floating branches only** (~lines 72 and 117). Leave center-host dismiss as-is unless tests show compose break there too.

- [ ] **Step 3: PASS + commit**

```bash
cd client && flutter test test/services/workbench/workbench_editor_opener_test.dart
git add client/lib/services/workbench/workbench_editor_opener.dart \
  client/test/services/workbench/workbench_editor_opener_test.dart
git commit -m "$(cat <<'EOF'
fix(workbench): keep compose when opening floating file preview

EOF
)"
```

---

### Task 7: ChatPageShell projection cleanup + verification

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (stop building `runTitles` / center run projection if still present)
- Modify: `client/lib/services/workbench/workbench_body_keep_alive.dart` / `workbench_body.dart` only if center still mounts `RunTabSurface` for live runs — under new model, center should not keep-alive run sessions; floating surface hosts them.

- [ ] **Step 1: Grep for remaining center run coupling**

```bash
cd client && rg -n "WorkbenchTabKind\\.run|WorkbenchTabId\\.run|sessionUsesRunPanel|RunTabSurface" lib pages
```

Remove or dead-path any ensure of center run tabs. Keep close handlers for safety if stale tabs exist.

- [ ] **Step 2: Run focused + broader tests**

```bash
cd client && flutter test \
  test/services/workbench/ \
  test/services/floating_workspace/ \
  test/widgets/run/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Do **not** swallow failures (`|| true` / redirecting stderr). Also confirm `isCenterStripWorkbenchTab` / projection never treats `run` as a center strip citizen (same as `shell`).

- [ ] **Step 3: Manual checklist**

1. Open workspace on compose landing → Run shellScript → floating opens with terminal; center still compose.
2. Process-mode script (`executeInTerminal: false`) → floating Run tab with log.
3. Open file from tree with floating preview → floating file tab; compose stays.
4. Title-bar Stop still works.

- [ ] **Step 4: Final commit if cleanup remained**

```bash
git add -u client/lib client/test
git commit -m "$(cat <<'EOF'
chore(workbench): drop center Run projection leftovers

EOF
)"
```

---

## Execution notes

- Prefer **subagent-driven-development** per task with TDD.
- Do not push remotes unless asked.
- If `RunCubit` is not in scope for `RunFloatingSurface` at app_shell construct time, keep dismiss wiring thin: bridge opens tabs; surface `build` uses `context.read<RunCubit>()` from the workspace `BlocProvider` when the floating panel is under a tools-scope bridge — verify `FloatingWorkspaceToolsScopeBridge` exposes the active workspace `RunCubit`. If not, extend that bridge before Task 2 wiring.

## Done when

- Landing Run shows floating UI without leaving compose.
- Process Run logs appear as floating `run` tabs.
- No new center `WorkbenchTabKind.run` tabs are created.
- Floating file open does not dismiss compose.
- Listed tests pass.
