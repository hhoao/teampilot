# Floating panel title-bar gestures, Esc minimize, and unified surface color

**Date:** 2026-08-01  
**Status:** implemented (2026-08-01)  
**Scope:** `FloatingWorkspacePanel` chrome + panel-local / open-gated keyboard (`client/lib/pages/floating_workspace/`, command wiring as needed)

## Problem

The floating workspace panel already supports maximize via chrome buttons and keyboard commands, but:

1. Double-clicking the title bar does nothing (desktop windows usually toggle maximize/restore).
2. While maximized, title-bar drag is disabled (`allowDragResize: !isMaximized`), so users cannot drag-to-restore.
3. Panel body uses `colorScheme.workspaceCard` while the title bar uses `workspaceSubtleSurface`, so the chrome and content look like two stacked surfaces.
4. There is no Escape → minimize path; users expect Esc to dismiss/minimize the open floating panel (including when focus is inside a terminal or editor tab).

## Goals

1. **Double-click title bar** toggles maximize ↔ restore (same semantics as the maximize chrome button while the panel is already open).
2. **Drag while maximized** exits maximize and continues a **pointer-following** drag (Windows-like).
3. **Content background** matches the title bar (`workspaceSubtleSurface`).
4. **Escape** minimizes the floating panel whenever it is **open**, even if focus is inside a terminal or file editor surface.

## Non-goals

- Changing minimize (dash) button behavior or “minimize on double-click”.
- Changing maximize insets / safe-area math.
- New persistence fields (restore size already lives in `panelPlacement`).
- Snap-to-maximize on screen edges or animated maximize/restore.
- Guaranteeing Windows-identical double-click behavior on tab chips (see gesture note below).
- Two-step Esc (restore-then-minimize); Esc always minimizes while open.
- Binding Esc when the panel is hidden or minimized (must not steal Esc from dialogs / find bars / other chrome).

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Approach | Enhance existing `_TitleBar` / `_PanelChromeFrame` gesture path (no new controller type) |
| Drag vs resize flags | Split today’s `allowDragResize` into `allowTitleDrag` (true whenever panel is open, including maximized) and `allowEdgeResize` (true only when open **and** not maximized) |
| Double-click target | Title-bar drag region (wraps tab bar); **exclude** maximize/minimize icon buttons |
| Double-click action | While panel is open: `setMaximized(!isMaximized)` — never `minimize()`, never CommandBus hidden→open branch |
| Drag while maximized | Title pan allowed; first pan start unmaximizes then follows pointer |
| Restore size | Same size resolution as `_resolvePlacedRect`: `panelPlacement.resolve(host)`, else clamped `legacyAbsoluteBounds`, else `defaultFloatingPanelPlacement(toggleOffset)` — **width/height only**; left/top come from the follow-pointer formula |
| Coordinate space | Use **host-local** coordinates for fracX / restored left/top (`RenderBox.globalToLocal` on the host overlay). Keep existing drag **delta** math on `details.globalPosition` after restore is seeded |
| Maximized rect for fracX | Current maximized `positioned` rect (includes `FloatingMaximizeInsets` safe area) — not bare `hostSize` |
| Follow-pointer placement | See algorithm below |
| Seed order | Write `_gestureBounds` / call `onGestureBegin(restoredRect)` **before** `setMaximized(false)` so the first non-maximized frame does not flash the old inset-anchored placement |
| Drag start anchors | After restore: `_dragStartBounds = restoredRect` (clamped); `_dragStartPointer = pan-start globalPosition`; later updates = existing `start + delta` |
| Title bar height | `_kTitleBarHeight` (40 logical px) |
| Content color | Panel `Material.color` = `cs.workspaceSubtleSurface` (same as title bar) |
| Resize while maximized | Still disabled (`allowEdgeResize == false`) |
| Esc minimize | While `visibility == open`, Escape → same as chrome minimize / `CommandIds.floatingMinimize` (`cubit.minimize()`). **Not** restore-first. |
| Esc focus policy | **Always** while open — including focus inside floating terminal or editor, and when focus is elsewhere in the workspace shell (product choice). |
| Esc interception | Follow the existing keyboard platform (see `terminal_passthrough_shortcuts.dart`): `HardwareKeyboard` / `ShortcutDispatcher` returning handled does **not** stop `TerminalView` PTY encode. Esc must (1) fire minimize via open-gated dispatcher/`CommandBus`, and (2) appear in the focused terminal’s `TerminalView.shortcuts` overlay as `DoNothingAndStopPropagationIntent` (same pattern as other `terminalPassthrough` chords) so PTY never receives Esc. Editor surfaces need an equivalent leaf claim while open. |
| Esc open-gate | Prefer `CommandIds.floatingMinimize` + Escape chord with a new `ShortcutWhen.floatingPanelOpen` (and `ShortcutContext.floatingPanelOpen` from cubit visibility). **Do not** leave Escape in the terminal overlay when the panel is not open — otherwise dock/session terminals would swallow Esc without minimizing. Either filter `terminalPassthroughShortcutOverlay` by satisfied `when`, or build floating-terminal shortcuts with an Esc claim only inside the floating surface. |
| Esc when not open | No Escape minimize binding while hidden or minimized; modal/rebind/`ShortcutDispatcher.enabled == false` still win. |
| Esc vs close_shortcut | Do **not** treat `FloatingWorkspaceCloseShortcut` as the primary Esc path (it only owns Ctrl/Cmd+W). Esc is command-platform + terminal/editor leaf overlay. |

## Behavior detail

### Double-click

```
title-bar drag region double-tap/click
  → FloatingWorkspaceCubit.setMaximized(!state.isMaximized)
```

Chrome maximize/minimize buttons keep current behavior (CommandBus when available).

**Gesture note:** Tab chips keep their own `onTap`. Double-click on a tab chip follows Flutter’s gesture arena; we do **not** require Windows-parity maximize-on-tab-double-click. Prefer double-click on empty title chrome / non-button area for the guaranteed path. A completed pan must not synthesize a double-tap.

### Drag-to-restore (maximized → floating)

On title-bar `onPanStart` while `isMaximized`:

1. Let `maxRect` = current maximized `panelBounds` (safe-inset positioned rect).
2. Resolve restore size via the same path as `_resolvePlacedRect(state, hostSize)` → take `width`/`height` only as `restoredW`/`restoredH`.
3. Convert pan-start `globalPosition` → host-local `(pointerX, pointerY)`.
4. Compute restored rect in host-local space:
   - `fracX = ((pointerX - maxRect.left) / maxRect.width).clamp(0.0, 1.0)`
   - `left = pointerX - fracX * restoredW`
   - `top = pointerY - (_kTitleBarHeight / 2)`
   - `restoredRect = clampFloatingPanelBounds(Rect.fromLTWH(left, top, restoredW, restoredH), hostSize)`
5. Seed gesture **before** clearing maximize:
   - `_dragStartBounds = restoredRect`
   - `_dragStartPointer = details.globalPosition`
   - `onGestureBegin(restoredRect)` (sets `_gestureBounds` immediately)
6. Then `setMaximized(false)`.
7. Subsequent `onPanUpdate`: existing logic  
   `clamp(Rect.fromLTWH(start.left + delta.dx, start.top + delta.dy, start.width, start.height), host)`  
   where `delta = globalPosition - _dragStartPointer`.
8. `onPanEnd` → `setPanelRect` as today.

When **not** maximized, title pan behavior is unchanged (start bounds = current floating `panelBounds`).

### Escape → minimize

```
visibility == open + Escape key down
  → ShortcutDispatcher matches floatingMinimize (when: floatingPanelOpen)
  → CommandBus → cubit.minimize()
  → if focus in terminal: TerminalView.shortcuts overlay stops PTY encode
  → if focus in floating editor: leaf Shortcuts claim Esc equivalently
```

- Maximized + Esc → minimize (`isMaximized` retained while minimized — existing cubit behavior).
- Hidden / minimized → `floatingPanelOpen` unsatisfied → no match; Esc not claimed by floating overlay.
- Does not close tabs (unlike Ctrl/Cmd+W on a tab); only minimizes the panel.
- Implementation note: if `terminalPassthroughShortcutOverlay` today ignores `when`, either teach it to filter by `ShortcutContext`, or add Esc only on the floating terminal surface’s shortcut map so workspace dock terminals keep receiving Esc.

### Background

```
Material(
  color: cs.workspaceSubtleSurface,  // was workspaceCard
  ...
)
```

Title bar already uses `workspaceSubtleSurface`; no title-bar color change.

## Files

| File | Change |
|------|--------|
| `floating_workspace_panel.dart` | Split drag/resize flags; double-tap on title drag region; maximized title pan → unmaximize + follow-pointer seed; unify Material color |
| `command_catalog.dart` / `command_definition.dart` / `shortcut_context.dart` | Escape chord on `floatingMinimize`; `ShortcutWhen.floatingPanelOpen` + context field wired from floating visibility |
| `terminal_passthrough_shortcuts.dart` and/or floating terminal surface | Ensure Esc is claimed in floating terminal shortcuts **only while open**; do not permanently steal Esc from dock terminals |
| Floating editor surface (if needed) | Leaf Esc claim while that surface is focused |
| Widget / command tests | Double-click; drag-to-restore; Esc minimize (open + in-terminal focus); Esc inactive when minimized; chrome/resize regressions |

Cubit API unchanged (`setMaximized`, `setPanelRect`, `minimize` already sufficient).

## Test plan

Fixed host **1400×900**, known `panelPlacement` **600×400** (with known insets), and known maximize safe insets so expected restore math is deterministic.

1. **Double-click:** open panel → double-tap title drag region → `isMaximized == true`; double-tap again → `false`. Assert `minimize()` is **not** called / visibility stays `open`.
2. **Drag-to-restore (numeric):** maximize → `panStart` on title bar at host-local point with `fracX = 0.5` on `maxRect` → assert `isMaximized == false`, first gesture/panel bounds `width/height == 600×400` (≠ maximized size), and `left/top` match the formula above after `clampFloatingPanelBounds`.
3. **Follow-through:** after restore, continue pan by a known delta → left/top move by that delta (clamped).
4. **Esc minimize:** open panel → send Escape → `visibility == minimized`. With focus forced into a floating terminal surface, Esc still minimizes **and** the terminal shortcut overlay claims Esc (no PTY write in the test double / passthrough assert).
5. **Esc gated:** panel minimized/hidden → Escape does **not** invoke `floatingMinimize`; a non-floating/dock terminal must still be able to receive Esc (overlay must not permanently swallow it).
6. **Regression:** maximize / minimize chrome buttons still work; while maximized, resize handles are absent; while floating, resize handles present; Ctrl/Cmd+W close-tab path unchanged.
7. **Color:** panel `Material.color` equals `Theme.colorScheme.workspaceSubtleSurface`.
8. **(Optional)** drag-to-restore when only `legacyAbsoluteBounds` is set (no `panelPlacement`).

## Out of scope follow-ups

- Snap-to-maximize when dragging to screen edge.
- Animate maximize/restore transitions.
- Force double-click maximize when the pointer is exactly on a tab chip.
- Esc restore-then-minimize two-step.
- User-rebindable Escape for floating minimize in shortcut settings (can follow later via command catalog if desired).
