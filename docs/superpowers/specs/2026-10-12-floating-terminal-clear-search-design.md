# Floating Workspace Terminal Clear and Search

Date: 2026-10-12
Status: Approved (brainstorming)

## Problem

The floating-workspace shell terminal (`WorkspaceTerminalPanel` hosted by
`TerminalFloatingSurface` / `ShellTerminalSurface`) has a right-click menu
with copy, paste, select all, Ask AI, and open-link. It has no **Clear
terminal** and no **Find in terminal**.

The chat workbench terminal already has Find (context menu + overlay
`TerminalFindBar` + `Ctrl+Shift+F`). The Alacritty engine already exposes
`clearHistory()` (`ClearMode::Saved`, bound to `Ctrl+Shift+K`), which drops
scrollback only and leaves the current screen.

## Goals

- Right-click the floating workspace terminal to **Find in terminal** and
  **Clear terminal**.
- Find reuses the existing overlay bar and shortcuts (`Ctrl+Shift+F`, `F3`,
  `Shift+F3`, `Esc`). The bar searches the active tab only.
- Clear drops **scrollback and the current screen**. It does not kill the
  process and does not write to the PTY.

## Non-Goals

- Title-bar / toolbar buttons on the floating panel.
- Unifying the chat-workbench and workspace-terminal context menus.
- Adding Clear to the chat workbench terminal (can follow later).
- Sending `Ctrl+L` / `reset` into the PTY.
- Changing `clearHistory()` / `Ctrl+Shift+K` (scrollback-only stays).

## Decisions

Locked with the user (2026-10-12):

- Entry point: **right-click context menu** (not title-bar icons).
- Clear = **scrollback + current screen**.
- Approach: extend the workspace-terminal menu and reuse `TerminalFindBar`;
  add a dedicated engine `clearTerminal()` rather than merging the two
  terminal menus.

## Architecture

```
Right-click / Ctrl+Shift+F
        │
        ▼
WorkspaceTerminalPanel
  ├─ showWorkspaceTerminalContextMenu  (find, clear, copy/paste/…)
  ├─ TerminalFindShortcuts + TerminalFindBar overlay
  └─ entry.session.engine.clearTerminal()
           │
           ▼
flutter_alacritty: ClearMode::Saved then ClearMode::All
```

`WorkspaceTerminalPanel` is the only host of `ShellTerminalSurface`, so
this covers every floating shell tab without touching
`terminal_floating_surface.dart`.

### Engine (`client/packages/flutter_alacritty`, submodule)

`clearHistory()` stays `term.clear_screen(ClearMode::Saved)`.

Add `clear_terminal()`:

1. `ClearMode::Saved` (scrollback)
2. `ClearMode::All` (visible grid)
3. Dart client calls `refreshView()` (same as `clearHistory()`)

Wire it through the existing FRB stack: Rust `api/terminal.rs`
`engine_clear_terminal` → `EngineBinding.clearTerminal` →
`TerminalEngineClient` → `TerminalEngine.clearTerminal()`. Update fakes
(`FakeBinding` and copies). Keep `ClearHistoryIntent` on `clearHistory()`.

After clear: drop the current selection and, if Find is open, `searchClear()`
so highlights do not point at wiped cells. Leave Find bar visibility as-is
(user can keep typing a query against the empty buffer).

The running program is untouched. The prompt may stay blank until it prints
again.

### Context menu

Extract `_showContextMenu` from `workspace_terminal_panel.dart` (~639 lines)
into `widgets/workspace_terminal/workspace_terminal_context_menu.dart`,
mirroring `pages/chat/chat_workbench_context_menu.dart`.

Menu order (active session):

1. Find in terminal (`terminalFind`)
2. Clear terminal (`terminalClear`)
3. Open link (only when the click hit a hyperlink)
4. Existing paste / copy / Ask AI / select all

Find and Clear stay enabled whenever a session is showing. They do not
require a selection.

### Find overlay

Panel state: `bool _findVisible` for the **active** entry. Switching tabs
or disposing the panel closes Find and `searchClear()`s the previous
controller.

When `_findVisible`, wrap the session body in `TerminalFindShortcuts` and
stack `TerminalFindBar` at `top/left/right: 8` (no chat Chat/Terminal
capsule, so do not use the workbench `top: 48`).

Shortcuts match chat: `Ctrl+Shift+F` toggle, `F3` / `Shift+F3` next/prev,
`Esc` close.

### l10n

Edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only:

| Key | en | zh |
|-----|----|----|
| `terminalClear` | Clear terminal | 清除终端 |

Reuse `terminalFind` / `terminalFindNoResults`. Find-bar Previous/Next/Close
tooltips stay as they are on the chat bar (out of scope to l10n them here).

## Error handling

- Unbound engine: `clearTerminal()` is a no-op (same as `clearHistory()`).
- Empty search query: existing `TerminalFindBar` already clears marks.
- No confirmation dialog for Clear.

## Testing

- **Rust:** `clear_terminal` drops scrollback (`display_offset == 0`) and
  blanks the viewport (cells are default/empty after a filled grid). Leave
  `clear_history_drops_scrollback` unchanged.
- **Dart engine fakes:** `clearTerminal()` on `EngineBinding` /
  `FakeBinding`; client test that it refreshes the view.
- **Context menu widget test:** menu lists Find and Clear; choosing Find
  calls `onFindRequested`; choosing Clear calls `onClearTerminal`.
- **Find host:** visible flag shows `TerminalFindBar`; close / tab change
  hides it.
- Finish with `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
  and `dart run tool/run_tests.dart` (never `flutter test` directly).

## Out of file-growth

Do not grow `_showContextMenu` inside `workspace_terminal_panel.dart`. The
extracted menu file owns item list + actions; the panel owns find-visible
state, overlay, and engine call.
