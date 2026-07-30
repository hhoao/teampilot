# Floating Workspace (Orca-like overlay for non-session surfaces)

**Date:** 2026-07-30  
**Status:** Draft  
**Product:** TeamPilot (`client/`)

## Goal

Give TeamPilot an in-app **Floating Workspace** overlay (Orca-style) that hosts
**non-session** previews and tools — starting with **sidebar file preview** and
**workspace terminal launch** — so the session/chat main area stays focused on
conversation while IDE-adjacent surfaces live in a draggable, minimizable panel.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Host product | TeamPilot |
| Window model | Main-window **overlay** (not a second OS window / always-on-top) |
| v1 surfaces | File preview + workspace terminal (`WorkbenchTabKind.file` / `.shell`) |
| Center workbench after migration | **session / diff / run** stay as center workbench tabs; **file / shell** leave the center strip |
| Layout coexistence | **Replace** center-workbench hosting of file + shell; all former openers redirect into the floating workspace |
| Empty-state actions | **新 Terminal** / **打开文件** / **最小化** (Orca tone; file picker, not Markdown-specific) |
| Architecture | First-class `FloatingWorkspace` host + pluggable `FloatingSurface`s; domain state stays in `EditorCubit` / `WorkspaceTerminalRegistry` |
| Persistence | Persist panel bounds, toggle position, maximized flag; **do not** persist open tabs across app restart |
| Platform | Desktop-first; mobile parity is out of scope for this spec |

## Problem

1. File and shell currently open as **center workbench tabs**
   (`WorkbenchCubit` + `WorkbenchBody`), competing with session/diff/run in the
   same strip and crowding the primary chat column.
2. There is no Orca-like always-reachable overlay for “scratch” IDE surfaces
   that can minimize while keeping PTY/editor state alive.
3. Adding more non-session tools later (Git, Resource Manager, …) needs a
   stable host; bolting each into the center workbench does not scale.

## Architecture

```
HomeShell (main window)
├── Center workbench (WorkbenchCubit)
│     └── tabs: session | diff | run     ← file/shell removed from strip
├── Workspace sidebar (file tree)        (click file → floating file tab)
├── FloatingWorkspaceHost                ← new
│   ├── FloatingWorkspaceToggle          (bottom-right, draggable)
│   └── FloatingWorkspacePanel           (fixed overlay: drag / resize / chrome)
│         ├── empty actions | tab bar + window controls
│         └── FloatingWorkspaceTabHost
│               ├── FilePreviewSurface  → EditorCubit (+ WorkbenchEditorOpener redirect)
│               ├── TerminalSurface     → WorkspaceTerminalRegistry / ShellConnector
│               └── (future surfaces…)
└── Legacy: WorkbenchTabKind.file / .shell no longer created on the center strip
```

### Layering

| Layer | Owns | Does not own |
|-------|------|----------------|
| `FloatingWorkspaceCubit` | visibility, bounds, active tab, empty commands, active workspace binding | File bytes, PTY lifecycle |
| `FloatingSurface` plugins | id, empty action, tab create/build, activate, close guards, attention stream | Window chrome |
| Domain cubits / registries | `openFile`, shell connect, content | Whether UI is shown in the floating panel |
| `WorkbenchCubit` (post-migration) | session / diff / run center tabs only | file / shell presentation |

### Multi-workspace

The floating panel binds to the **active HomeShell workspace**. Tab contents are
stored in a **per-workspace bucket** (same idea as `EditorCubit` /
`WorkbenchCubit` buckets). Switching workspace tabs swaps the visible floating
bucket. Panel **geometry** (bounds / toggle position / maximized) is **global**.

## Interaction

### Visibility model

Use an explicit enum (not a lone `isOpen` bool):

```
enum FloatingPanelVisibility { hidden, open, minimized }
```

| Value | Meaning |
|-------|---------|
| `hidden` | No panel chrome; used only when feature disabled or never opened this session with zero need to keep mounts |
| `open` | Panel visible (normal or maximized) |
| `minimized` | Panel chrome hidden; **tab content stays mounted** when the active bucket has tabs (PTY/editor keep-alive) |

`isMaximized` is orthogonal and only applies while `visibility == open`.

Toggle / `floatingWorkspace.toggle`:

- `open` → `minimized`
- `minimized` or `hidden` → `open`

Empty panel + `Ctrl/Cmd+W` (no closable tab): `open` → `minimized` (may drop to
`hidden` only when the bucket has **zero** tabs and nothing to keep alive).

### Show / hide entries

| Entry | Behavior |
|-------|----------|
| `FloatingWorkspaceToggle` | Toggle open ↔ minimized; position draggable + persisted |
| `floatingWorkspace.toggle` shortcut | Same (defaults: Linux/Win `Ctrl+Alt+A`, macOS `Cmd+Opt+A`, aligned with Orca) |
| Sidebar / file-tree open | Ensure `open` → focus/create file tab → `EditorCubit.openFile` via redirected opener |
| Former shell / file workbench openers | Redirect into floating surfaces (see Migration) |
| Chrome maximize / minimize | Maximize fills left sidebar + center content inside workspace card padding (excludes docked right-tools + status bar); minimize → `minimized` with keep-alive |
| Empty panel close shortcut | `Ctrl/Cmd+W` → minimize when there is no closable tab |

### Empty state (v1)

1. **新 Terminal** — create/focus workspace shell in floating terminal surface  
2. **打开文件** — in-app file picker rooted at the active workspace; then open file tab  
3. **最小化** — set `visibility = minimized`  

Rows: icon + label + shortcut keycap chips; keyboard ↑↓ + Enter; hover/selection
highlight.

**Command / keycap mapping** (register on `CommandBus`; empty-state chips reflect
effective bindings):

| Empty row | Command id | Notes |
|-----------|------------|--------|
| 新 Terminal | `floatingWorkspace.newTerminal` | Replaces center-strip use of `CommandIds.togglePanel` / `WorkbenchShellLauncher` for this UX; launcher implementation may be reused underneath |
| 打开文件 | `floatingWorkspace.openFile` | Opens picker then file surface; distinct from sidebar path click |
| 最小化 | `floatingWorkspace.minimize` | Also chrome Minus |
| (global) | `floatingWorkspace.toggle` / `maximize` | Toggle button + maximize control |

### Content state

- Top: tab bar (file names / Terminal) + maximize / minimize controls  
- Multiple file tabs allowed; terminal exposes multiple entries if the registry
  already supports them  
- Drag title region to move; edge resize handles; toggle z-index above panel  

### Attention UX

While `minimized`, terminal output or relevant file events may set an attention
dot on the toggle (Orca parity). Opening the panel focuses inside it; closing
restores focus to the prior surface (session input or sidebar).

## Data flow

```
Gesture (sidebar file / empty “新 Terminal” / redirected workbench opener)
  → FloatingWorkspaceCommands.openSurface(workspaceId, surfaceId, payload?)
  → Cubit: ensureOpen() + ensureTab() + setActive
  → Surface.activate(payload)
       FilePreviewSurface → EditorCubit.openFile(...)
       TerminalSurface    → WorkspaceShellConnector / registry.groupFor(...)
  → Panel renders Surface.build(activeTab)
```

Closing a tab calls `Surface.canClose` / `onTabClosed` (dirty file prompts;
terminal kill vs detach follows existing workspace-terminal policy), then
removes the tab from the bucket. Closing the workspace disposes that floating
bucket (and terminal group as today).

### State sketch

```
FloatingWorkspaceState
├── visibility: FloatingPanelVisibility   // hidden | open | minimized
├── isMaximized: bool                     // only meaningful when open
├── panelBounds / togglePosition          // global, persisted
├── activeWorkspaceId
├── buckets: Map<workspaceId, FloatingWorkspaceBucket>
│     ├── tabs: List<FloatingTab>         // { id, surfaceId, title, payload }
│     └── activeTabId
└── attention: bool
```

### `FloatingSurface` contract

```dart
abstract class FloatingSurface {
  String get id;
  FloatingEmptyAction? get emptyAction;
  bool get allowMultipleTabs;

  FloatingTab createTab({required String workspaceId, Object? payload});
  Widget build(BuildContext context, FloatingTab tab);

  Future<void> activate(FloatingTab tab);
  Future<bool> canClose(FloatingTab tab);
  void onTabClosed(FloatingTab tab);

  Stream<bool>? get attentionWhileMinimized;
}
```

`FloatingSurfaceRegistry` holds built-in `filePreview` + `terminal`; future
tools only `register`.

## Migration

**Source of truth today:** center workbench tabs via `WorkbenchCubit` /
`WorkbenchBody` (`WorkbenchTabKind`: `session | file | diff | shell | run`).
Bottom dock terminal is already gone (`LayoutCubit.toggleWorkspaceTerminal` is
a no-op); do **not** plan against a bottom-shell or right-preview host.

| Legacy | New behavior |
|--------|----------------|
| `WorkbenchEditorOpener.openFile` | Open floating file surface; **do not** `ensureTab` `WorkbenchTabKind.file` |
| `WorkbenchEditorOpener.openDiff` | **Unchanged** — stays center `WorkbenchTabKind.diff` |
| `WorkbenchShellLauncher` / `CommandIds.togglePanel` | Open floating terminal surface (reuse create-or-focus logic; stop adding center `shell` tabs) |
| File tree / context menu / search open file | Same redirected opener |
| `global_resource_manager_host` shell navigation | Redirect to floating terminal tab focus/create |
| `WorkbenchShellRunSync` / shell tab projection | Stop projecting `shell` onto the center strip; run sync for `run` tabs unchanged |
| `WorkbenchTabKind.file` / `.shell` in center strip | Removed from v1 product path; migrate or close any existing in-memory file/shell tabs when floating ships |
| Settings / docs referring to “panel” as center shell | Point at floating workspace |

**Explicitly stays on center workbench (v1):** `session`, `diff`, `run`.

## Module layout

```
client/lib/cubits/floating_workspace/
  floating_workspace_cubit.dart
  floating_workspace_state.dart

client/lib/services/floating_workspace/
  floating_surface.dart
  floating_surface_registry.dart
  floating_workspace_commands.dart
  floating_workspace_persistence.dart
  surfaces/
    file_preview_floating_surface.dart
    terminal_floating_surface.dart

client/lib/pages/floating_workspace/
  floating_workspace_host.dart
  floating_workspace_panel.dart
  floating_workspace_toggle.dart
  floating_workspace_empty.dart
  floating_workspace_chrome.dart
  floating_workspace_tab_bar.dart
```

- Mount host from `HomeShell`; construct cubit + registry in `app_shell.dart`.
- Register commands on `CommandBus` /
  `ShortcutDispatcher` as listed above.
- Prefer `shared_ui` primitives for keycaps / panel chrome (`Tp*`); add shared
  widgets only when missing.

## Error handling

| Case | Behavior |
|------|----------|
| File open failure | Keep panel open; reuse `EditorCubit` snackbar / error tab affordances |
| Terminal connect failure | Inline error inside terminal surface; do not auto-minimize |
| Active workspace closed | Dispose that floating bucket; switch to next workspace bucket or minimize |
| Dirty file on tab close | `canClose` → existing editor dirty prompt |

## Testing

- Cubit: visibility transitions; maximize only while open; per-workspace bucket switch; empty-tab close  
- Registry: empty-action order for built-in surfaces  
- Commands: `WorkbenchEditorOpener.openFile` and shell launcher route to floating; no new center `file`/`shell` tabs  
- Widget: empty three rows + keycaps; toggle above panel hit-testing  
- Focus: terminal passthrough while open; restore focus on minimize  
- Workbench projection: center strip lists only session/diff/run after migration  

## Non-goals

- Separate `BrowserWindow` / always-on-top OS window  
- Markdown notes or embedded browser (Orca extras)  
- Global Cmd+J-style command palette  
- Moving session chat into the floating panel  
- Moving **diff** or **run** tabs into the floating panel in v1  
- Mobile feature parity (optional later: hide toggle or full-screen sheet)  
- Persisting open floating tabs across app restart  

## Acceptance criteria

1. Opening a file from the sidebar shows preview **only** in the floating panel;
   no new center `WorkbenchTabKind.file` tab; session/diff/run strip behavior
   unchanged.  
2. **新 Terminal** yields a usable workspace shell in the floating panel; shell
   no longer occupies a center workbench tab / split.  
3. Minimize then reopen keeps terminal session and open files alive (same
   process; `visibility == minimized` with mounted content).  
4. Empty state shows the three actions with correct shortcut chrome; toggle is
   draggable and clickable above the panel.  
5. Switching HomeShell workspace tabs swaps the floating bucket contents.  
6. Diff / run / session remain center workbench tabs; no dead shell/file
   entry points; `flutter analyze` (project norms) and targeted tests pass.

## Risks

| Risk | Mitigation |
|------|------------|
| Opener/launcher still call `WorkbenchCubit.ensureTab(file\|shell)` | Redirect at `WorkbenchEditorOpener` / `WorkbenchShellLauncher` (and RM host); add tests that center strip never gains file/shell |
| Editor/terminal widgets assume workbench ancestors | Reuse views inside `Surface.build`; remove hard dependencies on center `WorkbenchBody` |
| ShortcutDispatcher vs terminal focus | Reuse existing terminal passthrough while panel open; restore session on close |
| Existing in-flight file/shell workbench tabs at upgrade | One-shot migrate into floating bucket or close with user-visible policy documented in the plan |

## References

- Orca: `src/renderer/src/components/floating-terminal/*`,
  `FloatingTerminalPanel` empty actions, `FloatingTerminalToggleButton`
- TeamPilot: `WorkbenchCubit`, `WorkbenchTabKind`, `WorkbenchEditorOpener`,
  `WorkbenchShellLauncher`, `WorkbenchBody`, `EditorCubit`,
  `WorkspaceTerminalRegistry`, `WorkspaceShellConnector`, `CommandBus` /
  `ShortcutDispatcher`
