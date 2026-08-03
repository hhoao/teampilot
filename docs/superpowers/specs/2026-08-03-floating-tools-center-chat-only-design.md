# Floating tools host: center Chat-only (design)

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Harden the floating-workspace model when `filePreviewHost = floating`, and fix Run/shellScript UI missing on workspace compose landing.

## Problem

Starting a `shellScript` launch configuration from the title-bar Run toolbar does not show any run UI when the workspace center is on compose landing (`newChatActive`).

Root cause: `RunUiIntent` is handled only by `WorkbenchShellRunSync`, which is mounted under `ChatPageShell`. Landing uses `WorkspaceChatPane` instead of `ChatPage`, so no listener calls `FloatingWorkspaceCubit.ensureOpen` / `ensureTab`. The process/PTY may start, but no floating tab appears. Center Run tabs also do not apply to built-in shell scripts (`sessionUsesRunPanel` excludes them).

This conflicts with the intended layout when file preview host is floating: center is Chat-only; tools live in the floating workspace.

## Goals

When `LayoutPreferences.filePreviewHost == FilePreviewHost.floating`:

1. **Center** hosts only Chat surfaces (compose landing and session chat/workbench for AI sessions).
2. **Floating workspace** hosts file preview, diff preview, workspace shell terminals, and Run process logs.
3. Run from landing or from an open session opens/focuses the floating panel **without** dismissing compose / stealing the center Chat surface.
4. Non-terminal Run output (process mode / extension launch text logs) appears as floating **Run** tabs, not center workbench tabs.

Preserve existing dual-mode for file/diff when `filePreviewHost == center`. **Shell terminals and Run process logs always use the floating workspace**, regardless of `filePreviewHost`. Only file/diff hosting follows that preference.

## Non-goals

- Removing the `filePreviewHost = center` product option.
- Changing Run configuration schema or launch execution semantics beyond UI hosting.
- Redesigning floating panel chrome, drag/resize, or toggle UX.
- Moving AI session member PTYs into the floating workspace (session terminals stay in the Chat/session workbench).

## Target surface ownership

| Surface | Floating host | Center (`filePreviewHost=floating`) | Center (`filePreviewHost=center`) |
|---------|---------------|-------------------------------------|-----------------------------------|
| Compose / Session Chat | — | yes | yes |
| File preview | yes | no | yes |
| Diff preview | yes | no | yes |
| Workspace shell terminal | yes | no | no (already floating) |
| Run process log | yes (new surface) | no | no |
| shellScript `executeInTerminal=true` | floating terminal tab | — | — |

## Architecture

### Intent bridge mount

Move `WorkbenchShellRunSync` (or extract a focused `RunUiIntentBridge` widget with the same responsibilities) from `ChatPageShell` up to `WorkspaceSplitPane`, so it is mounted for both:

- compose landing (`WorkspaceChatPane`)
- session center (`ChatPage` / `ChatPageShell`)

`ChatPageShell` must not keep a duplicate listener (avoid double `ensureTab`).

`WorkbenchShellRunSync` also reconciles run-panel sessions into center `WorkbenchTabKind.run` tabs. After the hoist, that reconcile must sync **floating** Run tabs instead (or stop creating center run tabs entirely). Do not leave the old center reconcile in place.

Hold-handle wiring for terminal focus continues to use the split-pane `WorkspaceTerminalHoldHandle` already owned by `WorkspaceSplitPane`. Preserve existing `focusToolWindow` → hold-handle `requestFocus` behavior for terminal intents.

### Run UI intent routing

Existing flow stays:

`RunToolbar` → `RunCubit.runSelected` → launcher → `publishUiIntent(RunUiIntent)` → bridge.

Bridge behavior:

| Intent | Action |
|--------|--------|
| `surface: terminal`, `activateToolWindow: true` | `FloatingWorkspaceCubit.ensureOpen`, `setActiveWorkspace`, `ensureTab` + `selectTab` for terminal floating tab (`resolveFloatingTabForTerminalRunIntent`) |
| `surface: run`, `activateToolWindow: true` | Same for a new floating Run tab (new resolver parallel to the terminal helper) |
| `activateToolWindow: false` | Do not force panel open/focus (keep current semantics); launch still proceeds |

**Do not** call `ChatCubit.dismissNewChat` / leave compose when handling these intents.

### Floating Run surface

Register a new `FloatingSurface` with id `run` (e.g. `RunFloatingSurface`) in `FloatingSurfaceRegistry.withDefaults` alongside terminal/file/diff.

- Tab payload: Run session id.
- Title: launch configuration name (fallback session id).
- Body: reuse `RunPanel` / `RunSessionPage` (text log via `RunTerminalBridge`), without center workbench chrome.
- Close: align with existing Run dismiss semantics (`RunCubit.dismissSession` — stop if running + remove session).

Process-mode / extension launches that already emit `RunToolSurface.run` always open this floating surface and must not create center `WorkbenchTabId.run` tabs.

### Center strip rules (`filePreviewHost=floating`)

- `WorkbenchCubit` center strip projects **session** tabs only.
- Do not ensure center tabs for file / diff / run under this host.
- On host switch or workspace open, migrate leftover center file/diff/run tabs to floating (extend `syncFilePreviewHostTabs` / `migrateLegacyWorkbenchTabsToFloating` — today run tabs are skipped — or add a sibling migrator). Align migration triggers with existing host-switch and workspace-open paths.
- ChatPageShell workbench projection: under floating host, do not advertise run/file titles into the center strip path. Never project run tabs to center in either host mode.

When `filePreviewHost=center`, file/diff may still use center strip as today; shell/run remain floating.

### File open vs compose

Today `WorkbenchEditorOpener.openFile` / `openDiff` may call `dismissNewChat` when opening a floating file/diff. Align with Run: opening floating file/diff **must not** dismiss compose when the intent is only to show a tool surface in the floating panel.

## Data flow (landing Run)

```
User taps Run (landing, newChatActive=true)
  → RunCubit.runSelected
  → ShellScriptLauncher (executeInTerminal)
  → WorkspaceTerminalRunService.openForRun + inject
  → publishUiIntent(terminal)
  → WorkspaceSplitPane bridge (always mounted)
  → FloatingWorkspace ensureOpen + terminal tab
  → Center remains WorkspaceChatPane / compose
```

## Error handling and edge cases

- Missing `TerminalRunDeps`: keep existing launcher failure → `RunCubit.errorMessage` / edit-on-schema-failure dialog; no silent UI success.
- Compound runs: each produced session/terminal follows the same routing; activate the latest relevant floating tab when `activateToolWindow` is true.
- Closing floating terminal tab for a run-bound entry: preserve existing registry/run-service close listeners.
- Inactive workspace tab: bridge is scoped to the active workspace split; intents for the bound `RunCubit` / `tabScopeId` only.
- Rerun / restart / new instance: reuse existing `RunCubit` dialogs; UI routing still goes through intents after start.

## Testing

1. **Unit:** floating Run tab resolver (`activateToolWindow`, empty session id, surface mismatch).
2. **Unit:** center strip plan / sync excludes file/diff/run when host is floating; includes migration of stale center run tabs.
3. **Widget / integration:** compose landing + `runSelected` for shellScript with `executeInTerminal` → floating visibility open and terminal tab present; `newChatActive` remains true.
4. **Widget:** process-mode / `RunToolSurface.run` → floating `run` tab, not center `WorkbenchTabKind.run`.
5. **Manual:** landing Run shows output in floating panel; center still compose; Stop still works from title-bar Run toolbar.

## Implementation sketch (for planning)

1. Extract or hoist Run UI intent bridge to `WorkspaceSplitPane`; remove duplicate from `ChatPageShell`.
2. Add `RunFloatingSurface` + registry wiring + floating tab id helper.
3. Extend intent resolution for `RunToolSurface.run` → floating tab.
4. Gate center file/diff/run projection on `filePreviewHost`; migrate stale tabs.
5. Stop `dismissNewChat` on floating file/diff/run opens.
6. Tests listed above.

## Decisions log

| Decision | Choice |
|----------|--------|
| Scope | Harden floating model (not Run-only patch; not remove center preview option) |
| Landing Run + center | Keep compose; only open floating |
| Non-terminal Run | Floating Run surface tabs |
| Approach | Hoist sync/bridge to `WorkspaceSplitPane` + floating Run surface |
