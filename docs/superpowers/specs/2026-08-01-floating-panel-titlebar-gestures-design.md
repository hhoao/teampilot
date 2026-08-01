# Floating panel title-bar gestures + unified surface color

**Date:** 2026-08-01  
**Status:** design (approved in chat; awaiting written-spec review)  
**Scope:** `FloatingWorkspacePanel` chrome only (`client/lib/pages/floating_workspace/`)

## Problem

The floating workspace panel already supports maximize via chrome buttons and keyboard commands, but:

1. Double-clicking the title bar does nothing (desktop windows usually toggle maximize/restore).
2. While maximized, title-bar drag is disabled (`allowDragResize: !isMaximized`), so users cannot drag-to-restore.
3. Panel body uses `colorScheme.workspaceCard` while the title bar uses `workspaceSubtleSurface`, so the chrome and content look like two stacked surfaces.

## Goals

1. **Double-click title bar** toggles maximize ↔ restore (same semantics as the maximize chrome button / `CommandIds.floatingMaximize`).
2. **Drag while maximized** exits maximize and continues a **pointer-following** drag (Windows-like).
3. **Content background** matches the title bar (`workspaceSubtleSurface`).

## Non-goals

- Changing minimize (dash) behavior or “minimize on double-click”.
- Changing maximize insets / safe-area math.
- New persistence fields (restore size already lives in `panelPlacement`).
- Touch-specific affordances beyond existing pan/double-tap.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Approach | Enhance existing `_TitleBar` / `_PanelChromeFrame` gesture path (no new controller type) |
| Double-click target | Title-bar row **excluding** maximize/minimize icon buttons |
| Double-click action | `setMaximized(!isMaximized)` only — never `minimize()` |
| Drag while maximized | Allowed on title bar; first drag interaction unmaximizes then follows pointer |
| Restore size | Last non-maximized `panelPlacement` (or default placement if never placed) |
| Follow-pointer placement | Map pointer’s fractional X across the maximized title bar onto the restored width; Y ≈ pointerY − titleBarHeight/2; then `clampFloatingPanelBounds` |
| Content color | Panel `Material.color` = `cs.workspaceSubtleSurface` (same as title bar) |
| Resize while maximized | Still disabled (edges remain off) |

## Behavior detail

### Double-click

```
title-bar (tabs / drag region) double-tap/click
  → FloatingWorkspaceCubit.setMaximized(!state.isMaximized)
```

Chrome buttons keep current behavior. Double-click must not fire when the gesture was a drag (Flutter: prefer `onDoubleTap` alongside pan; if both conflict, accept that a completed pan does not synthesize a double-tap).

### Drag-to-restore (maximized → floating)

On title-bar pan while `isMaximized`:

1. Resolve restored size from current `panelPlacement` / default placement (`width`/`height` only).
2. Compute restored `Rect`:
   - `fracX = ((pointerX - maximizedLeft) / maximizedWidth).clamp(0, 1)`
   - `left = pointerX - fracX * restoredWidth`
   - `top = pointerY - titleBarHeight / 2`
   - clamp with existing `clampFloatingPanelBounds`
3. `setMaximized(false)` and seed gesture bounds with that rect (`onGestureBegin` + `onGestureUpdate`).
4. Subsequent pan updates use the same delta math as today’s non-maximized drag, anchored at the unmaximize start pointer/bounds.
5. `onPanEnd` → `setPanelRect` as today.

Edge resize handles stay gated on `!isMaximized`.

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
| `floating_workspace_panel.dart` | Double-tap on title drag region; allow title pan when maximized; unmaximize+reposition on drag start; unify Material color |
| `floating_workspace_panel_bounds_test.dart` and/or new widget test | Double-click toggles maximize; maximized drag clears maximize and moves rect; optional color assert |

Cubit API unchanged (`setMaximized`, `setPanelRect` already sufficient).

## Test plan

1. Widget: open panel → double-tap title drag region → `isMaximized == true`; double-tap again → `false`.
2. Widget: maximize → pan title bar → `isMaximized == false` and panel left/top track pointer (not stuck at previous absolute rect).
3. Regression: maximize button / minimize button still work; resize handles absent while maximized.
4. Visual: body and title bar share `workspaceSubtleSurface` (theme assert or golden-free color check).

## Out of scope follow-ups

- Snap-to-maximize when dragging to screen edge.
- Animate maximize/restore transitions.
