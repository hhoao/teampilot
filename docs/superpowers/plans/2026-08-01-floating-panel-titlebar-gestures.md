# Floating panel title-bar gestures + Esc minimize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Title-bar double-click toggles maximize; maximized drag restores follow-the-pointer; Esc minimizes while the floating panel is open (including terminal/editor focus); panel body uses `workspaceSubtleSurface`.

**Architecture:** Gesture work stays in `floating_workspace_panel.dart`. Esc uses the existing command platform: `ShortcutWhen.floatingPanelOpen` + Escape on `floatingMinimize`, `ShortcutContext` from `FloatingWorkspaceCubit`, terminal overlay filtered by satisfied `when`, and bare Escape allowed through the `inTextInput` gate.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, `ShortcutDispatcher` / `KeybindingResolver`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-01-floating-panel-titlebar-gestures-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/commands/command_definition.dart` | Add `ShortcutWhen.floatingPanelOpen` |
| `client/lib/services/commands/shortcut_context.dart` | Add `floatingPanelOpen`; evaluate new when |
| `client/lib/services/commands/key_chord.dart` | Map `escape` ↔ `LogicalKeyboardKey.escape` |
| `client/lib/services/commands/command_catalog.dart` | `floatingMinimize`: Escape chord + `when: floatingPanelOpen` |
| `client/lib/services/commands/keybinding_resolver.dart` | Bare Escape not blocked by `inTextInput` |
| `client/lib/services/commands/terminal_passthrough_shortcuts.dart` | Filter overlay entries by satisfied `when` when context provided |
| `client/lib/widgets/terminal/teampilot_alacritty_terminal.dart` | Pass live `ShortcutContext` (incl. floating open) into overlay |
| `client/lib/main.dart` | Wire `FloatingWorkspaceCubit` into `_liveShortcutContext` |
| `client/lib/pages/floating_workspace/floating_workspace_panel.dart` | Split drag/resize flags; double-tap; drag-to-restore; subtle surface color |
| Tests under `client/test/…` | Esc when/overlay/resolver; panel gesture + color widget tests |

---

### Task 1: Escape chord + `floatingPanelOpen` when

**Files:**
- Modify: `command_definition.dart`, `shortcut_context.dart`, `key_chord.dart`, `command_catalog.dart`, `keybinding_resolver.dart`
- Modify: `main.dart` (`_liveShortcutContext`)
- Test: `keybinding_resolver_test.dart`, extend or add chord escape mapping coverage

- [ ] **Step 1: Write failing tests** — Escape matches `floatingMinimize` only when `floatingPanelOpen`; bare Escape matches even with `inTextInput: true`; does not match when panel closed.
- [ ] **Step 2: Run tests — expect fail**
- [ ] **Step 3: Implement enum/context/chord/catalog/resolver/main wiring**
- [ ] **Step 4: Run tests — expect pass**

### Task 2: Terminal overlay respects `when`

**Files:**
- Modify: `terminal_passthrough_shortcuts.dart`, `teampilot_alacritty_terminal.dart`
- Test: `terminal_passthrough_shortcuts_test.dart`

- [ ] **Step 1: Failing test** — with Escape on floatingMinimize + `floatingPanelOpen: false`, overlay must **not** accept Escape; with `true`, it must.
- [ ] **Step 2: Run — fail**
- [ ] **Step 3: Add optional `ShortcutContext` to overlay builder; skip defs whose `when` is unsatisfied; wire terminal widget to watch floating cubit when available
- [ ] **Step 4: Run — pass**

### Task 3: Panel color + title double-click + drag-to-restore

**Files:**
- Modify: `floating_workspace_panel.dart`
- Test: new/extended `floating_workspace_panel_*_test.dart` (widget)

- [ ] **Step 1: Failing widget tests** — Material color == `workspaceSubtleSurface`; double-tap title toggles maximize; maximized panStart clears maximize and seeds follow-pointer bounds
- [ ] **Step 2: Run — fail**
- [ ] **Step 3: Implement flags split, `onDoubleTap`, maximized pan unmaximize algorithm, Material color
- [ ] **Step 4: Run — pass**

### Task 4: Verification

- [ ] `cd client && flutter test test/services/commands/keybinding_resolver_test.dart test/services/commands/terminal_passthrough_shortcuts_test.dart test/pages/floating_workspace/ --exclude-tags integration`
- [ ] Spot-check `flutter analyze` on touched files if needed

**Commit:** only if user asks.
