# shared_ui: TpActionMenu, TpDateRangePicker, TpTokenTextField

**Status:** Approved (design)  
**Date:** 2026-07-16  
**Related:** Huji Tp* adapt (`huji` repo: `docs/superpowers/specs/2026-07-16-huji-tp-shared-ui-adapt-design.md`); theme consolidation / TpToast already on `shared_ui` `main`

## Problem

TeamPilot and Huji each keep copies (or forks) of action-menu and related composites outside `shared_ui`:

- TeamPilot: `client/lib/widgets/menu/` (`SidebarActionMenu*`, `TpPopover`-backed) — ~36 call-site files
- Huji: vendored older `widgets/menu/` + `widgets/calendar/` — ~8 call-site files; API diverged (`PopupMenuEntry` path)
- TeamPilot: `widgets/inline_token/` coupled to `services/inline_token/*`

`shared_ui` already owns `TpPopover` / tokens / preference primitives. Extending the package with these composites removes forks and grows a coherent design-system surface.

## Goals

1. Lift TeamPilot’s action menu into `shared_ui` as **`TpActionMenu*`** (canonical implementation).
2. Lift Huji’s date-range calendar as **`TpDateRangePicker` / `TpRangeCalendar`**, styled via action-menu metrics.
3. Extract a pure **`TpTokenTextField`** shell into the package; keep TeamPilot inline-token **services** in the app.
4. Single delivery wave: publish `shared_ui` → bump → remount TeamPilot + Huji call sites; delete app-local duplicates.
5. Public API uses **`Tp*`** names only — no `typedef` / compatibility aliases for old `SidebarActionMenu*` / `AppDateRangePicker` / `InlineTokenTextField`.

## Non-goals

- Moving appearance / desktop chrome back into `shared_ui`.
- Porting Huji’s `PopupMenuEntry`-based menu branch (discard; unify on TeamPilot/`TpPopover`).
- Moving `services/inline_token/*` (chip mirror internals may stay app-side or move only if kept framework-agnostic and required by the shell — prefer callbacks/resolver).
- Visual redesign of menus/calendars beyond rename + shared tokens.
- Splitting into multiple publish waves (user chose one PR wave).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Delivery | One PR wave (package + both apps) | User preference; avoid dual-track |
| Menu canonical source | TeamPilot (`TpPopover` + overlay) | Matches package primitives |
| Naming | `Tp*` rename, remount call sites | Consistent design-system API |
| Calendar | Into package from Huji | Shared composite; depends on menu metrics |
| Inline token | Shell only (`TpTokenTextField`) | Package stays free of product services |
| Approach | Lift-and-rename | No temporary dual implementations |

## Architecture

```
shared_ui
  components/action_menu/   ← TeamPilot widgets/menu (+ overlay)
  components/date_range/    ← Huji widgets/calendar
  components/token_field/   ← TpTokenTextField (+ minimal palette typedefs)
  (+ contextMenuPositionForGlobal util used by overlay)

TeamPilot app
  delete widgets/menu, widgets/inline_token (widget)
  keep services/inline_token/*
  call sites → package:shared_ui

Huji app
  delete widgets/menu, widgets/calendar (+ orphaned transitive copies if unused)
  call sites → package:shared_ui
```

### Package layout

| Path | Responsibility |
|------|----------------|
| `lib/src/components/action_menu/` | Metrics, panel, item, divider, spec, button, icon/popover anchors, show helpers, floating overlay |
| `lib/src/components/date_range/` | `TpDateRangePicker`, `TpRangeCalendar`, date utils |
| `lib/src/components/token_field/` | `TpTokenTextField`; `TpTokenPalette` / resolver typedefs (or equivalent names) |
| Public barrel | Export new components from `shared_ui.dart` |

### Rename map

| Current | Package |
|---------|---------|
| `ActionMenuController` | `TpActionMenuController` |
| `SidebarActionMenuMetrics` | `TpActionMenuMetrics` |
| `SidebarActionMenuPanel` / `Item` / `Divider` / `Spec` / `Button` / `IconAnchor` / `PopupItem` | `TpActionMenu*` |
| `ActionMenuPopoverAnchor` | `TpActionMenuAnchor` |
| `showSidebarActionMenu*` / `showFloatingActionMenuOverlay` | `showTpActionMenu*` / `showTpActionMenuOverlay` |
| `AppDateRangePicker` / `AppRangeCalendar` | `TpDateRangePicker` / `TpRangeCalendar` |
| `InlineTokenTextField` | `TpTokenTextField` |

`contextMenuPositionForGlobal` moves into the package (menu overlay dependency).

### `TpTokenTextField` boundary

- **In package:** multiline field, token pattern matching, mirror/chip painting driven by injected `TpTokenPaletteResolver` (or equivalent), optional overlay hooks already on the widget.
- **In TeamPilot:** slash/@ palette resolution, edit helpers, product-specific token patterns wired at call sites.

## Migration

1. **shared_ui:** Copy/rename TeamPilot menu + Huji calendar + extract token field; add tests; document in README; merge to `main`; record SHA.
2. **TeamPilot:** Bump submodule; replace imports/symbols; delete local menu + inline_token widget files; analyze green.
3. **Huji:** Bump same SHA; replace symbols; delete vendored menu/calendar; drop unused popover copies if nothing else needs them; analyze green.

Order inside the wave may be package-first commits then app remounts; consumers must not pin a broken intermediate on `main` without matching app changes (feature branches OK).

## Testing / acceptance

- `shared_ui`: `flutter test` (new widget tests for menu open/select, date-range selection smoke, token field basic render).
- TeamPilot + Huji: `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 errors.
- Grep: no `SidebarActionMenu`, `showSidebarActionMenu`, `AppDateRangePicker`, `InlineTokenTextField` in app `lib/` (except comments/docs if any); services may keep `InlineToken*` names for domain types.
- Smoke: TeamPilot context/overflow menus; Huji task date filter; TeamPilot token input field.

## Risks

| Risk | Mitigation |
|------|------------|
| Huji behavior change dropping `PopupMenuEntry` path | Accept TeamPilot parity; smoke Huji filter menus |
| Large PR surface | Logical commits inside wave; single bump SHA for apps |
| Token field pulls services accidentally | Spec gate: resolver/callback only; review imports |

## Out of scope follow-ups

- Preferencing `TpSelect` vs action menu for dense settings rows.
- Full calendar i18n polish beyond current Huji strings/patterns.
