# TpHover interactive surface + click-cursor migration

**Date:** 2026-08-02  
**Status:** implemented  
**Scope:** Strengthen `TpHover` / `TpHoverRow` in `client/packages/shared_ui`; recompose `TpTabChip` on `TpHover`; migrate eligible hand-rolled hover/`MouseRegion` interactive chrome across TeamPilot app + `ai_message_ui` so clickable UI gets a click cursor and stops duplicating hover state scaffolding.  
**Owner constraints:** best architecture / extensibility; **no** backward compatibility shims; workload not a limiting factor for eligible call sites.

## Problem

1. Many clickable controls use bare `MouseRegion` + `GestureDetector` / `InkWell` **without** `cursor: SystemMouseCursors.click`, so desktop hover does not show a hand pointer.
2. The same hover scaffolding is copy-pasted: local `_hovered`, `onEnter`/`onExit`, idle vs hover fill, and (for chips) active/hover accent alphas.
3. `shared_ui` already exposes `TpHover` / `TpHoverRow`, but they are underused; TeamPilot’s `TpHover` lags the richer huji twin (`backgroundColor`, `enabled`, `onLongPress`, `pressScale`).
4. `TpTabChip` still owns an outer `MouseRegion` stack and does not get click cursor from the shared primitive.

## Goals

1. Make **`TpHover` the canonical interactive chrome wrapper** in `shared_ui` (aligned with huji’s API surface).
2. Guarantee **click cursor** when the surface is interactive and enabled.
3. Recompose **`TpTabChip`** on `TpHover` (idle selected fill via `backgroundColor`; accent/border remain chip-owned).
4. Migrate **eligible** product call sites (rows, cards, chips, toolbar/status items, file-tree/git rows, `ai_message_ui` chrome) off hand-rolled hover.
5. Document the convention in `shared_ui/README.md`.

## Non-goals

- Adding `selected` / border / accent APIs to `TpHover`.
- Introducing a separate `TpSelectableSurface` (selected visuals stay in specialized widgets or host `Decoration` + `backgroundColor`).
- Syncing / committing changes into the huji repo (TeamPilot `shared_ui` only).
- Changing vendored packages (`window_manager`, `flutter-shadcn-ui`, toast engine internals, terminal view, resize handles).
- Visual redesign of cards/chips beyond wiring through `TpHover`.
- Forcing widget tests for every app migration site.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Architecture | **Lean `TpHover` + composition** — interaction primitive only; selected fill via `backgroundColor`; border/accent/shadow stay in chip/card |
| Rejected | Fat `TpHover` with `selected`+border; separate `TpSelectableSurface` |
| Package | `client/packages/shared_ui` |
| Compat | **None** — extend `TpHover` in place |
| Cursor | Default: interactive+enabled ⇒ `SystemMouseCursors.click`, else `basic`; overridable via `cursor` |
| huji parity | Port: `backgroundColor`, `enabled`, `onLongPress`, `pressScale` (default `1.0`) |
| Secondary menu coords | **`TpHover` adds `GestureTapDownCallback? onSecondaryTapDown`** (TeamPilot needs global position for `TpActionMenu`; huji has only `onSecondaryTap`) — either callback may be set; both count toward interactive |
| `TpTabChip` | Outer shell = `TpHover`; wire chip `onSecondaryTapDown` / `onLongPress` through; single tap path (no GestureDetector+InkWell double `onTap`); chrome via `onHoverChanged` |
| `TpHoverRow` | Forward new `TpHover` knobs used by rows: `backgroundColor`, `enabled`, `onLongPress`, `onSecondaryTap` / `onSecondaryTapDown`; sites needing only those can stay on `TpHoverRow` |
| Migration breadth | **Eligible sites in one workstream** after primitive + chip; exclude special-cursor / non-click / hover-only probes |
| Drag + hover rows | Prefer wrapping the **non-drag hit target** in `TpHover`, or pass `onTap` into `TpHover` while keeping `Draggable` as ancestor/sibling — do **not** nest competing `GestureDetector`s that steal drag; if ambiguous, migrate cursor/`onHoverChanged` only and leave drag gesture owner unchanged |
| `TpButton` / `TpIconButton` | Keep as-is (already provide appropriate cursors) |

## Architecture

```
shared_ui
  TpHover          ← interaction: cursor, hover fill, idle backgroundColor,
  TpHoverRow       ←    enabled, long-press, optional pressScale, onHoverChanged
  TpTabChip        ← composes TpHover; owns accent bar, active border, chrome fade
       │
       ├─ app hosts (shell/floating/run chips already on TpTabChip)
       ├─ list/sidebar rows, cards, status items, file tree / git rows
       └─ ai_message_ui interactive chrome
```

### `TpHover` API (target)

```dart
class TpHover extends StatefulWidget {
  const TpHover({
    required this.child,
    this.hoverColor,
    this.backgroundColor, // idle fill; host passes selected fill here
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown, // preferred for positioned context menus
    this.onLongPress,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.duration = const Duration(milliseconds: 120),
    this.cursor,
    this.forceHover = false,
    this.onHoverChanged,
    this.width,
    this.height,
    this.enabled = true,
    this.pressScale = 1.0,
    super.key,
  });
}
```

**Interactive** iff `enabled` and any of `onTap` / `onSecondaryTap` / `onSecondaryTapDown` / `onLongPress` is non-null.

**Fill rule:** when `enabled` is false, never enter hover fill (ignore pointer enter; clear pressed). When enabled: show `hoverColor` (or `defaultHoverColor`) while hovered or `forceHover`; otherwise `backgroundColor ?? transparent`.

### `TpTabChip` composition

```
Tooltip
 └─ TpHover(
      onTap / onSecondaryTapDown / onLongPress,
      backgroundColor: active ? surfaceContainerHigh : null,
      hoverColor: inactive hover tint (active may keep idle or subtle hover),
      onHoverChanged → _hovered for chrome + accent alphas,
    )
      └─ border decoration when active
           └─ Row: accent | leading/working | title | actions | close(TpHover)
```

Chrome visibility unchanged: `active || hovered || forceShowChrome || Android`. Chip public API keeps `onSecondaryTapDown` (positioned menus) and forwards it to `TpHover`.

### Migration include / exclude

**Include:** clickable product chrome that today hand-rolls `_hovered` / bare `MouseRegion` for tap — sidebar/list rows, hub/workspace cards, status-bar items, file tree / git change rows (see drag rule above), `TpTabChip`, `ai_message_ui` **action** chrome (e.g. message action bar, tool header buttons).

**Exclude:** window drag/caption/resize; terminal; toast engine; vendored UI; **hover-only** probes with no tap (e.g. fade/expand reveal `MouseRegion`s in `ai_message_ui`); controls that already use `TpButton` / `TpIconButton` / correctly cursored `InkWell`.

### Delivery order (single workstream)

1. Extend `TpHover` (+ tests) to huji parity.
2. Recompose `TpTabChip` on `TpHover` (+ chip tests).
3. Migrate eligible app + `ai_message_ui` call sites.
4. Update `shared_ui/README.md` convention.

## Testing

| Surface | Coverage |
|---------|----------|
| `TpHover` | click cursor when interactive; basic when disabled/non-interactive; `backgroundColor` idle; hover/`forceHover` fill; `onHoverChanged`; `onLongPress`; `onSecondaryTapDown` delivers `TapDownDetails`; `pressScale` when ≠ 1.0 |
| `TpHoverRow` | trailing visibility: hover / Android / `forceShowTrailing` |
| `TpTabChip` | tap/close; active border; hover chrome; Android always-show chrome; click cursor |

App: fix broken host tests only; run `flutter analyze` + `flutter test --exclude-tags integration` (including `shared_ui` package tests).

## Documentation

`shared_ui/README.md`: prefer `TpHover` / `TpHoverRow` for clickable chrome; do not ship bare `MouseRegion` without cursor for onTap UI; selected idle fill via `backgroundColor`, not a `selected` flag on `TpHover`.

## Relationship to other work

Complements `2026-08-02-tp-tab-strip-design.md` (strip/chip extraction). This spec does **not** redo strip reorder; it only fixes the chip’s interaction shell and the broader hover/cursor inconsistency.
