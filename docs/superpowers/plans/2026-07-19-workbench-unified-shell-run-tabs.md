# Workbench Unified Shell + Run Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the workspace bottom dock and host shell + Run as peer center workbench tabs (Orca-aligned), with keep-alive bodies and domain↔strip sync.

**Architecture:** Extend `WorkbenchTabKind` with `shell`/`run`. `WorkbenchCubit` owns strip order/selection/`lastFocusedShellTabId`. Domain state stays in `WorkspaceTerminalRegistry` + `RunCubit`. New `WorkbenchShellRunSync` passively mirrors registry/RunCubit into the strip. `WorkbenchBody` keep-alives shell/run surfaces. Delete `WorkspaceBottomDock` and bottom pane policy after center path works.

**Tech Stack:** Dart / Flutter (`flutter_bloc`, existing workbench + terminal + Run stacks); no new packages.

**Spec:** [`docs/superpowers/specs/2026-07-19-workbench-unified-shell-run-tabs-design.md`](../specs/2026-07-19-workbench-unified-shell-run-tabs-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Modify: `client/lib/cubits/workbench/workbench_tab.dart` | Add `shell` / `run` kinds + factories |
| Modify: `client/lib/cubits/workbench/workbench_cubit.dart` | `lastFocusedShellTabId` on bucket; update on shell `select`; helpers for most-recent shell |
| Modify: `client/test/cubits/workbench_cubit_test.dart` | Pin preview, syncSessions preserve, lastFocused |
| Create: `client/lib/services/workbench/workbench_run_intent.dart` | Pure: `WorkbenchTabId?` from `RunUiIntent` + latest run id; replace `dockTabForActivateIntent` |
| Create: `client/test/services/workbench/workbench_run_intent_test.dart` | Intent mapping tests (migrate from dock intent test) |
| Modify: `client/lib/services/workbench/workbench_tab_projection.dart` | Project shell/run `TabInfo` (icons, titles, `pinnable: false`) |
| Modify: `client/test/services/workbench/workbench_tab_projection_test.dart` | Shell/run rows |
| Modify: `client/lib/services/workbench/workbench_shell_actions.dart` | select/close/bulk for shell+run; update lastFocused |
| Create: `client/lib/pages/workbench/shell_terminal_surface.dart` | Single-entry terminal body (extract from panel; no dock chips) |
| Create: `client/lib/pages/workbench/run_tab_surface.dart` | Thin wrapper: `RunPanel(showChrome: false)` for one session |
| Modify: `client/lib/pages/workbench/workbench_body.dart` | Keep-alive stack for shell/run + kind switch |
| Create: `client/lib/widgets/workbench/workbench_shell_run_sync.dart` | Passive ensure/select/remove; peer to `WorkbenchSessionSync` |
| Create: `client/test/widgets/workbench/workbench_shell_run_sync_test.dart` | Passive ensure/remove (widget or cubit+fake listenables) |
| Modify: `client/lib/pages/chat/chat_page_shell.dart` | Pass shell/run titles into projection; `+` menu; mount sync |
| Modify: `client/lib/pages/workspace_shell/workspace_shell.dart` (+ new chat button) | Support `+` menu (new chat + new terminal) |
| Modify: `client/lib/services/commands/layout_command_registrar.dart` | `togglePanel` → create-or-focus shell |
| Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Remove dock; re-home hold to center shell; explicit `clearWorkspace` on close paths as needed |
| Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Drop bottom split / dockBottom |
| Modify: `client/lib/services/workspace/workspace_pane_policy.dart` | Remove `dockBottom` |
| Modify: `client/lib/cubits/layout_cubit.dart` + `layout_preferences.dart` | Deprecate `workspaceTerminalVisible` (ignore UI; stop writing) |
| Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Remove bottom dock visibility toggle |
| Delete: `client/lib/widgets/workspace_bottom_dock.dart`, `workspace_dock_tab.dart` | After center path green |
| Delete/rewrite: `client/test/widgets/workspace_bottom_dock_intent_test.dart` | Move to `workbench_run_intent_test.dart` |
| Modify: `client/lib/models/run/run_ui_intent.dart` | Comments: workbench tab, not bottom dock |
| l10n as needed | `+` menu strings if missing |

**Out of scope:** floating workspace; TabGroup splits; New Run in `+`; shell inside session members.

---

### Task 1: Tab kinds + `lastFocusedShellTabId`

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_tab.dart`
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`
- Modify: `client/test/cubits/workbench_cubit_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('shell/run factories and equality', () {
  final a = WorkbenchTabId.shell('e1');
  final b = WorkbenchTabId.shell('e1');
  final c = WorkbenchTabId.run('r1');
  expect(a, b);
  expect(a.kind, WorkbenchTabKind.shell);
  expect(c.kind, WorkbenchTabKind.run);
  expect(a, isNot(c));
});

test('ensureTab shell/run ignores preview flag (never enters preview set)', () {
  const ws = 'ws';
  final session = WorkbenchTabId.session('s1');
  cubit.ensureTab(ws, session, preview: true);
  expect(cubit.isPreview(ws, session), isTrue);

  final shell = WorkbenchTabId.shell('e1');
  cubit.ensureTab(ws, shell, preview: true);
  expect(cubit.isPreview(ws, shell), isFalse);
  expect(cubit.isPreview(ws, session), isTrue); // not displaced
});

test('syncSessions preserves shell/run tabs', () {
  const ws = 'ws';
  final s1 = WorkbenchTabId.session('s1');
  final shell = WorkbenchTabId.shell('e1');
  final run = WorkbenchTabId.run('r1');
  cubit.ensureTab(ws, s1);
  cubit.ensureTab(ws, shell);
  cubit.ensureTab(ws, run);
  cubit.syncSessions(ws, ['s1', 's2']);
  expect(cubit.tabOrder(ws), containsAll([shell, run, WorkbenchTabId.session('s2')]));
  expect(cubit.tabOrder(ws), contains(shell));
});

test('select shell updates lastFocusedShellTabId; resolveMostRecentShell', () {
  const ws = 'ws';
  final e1 = WorkbenchTabId.shell('e1');
  final e2 = WorkbenchTabId.shell('e2');
  cubit.ensureTab(ws, e1);
  cubit.ensureTab(ws, e2);
  cubit.select(ws, e1);
  expect(cubit.lastFocusedShellTabId(ws), e1);
  cubit.select(ws, WorkbenchTabId.session('s1')); // if needed ensure session first
  expect(cubit.resolveMostRecentShell(ws), e1);
});
```

- [ ] **Step 2: Run tests — expect FAIL** (missing kinds / methods)

```bash
cd client && flutter test test/cubits/workbench_cubit_test.dart
```

- [ ] **Step 3: Implement**

In `workbench_tab.dart`:

```dart
enum WorkbenchTabKind { session, file, diff, shell, run }

factory WorkbenchTabId.shell(String entryId) =>
    WorkbenchTabId._(WorkbenchTabKind.shell, entryId);

factory WorkbenchTabId.run(String runSessionId) =>
    WorkbenchTabId._(WorkbenchTabKind.run, runSessionId);
```

In `WorkbenchWorkspaceState`: add `WorkbenchTabId? lastFocusedShellTabId`.

In `ensureTab`: if `tab.kind` is `shell` or `run`, force `preview = false` (do not add to `previewTabIds`, do not replace existing preview).

In `select`: if `tab.kind == shell`, set `lastFocusedShellTabId = tab`.

Add:

```dart
WorkbenchTabId? lastFocusedShellTabId(String workspaceId) =>
    state.bucket(workspaceId).lastFocusedShellTabId;

WorkbenchTabId? resolveMostRecentShell(String workspaceId) {
  final bucket = state.bucket(workspaceId);
  final last = bucket.lastFocusedShellTabId;
  if (last != null &&
      last.kind == WorkbenchTabKind.shell &&
      bucket.tabOrder.contains(last)) {
    return last;
  }
  for (var i = bucket.tabOrder.length - 1; i >= 0; i--) {
    if (bucket.tabOrder[i].kind == WorkbenchTabKind.shell) {
      return bucket.tabOrder[i];
    }
  }
  return null;
}
```

Fix all exhaustive `switch (tab.kind)` compile breaks with `TODO` stubs only where required to compile tests (prefer completing switches in Task 3–4).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/cubits/workbench_cubit_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/workbench/workbench_tab.dart \
  client/lib/cubits/workbench/workbench_cubit.dart \
  client/test/cubits/workbench_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(workbench): add shell/run tab kinds and lastFocusedShell

EOF
)"
```

---

### Task 2: RunUiIntent → workbench tab mapper

**Files:**
- Create: `client/lib/services/workbench/workbench_run_intent.dart`
- Create: `client/test/services/workbench/workbench_run_intent_test.dart`
- Delete later: `client/test/widgets/workspace_bottom_dock_intent_test.dart` (migrate assertions here in this task)

- [ ] **Step 1: Write failing tests**

```dart
test('activate false → null', () {
  expect(
    resolveWorkbenchTabForRunIntent(
      const RunUiIntent(
        surface: RunToolSurface.run,
        activateToolWindow: false,
        focusToolWindow: false,
      ),
      latestRunSessionId: 'r9',
    ),
    isNull,
  );
});

test('run surface → latest run tab', () {
  expect(
    resolveWorkbenchTabForRunIntent(
      const RunUiIntent(
        surface: RunToolSurface.run,
        activateToolWindow: true,
        focusToolWindow: false,
      ),
      latestRunSessionId: 'r9',
    ),
    WorkbenchTabId.run('r9'),
  );
});

test('terminal surface → shell(terminalEntryId)', () {
  expect(
    resolveWorkbenchTabForRunIntent(
      const RunUiIntent(
        surface: RunToolSurface.terminal,
        activateToolWindow: true,
        focusToolWindow: true,
        terminalEntryId: 'e1',
      ),
      latestRunSessionId: null,
    ),
    WorkbenchTabId.shell('e1'),
  );
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/workbench/workbench_run_intent_test.dart
```

- [ ] **Step 3: Implement**

```dart
WorkbenchTabId? resolveWorkbenchTabForRunIntent(
  RunUiIntent intent, {
  required String? latestRunSessionId,
}) {
  if (!intent.activateToolWindow) return null;
  switch (intent.surface) {
    case RunToolSurface.terminal:
      final id = intent.terminalEntryId?.trim();
      if (id == null || id.isEmpty) return null;
      return WorkbenchTabId.shell(id);
    case RunToolSurface.run:
      final id = latestRunSessionId?.trim();
      if (id == null || id.isEmpty) return null;
      return WorkbenchTabId.run(id);
  }
}
```

Update `run_ui_intent.dart` comments to say workbench tab (not bottom dock).

- [ ] **Step 4: PASS + remove old dock intent test file (or make it re-export/delete)**

```bash
cd client && flutter test test/services/workbench/workbench_run_intent_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workbench): map RunUiIntent to shell/run WorkbenchTabId

EOF
)"
```

---

### Task 3: Tab projection for shell/run

**Files:**
- Modify: `client/lib/services/workbench/workbench_tab_projection.dart`
- Modify: `client/test/services/workbench/workbench_tab_projection_test.dart`

- [ ] **Step 1: Failing test** — `projectWorkbenchTabs` includes shell title/icon and run title/icon; `pinnable` false / not preview.

Add optional maps:

```dart
Map<String, String> shellTitles = const {},
Map<String, String> runTitles = const {},
Map<String, bool> runWorking = const {}, // optional spinner
```

- [ ] **Step 2: Implement switch arms**

```dart
WorkbenchTabKind.shell => TabInfo(
  id: tab.id,
  title: shellTitles[tab.id] ?? tab.id,
  icon: Icons.terminal_outlined, // distinct from session Icons.terminal_rounded if possible
  pinnable: false,
),
WorkbenchTabKind.run => TabInfo(
  id: tab.id,
  title: runTitles[tab.id] ?? tab.id,
  icon: Icons.play_arrow_rounded,
  working: runWorking[tab.id] ?? false,
  pinnable: false,
),
```

- [ ] **Step 3: Tests PASS + commit**

```bash
cd client && flutter test test/services/workbench/workbench_tab_projection_test.dart
git commit -m "$(cat <<'EOF'
feat(workbench): project shell and run tabs into strip

EOF
)"
```

---

### Task 4: `WorkbenchShellActions` for shell/run

**Files:**
- Modify: `client/lib/services/workbench/workbench_shell_actions.dart`
- Create: `client/test/services/workbench/workbench_shell_actions_shell_run_test.dart` (prefer testing pure teardown helpers if UI dismiss is hard; otherwise mock registry via injection)

- [ ] **Step 1: Extend `select`**

After `workbench.select`, if `tab.kind == shell`, lastFocused already updated in cubit. Exit compose as today. Do **not** call `chat.selectTab` for shell/run.

- [ ] **Step 2: Extend `closeAt` / `_closeDomainOnly`**

```dart
case WorkbenchTabKind.shell:
  final registry = context.read<WorkspaceTerminalRegistry>();
  // Use tabScopeId — same key dock/panel pass to groupFor today.
  final group = registry.groupFor(tabScopeId);
  context.read<WorkspaceTerminalRunService>().handleEntryClosed(tab.id);
  group.removeEntry(tab.id);
  workbench.removeTab(workspaceId, tab); // closeAt only
case WorkbenchTabKind.run:
  final runCubit = context.read<RunCubit>();
  final session = runCubit.state.sessions.cast<RunSession?>().firstWhere(
    (s) => s?.id == tab.id,
    orElse: () => null,
  );
  if (session != null) {
    final ok = await dismissRunSessionWithConfirm(...);
    if (!ok) return;
  }
  workbench.removeTab(workspaceId, tab);
```

For `_closeDomainOnly` (bulk): dispose shell without confirm; for run call `RunCubit.dismissSession` (no dialog), matching editor force-close. Reserve `dismissRunSessionWithConfirm` for single-tab `closeAt` only.

- [ ] **Step 3: Exhaustive switches compile; add a focused unit test if extractable**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workbench): close and select shell/run workbench tabs

EOF
)"
```

---

### Task 5: `WorkbenchShellRunSync` (passive ensure/select/remove)

**Files:**
- Create: `client/lib/widgets/workbench/workbench_shell_run_sync.dart`
- Create: `client/test/widgets/workbench/workbench_shell_run_sync_test.dart` (or service-level pure sync functions + thin widget)

Prefer extracting pure functions for testability:

```dart
// workbench_shell_run_sync_logic.dart
Set<String> shellIdsToEnsure(...);
List<WorkbenchTabId> shellTabsToRemove(...);
// run: added ids that use RunPanel → ensure+select last
```

Move `_sessionUsesRunPanel` from `workspace_bottom_dock.dart` into a shared helper (e.g. `run_panel_session.dart`).

- [ ] **Step 1: Failing tests for pure sync**

- New registry entry ids not in tabOrder → ensure shell (no select flag)
- New RunPanel session → ensure run + select that id
- Registry missing entry still in tabOrder → removeTab
- Run session gone → removeTab
- `activateToolWindow: false` shell still ensured (no select)

- [ ] **Step 2: Implement sync widget**

Listen to:
- `WorkspaceTerminalRegistry.groupFor(tabScopeId)` (`Listenable`) — same key the dock passes today
- `RunCubit` stream/bloc
- `RunCubit.uiIntents` → `resolveWorkbenchTabForRunIntent` → ensure+select; on terminal surface also `holdHandle?.selectEntry(entryId)` and when `focusToolWindow` → `holdHandle?.requestFocus()` (port dock `_onUiIntent`; **in-scope here**, not optional)

Mount next to `WorkbenchSessionSync` in `chat_page_shell.dart`. Until Task 8 deletes the dock, do **not** leave dock `_active` as a second selection owner — prefer removing dock selection usage as soon as sync mounts (or delete dock in the same PR slice).

Wire `shellTitles` via `WorkspaceTerminalTitleResolver` / entry `titleLabel` and `runTitles` from `RunCubit` sessions into `projectWorkbenchTabs` from `chat_page_shell.dart`.

- [ ] **Step 3: Title-bar close**

In `home_workspace_shell.dart` `_closeTab` (alongside `terminalRegistry.disposeWorkspace(tab.tabKey)`), call `workbench.clearWorkspace(...)` with the **same key** as the workbench bucket for that title-bar tab.

- [ ] **Step 4: Tests PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workbench): sync shell and run domain state into tab strip

EOF
)"
```

---

### Task 6: Body surfaces + keep-alive

**Files:**
- Create: `client/lib/pages/workbench/shell_terminal_surface.dart`
- Create: `client/lib/pages/workbench/run_tab_surface.dart`
- Modify: `client/lib/pages/workbench/workbench_body.dart`
- Re-home hold: `workspace_split_pane.dart` / `workspace_ide_shell.dart`

- [ ] **Step 1: Extract shell surface**

Single `WorkspaceTerminalEntry` view: reuse connect/theme pieces from `WorkspaceTerminalPanel` / dock body **without** dock header chips. Accept `entryId`, `workspaceId`, `holdHandle`.

- [ ] **Step 2: `RunTabSurface`**

```dart
RunPanel(showChrome: false, /* bind to session id */);
```

(Inspect `RunPanel` API — may already take active session from cubit; if so, ensure selecting run tab sets whatever RunCubit needs, or pass session id explicitly.)

- [ ] **Step 3: Keep-alive in `WorkbenchBody`**

Do **not** only `switch` and dispose off-tree. Pattern:

```dart
// Pseudocode
return Stack(
  children: [
    // active non-shell/run kinds as today OR Offstage
    if (active?.kind == session) ChatWorkbench(...),
    ...
    // Keep all open shell/run tabs mounted:
    for (final id in shellEntryIds)
      Offstage(
        offstage: active != WorkbenchTabId.shell(id),
        child: ShellTerminalSurface(entryId: id, ...),
      ),
    for (final id in runIds)
      Offstage(
        offstage: active != WorkbenchTabId.run(id),
        child: RunTabSurface(sessionId: id, ...),
      ),
  ],
);
```

Derive `shellEntryIds` / `runIds` from `workbench.tabOrder` filtered by kind (or registry/cubit — prefer tabOrder ∩ live domain).

- [ ] **Step 4: Wire `WorkspaceTerminalHoldHandle`**

Keep owning `_terminalHold` in `WorkspaceSplitPane`. Pass into center body / shell surfaces. Wire IDE shell split-drag `onHold` to `_terminalHold` the same way bottom dock did (grep `terminalHold` / `beginHold` in `workspace_ide_shell.dart`).

- [ ] **Step 5: Manual smoke note in commit; optional golden not required**

```bash
git commit -m "$(cat <<'EOF'
feat(workbench): render keep-alive shell and run center surfaces

EOF
)"
```

---

### Task 7: Strip `+` menu + create shell entrypoint

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart` / `WorkspaceShellNewChatButton`
- Modify: `client/lib/pages/chat/chat_page_shell.dart`
- Reuse: `client/lib/widgets/workspace_terminal/workspace_terminal_new_session_menu.dart`
- l10n: `app_en.arb` / `app_zh.arb` if new strings needed

- [ ] **Step 1: Change `+` to menu**

Items:
1. New conversation → existing `clearActive` + `enterComposeMode`
2. New terminal → show `WorkspaceTerminalNewSessionMenu` → `WorkspaceTerminalSessionOps.openEntry` (default local / SSH / WSL) → sync will `ensureTab`; also `workbench.ensureTab`+`select` immediately for snappy UX

- [ ] **Step 2: `togglePanel` command**

In `layout_command_registrar.dart` (stop calling `toggleWorkspaceTerminal`):

```dart
bus.register(CommandIds.togglePanel, () async {
  // resolve active workspaceId from LayoutCubit / AppKeys
  final workbench = ...;
  final existing = workbench.resolveMostRecentShell(workspaceId);
  if (existing != null) {
    workbench.select(workspaceId, existing);
    return;
  }
  await WorkspaceTerminalSessionOps().openEntry( /* default local spec */ );
  // sync/select
});
```

Need a small `WorkbenchShellLauncher` service if context-less command bus cannot open menus — mirror how other commands get workspace cwd.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workbench): add new-terminal to strip menu and retarget togglePanel

EOF
)"
```

---

### Task 8: Remove bottom dock and layout chrome

**Files:**
- Modify: `workspace_split_pane.dart` — remove `WorkspaceBottomDock` child
- Modify: `workspace_ide_shell.dart` — no bottom pane
- Modify: `workspace_pane_policy.dart` — drop `dockBottom`
- Modify: `workspace_shell_tabs.dart` — remove `WorkspaceShellBottomDockVisibilityToggle`
- Modify: `layout_cubit.dart` / `layout_preferences.dart` — stop UI writes to `workspaceTerminalVisible`; read may default false
- Delete: `workspace_bottom_dock.dart`, `workspace_dock_tab.dart`
- Fix all imports / analyzes

- [ ] **Step 1: Remove dock mount; keep app compiling**

- [ ] **Step 2: Delete dead types; update pane sync tests if any**

- [ ] **Step 3: Full analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/cubits/workbench_cubit_test.dart \
  test/services/workbench/ \
  test/widgets/workbench/ \
  --exclude-tags integration
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(workbench): remove workspace bottom dock

EOF
)"
```

---

### Task 9: Verification + manual smoke checklist

- [ ] **Step 1: Automated**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 2: Manual smoke (record results in PR / notes)**

- [ ] New shell from `+` → center tab; no bottom bar
- [ ] Local / SSH / WSL shell; switch to session and back — PTY still connected
- [ ] Start Run config → run tab selected (steals focus)
- [ ] Shell script with `activateToolWindow: false` → shell tab appears, does not steal focus
- [ ] Close shell tab → entry disposed
- [ ] Close run with confirm
- [ ] Close Others / Close to the Right with mixed kinds
- [ ] `togglePanel` shortcut: create then focus
- [ ] Close title-bar workspace and reopen — no stale shell/run tabs
- [ ] Sidebar/right-tools drag — PTY resize hold still works

- [ ] **Step 3: Final commit if smoke fixes needed**

---

## Execution notes

- Prefer **no dual selection owners**: once strip owns shell/run, do not leave dock `_active` alive.
- `syncSessions` already keeps non-session tabs — Task 1 tests lock this after adding kinds.
- Registry / RunCubit scope key: use `tabScopeId` as passed into the split pane (dock today passes this into `groupFor` even when the parameter is named `workspaceId`).
- When retargeting `togglePanel`, update `layout_command_registrar_test.dart` / any layout tests that assert `workspaceTerminalVisible`.
- Follow `@superpowers:test-driven-development` per task; use `@superpowers:subagent-driven-development` or `@superpowers:executing-plans` for execution.
