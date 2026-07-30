# Floating Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Orca-style in-app Floating Workspace overlay that hosts file preview and workspace terminal, migrating those surfaces off the center workbench strip while session/diff/run stay put.

**Architecture:** `FloatingWorkspaceCubit` owns panel visibility/geometry/tabs; pluggable `FloatingSurface`s activate domain services (`EditorCubit`, `WorkspaceTerminalRegistry`). `WorkbenchEditorOpener.openFile` and `WorkbenchShellLauncher` stop creating center `file`/`shell` tabs and instead open floating surfaces. Mount `FloatingWorkspaceHost` on `HomeShell`.

**Tech Stack:** Dart / Flutter, `flutter_bloc`, existing `CommandBus` / `ShortcutDispatcher`, `shared_ui` (`Tp*`), `LayoutPreferences` persistence.

**Spec:** `docs/superpowers/specs/2026-07-30-floating-workspace-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/cubits/floating_workspace/floating_panel_visibility.dart` | `FloatingPanelVisibility` enum |
| `client/lib/cubits/floating_workspace/floating_workspace_state.dart` | State, bucket, tab models |
| `client/lib/cubits/floating_workspace/floating_workspace_cubit.dart` | Visibility, bounds, tabs, workspace binding |
| `client/lib/services/floating_workspace/floating_surface.dart` | `FloatingSurface` + `FloatingEmptyAction` contracts |
| `client/lib/services/floating_workspace/floating_surface_registry.dart` | Built-in surface registration |
| `client/lib/services/floating_workspace/floating_workspace_commands.dart` | CommandBus registration |
| `client/lib/services/floating_workspace/floating_workspace_persistence.dart` | Read/write bounds + toggle into `LayoutCubit` / prefs |
| `client/lib/services/floating_workspace/surfaces/file_preview_floating_surface.dart` | File tab → `EditorCubit` + `FileEditorSurface` |
| `client/lib/services/floating_workspace/surfaces/terminal_floating_surface.dart` | Shell tab → terminal view widgets |
| `client/lib/pages/floating_workspace/floating_workspace_host.dart` | Stacks panel + toggle over shell |
| `client/lib/pages/floating_workspace/floating_workspace_panel.dart` | Drag/resize/chrome/content |
| `client/lib/pages/floating_workspace/floating_workspace_toggle.dart` | Bottom-right trigger |
| `client/lib/pages/floating_workspace/floating_workspace_empty.dart` | Empty-state action list |
| `client/lib/pages/floating_workspace/floating_workspace_chrome.dart` | Maximize / minimize controls |
| `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart` | Floating tab strip |
| `client/lib/services/commands/command_ids.dart` | New `floatingWorkspace.*` ids |
| `client/lib/services/commands/command_catalog.dart` | Catalog + default keybindings |
| `client/lib/models/layout_preferences.dart` | Persist floating geometry fields |
| `client/lib/services/workbench/workbench_editor_opener.dart` | Redirect `openFile` to floating |
| `client/lib/services/workbench/workbench_shell_launcher.dart` | Redirect shell create/focus to floating |
| `client/lib/services/workbench/workbench_shell_run_sync_logic.dart` | Stop projecting `shell` onto center strip |
| `client/lib/services/workbench/workbench_tab_projection.dart` | Optionally filter file/shell (defense in depth) |
| `client/lib/pages/workbench/file_editor_surface.dart` | Dirty pin → floating tab (not workbench file) |
| `client/lib/pages/home_workspace/home_workspace_shell.dart` | Mount host |
| `client/lib/app/app_shell.dart` | DI: cubit, registry, commands |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Empty-state + chrome strings |
| Tests under `client/test/cubits/floating_workspace/` and `client/test/services/floating_workspace/` | Cubit, opener redirect, shell redirect, registry |

**Shell tab sync policy (fixed):** Floating terminal tabs are created **only** via explicit paths (`floatingWorkspace.newTerminal`, redirected `WorkbenchShellLauncher`, RM host navigation). Do **not** auto-ensure center `shell` tabs. After migration, `WorkbenchShellRunSync` must **stop** adding/removing center `shell` tabs; run-tab sync stays. Floating bucket is the sole UI list for shells.

**Maximize safe area (fixed):** Do **not** maximize against the outer `HomeShell` stack alone (that would cover the workspace sidebar). Provide a `FloatingMaximizeInsets` (or `ValueNotifier<EdgeInsets>`) updated from `WorkspaceSplitPane` / `WorkspaceIdeShell` with the center+tools content rect (or left inset = sidebar width when visible). `FloatingWorkspacePanel` maximize uses that inset relative to the host overlay. If no workspace page is active, fall back to full `HomeShell` body below the title bar.

**Default shortcuts (v1):**

| Command | Default |
|---------|---------|
| `floatingWorkspace.toggle` | Linux/Win `Ctrl+Alt+A`; macOS `Cmd+Opt+A` |
| `floatingWorkspace.maximize` | Unbound on Linux/Win; macOS `Cmd+Opt+Shift+A` (Orca-like) |
| `floatingWorkspace.minimize` | Unbound (chrome + empty row still call command) |
| `floatingWorkspace.newTerminal` | Reuse existing `togglePanel` binding **or** register as alias handler — empty keycap shows `togglePanel` effective combo until a dedicated binding exists |
| `floatingWorkspace.openFile` | Unbound in v1 (empty row still works via click; keycap may be empty) |

Keep `CommandIds.togglePanel` registered; its handler calls `floatingWorkspace.newTerminal` path (ensure open + focus/create shell) so welcome page / cheatsheet keep working.

---

### Task 1: Visibility + state + cubit core (TDD)

**Files:**
- Create: `client/lib/cubits/floating_workspace/floating_panel_visibility.dart`
- Create: `client/lib/cubits/floating_workspace/floating_workspace_state.dart`
- Create: `client/lib/cubits/floating_workspace/floating_workspace_cubit.dart`
- Create: `client/test/cubits/floating_workspace/floating_workspace_cubit_test.dart`

- [ ] **Step 1: Write failing cubit tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_state.dart';

void main() {
  test('toggle open ↔ minimized; maximize only while open', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    expect(cubit.state.visibility, FloatingPanelVisibility.hidden);
    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.open);

    cubit.setMaximized(true);
    expect(cubit.state.isMaximized, isTrue);

    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.minimized);
    expect(cubit.state.isMaximized, isTrue); // retained while minimized

    cubit.toggle();
    expect(cubit.state.visibility, FloatingPanelVisibility.open);
    expect(cubit.state.isMaximized, isTrue);
  });

  test('ensureTab is per-workspace; setActiveWorkspace swaps bucket view', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);

    cubit.setActiveWorkspace('ws-a');
    cubit.ensureOpen();
    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    cubit.setActiveWorkspace('ws-b');
    expect(cubit.state.activeBucket.tabs, isEmpty);
    cubit.setActiveWorkspace('ws-a');
    expect(cubit.state.activeBucket.tabs.single.id, 'f1');
  });

  test('minimizeWithNoTabsGoesHidden when bucket empty', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.ensureOpen();
    cubit.minimize(closeIfEmpty: true);
    expect(cubit.state.visibility, FloatingPanelVisibility.hidden);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL (library missing)**

```bash
cd client && flutter test test/cubits/floating_workspace/floating_workspace_cubit_test.dart
```

Expected: compilation failure / missing types.

- [ ] **Step 3: Implement minimal cubit + state**

```dart
enum FloatingPanelVisibility { hidden, open, minimized }

class FloatingTab {
  const FloatingTab({
    required this.id,
    required this.surfaceId,
    required this.title,
    this.payload,
  });
  final String id;
  final String surfaceId;
  final String title;
  final Object? payload;
}

class FloatingWorkspaceBucket {
  const FloatingWorkspaceBucket({
    this.tabs = const [],
    this.activeTabId,
  });
  final List<FloatingTab> tabs;
  final String? activeTabId;
  // copyWith…
}

class FloatingWorkspaceState {
  const FloatingWorkspaceState({
    this.visibility = FloatingPanelVisibility.hidden,
    this.isMaximized = false,
    this.activeWorkspaceId = '',
    this.buckets = const {},
    this.panelBounds = const Rect.fromLTWH(80, 80, 720, 480),
    this.toggleOffset = const Offset(-24, -24), // from bottom-right
    this.attention = false,
  });
  // fields + copyWith + activeBucket getter…
}

class FloatingWorkspaceCubit extends Cubit<FloatingWorkspaceState> {
  FloatingWorkspaceCubit() : super(const FloatingWorkspaceState());

  void toggle() { /* open↔minimized; hidden→open */ }
  void ensureOpen() { /* visibility = open */ }
  void minimize({bool closeIfEmpty = false}) { /* … */ }
  void setMaximized(bool value) { /* … */ }
  void setActiveWorkspace(String id) { /* … */ }
  void ensureTab(FloatingTab tab) { /* upsert + active */ }
  void selectTab(String tabId) { /* … */ }
  void removeTab(String tabId) { /* … */ }
  void setPanelBounds(Rect r) { /* … */ }
  void setToggleOffset(Offset o) { /* … */ }
  void setAttention(bool v) { /* … */ }
  void disposeWorkspace(String workspaceId) { /* drop bucket */ }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/cubits/floating_workspace/floating_workspace_cubit_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/floating_workspace/ \
  client/test/cubits/floating_workspace/
git commit -m "$(cat <<'EOF'
feat(floating_workspace): add visibility state and cubit core

EOF
)"
```

---

### Task 2: Surface contract + registry (TDD)

**Files:**
- Create: `client/lib/services/floating_workspace/floating_surface.dart`
- Create: `client/lib/services/floating_workspace/floating_surface_registry.dart`
- Create: `client/test/services/floating_workspace/floating_surface_registry_test.dart`

- [ ] **Step 1: Failing test — empty actions order**

```dart
test('built-in registry empty actions are terminal, openFile, then none for minimize-only chrome', () {
  final registry = FloatingSurfaceRegistry.withDefaults(
    file: _FakeSurface(id: 'filePreview', emptyLabel: 'openFile'),
    terminal: _FakeSurface(id: 'terminal', emptyLabel: 'newTerminal'),
  );
  expect(
    registry.emptyActions.map((a) => a.commandId).toList(),
    ['floatingWorkspace.newTerminal', 'floatingWorkspace.openFile'],
  );
});
```

Minimize is a chrome/command action, **not** a `FloatingSurface.emptyAction` (matches Orca list but minimize is panel-owned). Empty UI concatenates `registry.emptyActions` + minimize row.

- [ ] **Step 2: Implement contract + registry**

```dart
class FloatingEmptyAction {
  const FloatingEmptyAction({
    required this.commandId,
    required this.labelKey, // l10n key or AppLocalizations getter name
    required this.icon,
  });
  final String commandId;
  final String labelKey;
  final IconData icon;
}

abstract class FloatingSurface {
  String get id;
  FloatingEmptyAction? get emptyAction;
  bool get allowMultipleTabs;
  FloatingTab createTab({required String workspaceId, Object? payload});
  Widget build(BuildContext context, FloatingTab tab);
  Future<void> activate(FloatingTab tab);
  Future<bool> canClose(FloatingTab tab) async => true;
  void onTabClosed(FloatingTab tab) {}
  Stream<bool>? get attentionWhileMinimized => null;
}

class FloatingSurfaceRegistry {
  FloatingSurfaceRegistry(List<FloatingSurface> surfaces)
      : _byId = {for (final s in surfaces) s.id: s};

  factory FloatingSurfaceRegistry.withDefaults({
    required FloatingSurface file,
    required FloatingSurface terminal,
  }) => FloatingSurfaceRegistry([terminal, file]); // terminal first for empty order

  final Map<String, FloatingSurface> _byId;
  FloatingSurface? operator [](String id) => _byId[id];
  List<FloatingEmptyAction> get emptyActions => [
    for (final s in _byId.values)
      if (s.emptyAction != null) s.emptyAction!,
  ];
}
```

- [ ] **Step 3: PASS + Commit**

```bash
cd client && flutter test test/services/floating_workspace/floating_surface_registry_test.dart
git add client/lib/services/floating_workspace/floating_surface.dart \
  client/lib/services/floating_workspace/floating_surface_registry.dart \
  client/test/services/floating_workspace/floating_surface_registry_test.dart
git commit -m "$(cat <<'EOF'
feat(floating_workspace): add FloatingSurface registry

EOF
)"
```

---

### Task 3: LayoutPreferences persistence fields

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart` (setters that `_save`)
- Create or modify: existing layout preferences tests if present
- Create: `client/lib/services/floating_workspace/floating_workspace_persistence.dart`

- [ ] **Step 1: Add fields + JSON round-trip test**

Add to `LayoutPreferences`:

```dart
final double? floatingPanelLeft;
final double? floatingPanelTop;
final double? floatingPanelWidth;
final double? floatingPanelHeight;
final double? floatingToggleDx; // from bottom-right
final double? floatingToggleDy;
final bool floatingMaximized;
```

Defaults: all null → cubit uses built-in defaults; `floatingMaximized: false`.

- [ ] **Step 2: Implement `FloatingWorkspacePersistence.bind(LayoutCubit, FloatingWorkspaceCubit)`**

On cubit geometry changes → write prefs. On layout load → hydrate cubit once.

- [ ] **Step 3: Commit**

```bash
git add client/lib/models/layout_preferences.dart \
  client/lib/cubits/layout_cubit.dart \
  client/lib/services/floating_workspace/floating_workspace_persistence.dart \
  client/test/**/*layout*  # if updated
git commit -m "$(cat <<'EOF'
feat(layout): persist floating workspace geometry

EOF
)"
```

---

### Task 4: Command ids + registrar

**Files:**
- Modify: `client/lib/services/commands/command_ids.dart`
- Modify: `client/lib/services/commands/command_catalog.dart`
- Create: `client/lib/services/floating_workspace/floating_workspace_commands.dart`
- Modify: `client/lib/services/commands/layout_command_registrar.dart` (doc comment: togglePanel → floating shell)
- Modify: `client/lib/app/app_shell.dart` (construct `FloatingWorkspaceCubit` **before** registering floating + layout commands; Provide later in Task 9 is fine as long as the same instance is used)

- [ ] **Step 1: Add command ids**

```dart
static const String floatingToggle = 'floatingWorkspace.toggle';
static const String floatingMaximize = 'floatingWorkspace.maximize';
static const String floatingMinimize = 'floatingWorkspace.minimize';
static const String floatingNewTerminal = 'floatingWorkspace.newTerminal';
static const String floatingOpenFile = 'floatingWorkspace.openFile';
```

- [ ] **Step 2: `registerFloatingWorkspaceCommands`**

Handlers:
- toggle / maximize / minimize → cubit
- newTerminal → ensureOpen + shell surface activate (callback injected)
- openFile → ensureOpen + file picker callback
- Keep `CommandIds.togglePanel` → same as `floatingNewTerminal`

- [ ] **Step 3: Catalog entries + default chords for toggle (and maximize on macOS)**

Follow existing `command_catalog.dart` patterns for platform defaults.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/commands/command_ids.dart \
  client/lib/services/commands/command_catalog.dart \
  client/lib/services/floating_workspace/floating_workspace_commands.dart \
  client/lib/services/commands/layout_command_registrar.dart \
  client/lib/app/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(commands): register floating workspace shortcuts

EOF
)"
```

---

### Task 5: File preview surface + opener redirect (TDD)

**Files:**
- Create: `client/lib/services/floating_workspace/surfaces/file_preview_floating_surface.dart`
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`
- Modify: `client/test/services/workbench/workbench_editor_opener_test.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart` (dirty pin)

- [ ] **Step 1: Rewrite opener tests**

```dart
test('openFile opens editor and floating tab, not workbench file tab', () async {
  // … gated fs …
  final floating = FloatingWorkspaceCubit();
  addTearDown(floating.close);
  floating.setActiveWorkspace('ws');

  final opener = WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    floating: floating,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  await opener.openFile('ws', '/repo/a.txt');

  expect(workbench.activeTabId('ws')?.kind, isNot(WorkbenchTabKind.file));
  expect(
    floating.state.bucket('ws').tabs.any((t) => t.payload == '/repo/a.txt'),
    isTrue,
  );
  expect(floating.state.visibility, FloatingPanelVisibility.open);
  expect(editor.state.bucket('ws').openFilePaths, ['/repo/a.txt']);
});
```

Keep `openDiff` tests asserting center `diff` tabs still created.

- [ ] **Step 2: FAIL then implement opener**

```dart
Future<void> openFile(...) async {
  // markdown seed unchanged
  _floating.ensureOpen();
  _floating.setActiveWorkspace(workspaceId);
  _floating.ensureTab(FloatingTab(
    id: 'file:$normalized',
    surfaceId: 'filePreview',
    title: p.basename(normalized),
    payload: normalized,
  ));
  _chat?.dismissNewChat();
  await _editor.openFile(workspaceId, normalized, fs: fs);
  // DO NOT _workbench.ensureTab(file)
}
```

Inject `FloatingWorkspaceCubit` (required). Update all construction sites in `app_shell.dart` / tests.

**`Surface.activate` vs opener:** `WorkbenchEditorOpener.openFile` performs domain `EditorCubit.openFile` itself (snappy). `FilePreviewFloatingSurface.activate` may be a no-op or idempotent re-open. Panel tab switches call `surface.activate` only when needed to focus an already-open file (e.g. reveal). Do not double-open on every rebuild.

- [ ] **Step 3: `FilePreviewFloatingSurface.build` → `FileEditorSurface(workspaceId, path)`**

- [ ] **Step 4: Dirty listener — pin floating tab instead of `WorkbenchCubit.pinTab(file)`**

If floating has no pin API yet, add `FloatingWorkspaceCubit.pinTab` or skip preview-replacement semantics for v1 (document: floating file tabs are always “pinned” / multi-tab). Prefer: floating tabs are never auto-replaced (simpler than workbench preview LRU).

- [ ] **Step 5: PASS + Commit**

```bash
cd client && flutter test test/services/workbench/workbench_editor_opener_test.dart
git add client/lib/services/workbench/workbench_editor_opener.dart \
  client/lib/services/floating_workspace/surfaces/file_preview_floating_surface.dart \
  client/lib/pages/workbench/file_editor_surface.dart \
  client/test/services/workbench/workbench_editor_opener_test.dart \
  client/lib/app/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(floating_workspace): route file open into floating surface

EOF
)"
```

---

### Task 6: Terminal surface + shell launcher redirect (TDD)

**Files:**
- Create: `client/lib/services/floating_workspace/surfaces/terminal_floating_surface.dart`
- Modify: `client/lib/services/workbench/workbench_shell_launcher.dart`
- Modify: `client/test/services/workbench/workbench_shell_launcher_test.dart`
- Modify: `client/lib/pages/home_workspace/global_resource_manager_host.dart` (shell focus → floating)
- Modify: `client/lib/services/workbench/workbench_shell_run_sync_logic.dart` (+ tests)

- [ ] **Step 1: Update shell launcher tests**

Assert `openAndSelect` / `focusOrCreateDefaultShell`:
- creates registry entry as today
- ensures floating terminal tab + `ensureOpen`
- does **not** `workbench.ensureTab(shell)`

- [ ] **Step 2: Implement launcher changes**

```dart
// After openEntry:
_floating.ensureOpen();
_floating.setActiveWorkspace(workspaceId);
_floating.ensureTab(FloatingTab(
  id: 'shell:${entry.id}',
  surfaceId: 'terminal',
  title: /* existing title resolver */,
  payload: entry.id,
));
// Remove: _workbench.ensureTab / select shell
```

Change `resolveWorkbenchShellToggle` / `focusOrCreateDefaultShell` to resolve most-recent shell from the **floating** bucket’s terminal tabs (by `payload` entry id) or registry selected entry — **not** `WorkbenchCubit.resolveMostRecentShell` (center strip will be empty of shells).

For `selectExisting`: call `_floating.ensureOpen()` + `_floating.selectTab(...)` — **do not** `_workbench.select(shell)`.

Also redirect RM `_navigateLeaf` / `ResourceBindingKind.workspaceShell` focus from `workbench.ensureTab(shell)` to floating tab focus/create (same as launcher). Update `layout_command_registrar_test.dart` if it still asserts center-shell `resolveMostRecentShell` behavior.

- [ ] **Step 3: Stop shell projection in `workbench_shell_run_sync_logic`**

Only sync `run` tabs to center strip. Update `workbench_shell_run_sync_logic_test.dart`.

Also update `client/lib/widgets/workbench/workbench_shell_run_sync.dart` so it no longer reconciles `shellIdsToEnsure` / `shellTabsToRemove` into `WorkbenchCubit` (logic returning empty shell ops is OK if the widget still compiles — document which approach you took in the commit).

- [ ] **Step 4: RM kill path**

In `global_resource_manager_host` (and any `_killBinding` / `killWorkspaceShell`), when removing a shell entry also `floating.removeTab('shell:$entryId')` + `TerminalFloatingSurface.onTabClosed` / registry dispose as today — do not only `workbench.removeTab(shell)`.

- [ ] **Step 5: `TerminalFloatingSurface.build`**

Reuse existing terminal body widgets from `workspace_terminal_view.dart` / workbench shell pane — extract a path-parameterized view if currently coupled to `WorkbenchCubit` selection. Prefer thin adapter: given `entryId`, render the same terminal view the center shell tab used.

- [ ] **Step 6: PASS + Commit**

```bash
cd client && flutter test \
  test/services/workbench/workbench_shell_launcher_test.dart \
  test/services/workbench/workbench_shell_run_sync_logic_test.dart
git add client/lib/services/workbench/workbench_shell_launcher.dart \
  client/lib/services/workbench/workbench_shell_run_sync_logic.dart \
  client/lib/widgets/workbench/workbench_shell_run_sync.dart \
  client/lib/services/floating_workspace/surfaces/terminal_floating_surface.dart \
  client/lib/pages/home_workspace/global_resource_manager_host.dart \
  client/test/services/workbench/
git commit -m "$(cat <<'EOF'
feat(floating_workspace): route workspace shell into floating surface

EOF
)"
```

---

### Task 7: Center strip defense — stop showing file/shell

**Files:**
- Modify: `client/lib/services/workbench/workbench_tab_projection.dart` (+ test)
- Modify: `client/lib/pages/workbench/workbench_body.dart` (file/shell branches become assert/fallback)
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart` optionally reject `ensureTab(file|shell)` in debug/assert

- [ ] **Step 1: Projection filter test**

```dart
test('projection omits file and shell kinds', () {
  final tabs = projectWorkbenchTabs(
    tabOrder: [
      WorkbenchTabId.session('s1'),
      WorkbenchTabId.file('/a'),
      WorkbenchTabId.shell('e1'),
      WorkbenchTabId.diff('/a', source: WorkbenchDiffSource.changes),
    ],
    // … minimal maps …
  );
  expect(tabs.map((t) => t.id), ['s1', /* diff key */]);
});
```

Or filter at call site before projection — pick one place; prefer filter inside `projectWorkbenchTabs` for defense in depth **or** refuse `ensureTab` for file/shell. Spec: product path must not create them; assert in `WorkbenchCubit.ensureTab` when kind is file/shell (throws in assert mode / no-ops in release) is clearest.

- [ ] **Step 2: Implement + update any tests that still create file/shell center tabs for UI**

Migrate those tests to floating cubit.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(workbench): keep file and shell off center strip

EOF
)"
```

---

### Task 8: Empty panel + chrome + toggle + tab close UI (TDD widget)

**Files:**
- Create: `client/lib/pages/floating_workspace/floating_workspace_empty.dart`
- Create: `client/lib/pages/floating_workspace/floating_workspace_chrome.dart`
- Create: `client/lib/pages/floating_workspace/floating_workspace_toggle.dart`
- Create: `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`
- Create: `client/test/pages/floating_workspace/floating_workspace_empty_test.dart`
- Create: `client/test/pages/floating_workspace/floating_workspace_tab_close_test.dart` (or cubit+surface unit test)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ regen if project requires)

- [ ] **Step 1: Widget test empty rows**

Pump `FloatingWorkspaceEmpty` with fake actions; tap “新 Terminal” invokes callback; shows three rows including minimize. Also cover ↑↓ + Enter keyboard selection (spec Interaction).

- [ ] **Step 2: Implement empty + chrome + toggle**

Visual: dark rounded panel list, keycap chips via `shared_ui` if available or small `Tp`-style chip. Toggle: `Icons.dashboard_customize_outlined` or similar grid icon; `Positioned` from bottom-right using cubit offset; `Listener`/`GestureDetector` for drag.

z-index: toggle above panel (`Stack` order).

- [ ] **Step 3: Tab bar close affordance + close pipeline**

Each floating tab shows a close control. On close:

```dart
Future<void> closeFloatingTab({
  required FloatingWorkspaceCubit cubit,
  required FloatingSurfaceRegistry registry,
  required FloatingTab tab,
}) async {
  final surface = registry[tab.surfaceId];
  if (surface == null) {
    cubit.removeTab(tab.id);
    return;
  }
  if (!await surface.canClose(tab)) return; // dirty file prompt inside surface
  surface.onTabClosed(tab);                 // editor.closeFile / kill or detach shell
  cubit.removeTab(tab.id);
}
```

- File surface `canClose`: reuse existing dirty-file dialog used by workbench file tab close.
- Terminal surface `onTabClosed`: follow existing workspace-terminal close/kill policy (same as center shell tab close today).

- [ ] **Step 4: Empty panel `Ctrl/Cmd+W`**

When panel is focused / open and active bucket has **zero** tabs (or no closable active tab), map close-tab-style shortcut to `floatingWorkspace.minimize` (spec: empty + close → minimize). When a tab is active, `Ctrl/Cmd+W` closes that tab via the pipeline above. Prefer registering a small `Shortcuts`/`Actions` scope on the panel rather than fighting session strip shortcuts globally.

- [ ] **Step 5: l10n strings**

```
floatingWorkspaceNewTerminal / 新 Terminal
floatingWorkspaceOpenFile / 打开文件
floatingWorkspaceMinimize / 最小化
```

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(floating_workspace): add empty state, chrome, toggle, and tab close

EOF
)"
```

---

### Task 9: Panel + host mount on HomeShell

**Files:**
- Create: `client/lib/pages/floating_workspace/floating_workspace_panel.dart`
- Create: `client/lib/pages/floating_workspace/floating_workspace_host.dart`
- Create: `client/lib/services/floating_workspace/floating_maximize_insets.dart` (notifier / inherited)
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (or IDE shell) — publish maximize insets
- Modify: `client/lib/app/app_shell.dart` (Provide same cubit instance + registry)
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` `_closeTab` (or equivalent) — `floating.disposeWorkspace(workspaceId)`

- [ ] **Step 1: `FloatingWorkspacePanel`**

- Visible chrome when `visibility == open`
- When maximized: expand to **`FloatingMaximizeInsets`** content rect (sidebar-aware); if insets unset, full body below title bar
- Else: `Positioned` from `panelBounds` with **drag on title and edge resize handles (required for v1)** — clamp to host size
- Body: if no tabs → empty; else tab bar + `registry[tab.surfaceId].build`
- Keep child mounted when `minimized` **if** active bucket has tabs (`Offstage` / `Opacity:0` + `IgnorePointer`, or `TickerMode` off) — do **not** dispose PTY

- [ ] **Step 2: `FloatingWorkspaceHost`**

```dart
Stack(
  children: [
    child, // existing HomeShell body
    const FloatingWorkspacePanel(),
    const FloatingWorkspaceToggle(),
  ],
)
```

- [ ] **Step 3: Wire active workspace + dispose on workspace close**

- Listen to `ChatCubit.tabStore.activeWorkspaceId` (or HomeShell tab key) → `floating.setActiveWorkspace`.
- In `HomeShell` workspace-tab close path (same place that calls `WorkbenchCubit.clearWorkspace`), also call `floating.disposeWorkspace(workspaceId)` and clear attention if needed.

- [ ] **Step 4: Publish maximize insets from workspace layout**

From `WorkspaceSplitPane` (after sidebar width known), update `FloatingMaximizeInsets` so maximize does not cover the file-tree sidebar.

- [ ] **Step 5: Manual smoke (desktop)** — document in commit body; optional widget smoke test for host visibility.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(floating_workspace): mount overlay host on HomeShell

EOF
)"
```

---

### Task 10: Open-file picker + attention + focus polish

**Files:**
- Modify: `floating_workspace_commands.dart` / host
- Modify: surfaces for `attentionWhileMinimized`
- Possibly: terminal passthrough already global — verify with panel focused

- [ ] **Step 1: `floatingWorkspace.openFile` handler**

Use existing workspace file-picker / search patterns (`FilePicker` or reuse workspace search dialog scoped to files). On select → same path as `WorkbenchEditorOpener.openFile`.

- [ ] **Step 2: Attention**

Subscribe terminal surface stream (registry entry output / working flag) while minimized → `setAttention(true)`; clear on open.

- [ ] **Step 3: Focus restore**

Remember `FocusNode` / use `FocusManager` primary focus before open; restore on minimize (best-effort; match Orca “transient overlay”).

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(floating_workspace): file picker, attention dot, focus restore

EOF
)"
```

---

### Task 11: In-flight migration + welcome/cheatsheet + full verify

**Files:**
- Modify: bootstrap or first-open migration when floating ships
- Modify: `workbench_welcome_page` / `kWorkbenchWelcomeCommandIds` tests if needed
- Modify: any remaining tests creating center file/shell tabs

- [ ] **Step 1: Migration policy**

On app start (or first `FloatingWorkspaceCubit` create): for each workspace bucket in `WorkbenchCubit`, if tabs contain `file`/`shell`, move them into floating tabs (call editor already open / shell entry ids) and remove from workbench. One-shot; no user prompt.

- [ ] **Step 2: Run targeted suites**

```bash
cd client && flutter test \
  test/cubits/floating_workspace/ \
  test/services/floating_workspace/ \
  test/services/workbench/workbench_editor_opener_test.dart \
  test/services/workbench/workbench_shell_launcher_test.dart \
  test/services/workbench/workbench_shell_run_sync_logic_test.dart \
  test/services/workbench/workbench_tab_projection_test.dart \
  test/pages/workbench/workbench_welcome_page_test.dart \
  test/pages/floating_workspace/
```

- [ ] **Step 3: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(floating_workspace): migrate legacy file/shell tabs and verify

EOF
)"
```

---

## Acceptance mapping

| Spec criterion | Tasks |
|----------------|-------|
| Sidebar file → floating only | 5, 7, 9 |
| New Terminal → floating; no center shell | 6, 7, 9 |
| Minimize keep-alive | 1, 9 |
| Empty three actions + toggle | 8, 9, 10 |
| Tab close + dirty/kill guards | 8 |
| Workspace close disposes floating bucket | 9 |
| Empty Ctrl/Cmd+W → minimize | 8 |
| Workspace tab switches bucket | 1, 9 |
| Diff/run/session stay center | 5–7 |
| Persistence geometry | 3 |
| Maximize respects sidebar inset | 9 |

## Out of scope (do not implement in this plan)

- Second OS window, Markdown notes, browser tab, Cmd+J palette, mobile parity, persisting open tabs across restart, moving diff/run into floating.
