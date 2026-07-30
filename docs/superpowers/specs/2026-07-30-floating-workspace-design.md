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
| v1 surfaces | File preview + workspace terminal |
| Layout coexistence | **Replace**: remove bottom-shell terminal slot and right/center file-preview hosting; old entry points open the floating workspace |
| Empty-state actions | **新 Terminal** / **打开文件** / **最小化** (Orca tone; file picker, not Markdown-specific) |
| Architecture | First-class `FloatingWorkspace` host + pluggable `FloatingSurface`s; domain state stays in `EditorCubit` / `WorkspaceTerminalRegistry` |
| Persistence | Persist panel bounds, toggle position, maximized flag; **do not** persist open tabs across app restart |
| Platform | Desktop-first; mobile parity is out of scope for this spec |

## Problem

1. File preview and workspace terminal currently compete with the session
   workbench (right tools / bottom shell), cluttering the primary chat surface.
2. There is no Orca-like always-reachable overlay for “scratch” IDE surfaces
   that can minimize while keeping PTY/editor state alive.
3. Adding more non-session tools later (Git, Resource Manager, …) needs a
   stable host; bolting each into `WorkspaceSplitPane` does not scale.

## Architecture

```
HomeShell (main window)
├── Session / Chat main area          (unchanged)
├── Workspace sidebar (file tree)     (click file → floating file tab)
├── FloatingWorkspaceHost             ← new
│   ├── FloatingWorkspaceToggle       (bottom-right, draggable)
│   └── FloatingWorkspacePanel        (fixed overlay: drag / resize / chrome)
│         ├── empty actions | tab bar + window controls
│         └── FloatingWorkspaceTabHost
│               ├── FilePreviewSurface  → EditorCubit
│               ├── TerminalSurface     → WorkspaceTerminalRegistry / ShellConnector
│               └── (future surfaces…)
└── Legacy right file-preview pane / bottom WorkspaceTerminalPanel slot: removed
```

### Layering

| Layer | Owns | Does not own |
|-------|------|----------------|
| `FloatingWorkspaceCubit` | open / minimized / maximized, bounds, active tab, empty commands, active workspace binding | File bytes, PTY lifecycle |
| `FloatingSurface` plugins | id, empty action, tab create/build, activate, close guards, attention stream | Window chrome |
| Domain cubits / registries | `openFile`, shell connect, content | Whether UI is shown in the floating panel |

### Multi-workspace

The floating panel binds to the **active HomeShell workspace**. Tab contents are
stored in a **per-workspace bucket** (same idea as `EditorCubit` buckets).
Switching workspace tabs swaps the visible floating bucket. Panel **geometry**
(bounds / toggle position / maximized) is **global** (one set for the app).

## Interaction

### Show / hide

| Entry | Behavior |
|-------|----------|
| `FloatingWorkspaceToggle` | Toggle open ↔ minimized; position draggable + persisted |
| `floatingWorkspace.toggle` shortcut | Same (defaults: Linux/Win `Ctrl+Alt+A`, macOS `Cmd+Opt+A`, aligned with Orca) |
| Sidebar file open | Ensure panel open → focus/create file tab → `EditorCubit.openFile` |
| Former terminal / preview toggles | Redirect to open the matching floating surface |
| Chrome maximize / minimize | Maximize fills workbench safe area; minimize keeps tree mounted when tabs exist (PTY/editor alive) |
| Empty panel + close shortcut | `Ctrl/Cmd+W` minimizes when there is no closable tab |

### Empty state (v1)

1. **新 Terminal** — create/focus workspace shell tab for active workspace  
2. **打开文件** — in-app file picker rooted at the active workspace; then open file tab  
3. **最小化** — collapse panel  

Rows: icon + label + shortcut keycap chips; keyboard ↑↓ + Enter; hover/selection
highlight.

### Content state

- Top: tab bar (file names / Terminal) + maximize / minimize controls  
- Multiple file tabs allowed; terminal exposes multiple entries if the registry
  already supports them  
- Drag title region to move; edge resize handles; toggle z-index above panel  

### Attention UX

While minimized, terminal output or relevant file events may set an attention
dot on the toggle (Orca parity). Opening the panel focuses inside it; closing
restores focus to the prior surface (session input or sidebar).

## Data flow

```
Gesture (sidebar file / empty “新 Terminal” / redirected legacy entry)
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
├── isOpen / isMaximized
├── panelBounds / togglePosition     // global, persisted
├── activeWorkspaceId
├── buckets: Map<workspaceId, FloatingWorkspaceBucket>
│     ├── tabs: List<FloatingTab>    // { id, surfaceId, title, payload }
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

| Legacy | New behavior |
|--------|----------------|
| Sidebar → right/center editor host | Same `EditorCubit.openFile`; **display only** in floating file tab |
| Bottom `WorkspaceTerminalPanel` visibility | `floatingWorkspace.open('terminal')` |
| Right-tools **file preview** responsibility | Removed from split; other right-tools (if any) stay |
| Layout flags for bottom-shell / right-preview | Deprecated or remapped to “open floating workspace”; settings copy updated |

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
  `ShortcutDispatcher`: `toggle`, `maximize`, `minimize`, `newTerminal`,
  `openFile`.
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

- Cubit: open / minimize / maximize; per-workspace bucket switch; empty-tab close  
- Registry: empty-action order for built-in surfaces  
- Commands: sidebar openFile routes to floating; legacy layout flags redirect  
- Widget: empty three rows + keycaps; toggle above panel hit-testing  
- Focus: terminal passthrough while open; restore focus on minimize  

## Non-goals

- Separate `BrowserWindow` / always-on-top OS window  
- Markdown notes or embedded browser (Orca extras)  
- Global Cmd+J-style command palette  
- Moving session chat into the floating panel  
- Mobile feature parity (optional later: hide toggle or full-screen sheet)  
- Persisting open floating tabs across app restart  

## Acceptance criteria

1. Opening a file from the sidebar shows preview **only** in the floating panel;
   session layout unchanged; legacy right preview slot gone.  
2. **新 Terminal** yields a usable workspace shell in the floating panel; bottom
   `WorkspaceTerminalPanel` no longer occupies the split.  
3. Minimize then reopen keeps terminal session and open files alive (same
   process).  
4. Empty state shows the three actions with correct shortcut chrome; toggle is
   draggable and clickable above the panel.  
5. Switching HomeShell workspace tabs swaps the floating bucket contents.  
6. No dead entry points after layout-flag removal; `flutter analyze` (project
   norms) and targeted unit/widget tests pass.

## Risks

| Risk | Mitigation |
|------|------------|
| Editor/terminal widgets assume split-pane ancestors | Reuse views inside `Surface.build`; remove hard dependencies on `WorkspaceSplitPane` |
| ShortcutDispatcher vs terminal focus | Reuse existing terminal passthrough while panel open; restore session on close |
| Accidental removal of non-preview right tools | Migration checklist scopes **file preview** only |

## References

- Orca: `src/renderer/src/components/floating-terminal/*`,
  `FloatingTerminalPanel` empty actions, `FloatingTerminalToggleButton`
- TeamPilot: `EditorCubit`, `WorkspaceTerminalRegistry`,
  `WorkspaceShellConnector`, `WorkspaceSplitPane`, `WorkspaceTerminalPanel`,
  `CommandBus` / `ShortcutDispatcher`
