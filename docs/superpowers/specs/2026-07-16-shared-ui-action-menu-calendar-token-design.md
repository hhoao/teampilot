# shared_ui: TpActionMenu, TpDateRangePicker, TpTokenTextField

**Status:** Landed  
**shared_ui SHA:** `901e0538e5611a22c6e94b4979b76139a6168166`  
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
3. Lift **`TpTokenTextField`** into the package **with** chip mirror + field edit helpers; TeamPilot keeps only **product palette / compose** wiring.
4. Single delivery wave: publish `shared_ui` → bump → remount TeamPilot + Huji call sites; delete app-local duplicates.
5. Public API uses **`Tp*`** names only — no `typedef` / compatibility aliases for old `SidebarActionMenu*` / `AppDateRangePicker` / `InlineTokenTextField`.

## Non-goals

- Moving appearance / desktop chrome back into `shared_ui`.
- Porting Huji’s `PopupMenuEntry`-based menu branch (discard; unify on TeamPilot/`TpPopover`).
- Keeping product-specific slash/@ palette tables / compose wiring in the package (those stay in TeamPilot).
- Visual redesign of menus/calendars beyond rename + shared tokens.
- Splitting into multiple publish waves (user chose one PR wave).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Delivery | One PR wave (package + both apps) | User preference; avoid dual-track |
| Menu canonical source | TeamPilot (`TpPopover` + overlay) | Matches package primitives |
| Naming | `Tp*` rename, remount call sites | Consistent design-system API |
| Calendar | Into package from Huji; **rewire** `AppPopover`→`TpPopover`, `HoverWidget`→`TpHover`; **add `intl`** for `DateFormat.yMMMM` | Compiles in package without Huji popover fork |
| Inline token | Package owns **field + chip mirror + keyboard edit helpers** the shell needs; TeamPilot keeps **product palette resolvers** / compose wiring | Avoids package→app imports; clears ownership |
| Menu position util | Lift **`contextMenuGlobalPosition`** (used by `show*AtTap`); do **not** treat `contextMenuPositionForGlobal` (`RelativeRect`/`showMenu`) as overlay dep — that is the discarded Huji/`showMenu` path | Matches TeamPilot call graph |
| Approach | Lift-and-rename | No temporary dual implementations |

## Architecture

```
shared_ui
  components/action_menu/   ← TeamPilot widgets/menu (+ overlay)
  components/date_range/    ← Huji calendar, on TpPopover + TpHover + intl
  components/token_field/   ← TpTokenTextField + chip mirror + edit helpers + palette typedefs
  (+ contextMenuGlobalPosition util for show*AtTap)

TeamPilot app
  delete widgets/menu, widgets/inline_token (widget)
  keep product palette / compose services (thin wrappers over package typedefs OK)
  call sites → package:shared_ui
  other chip-mirror consumers (e.g. compose trigger styles) → import package

Huji app
  delete widgets/menu, widgets/calendar (+ orphaned AppPopover copies if unused)
  call sites → package:shared_ui
```

### Package layout

| Path | Responsibility |
|------|----------------|
| `lib/src/components/action_menu/` | Metrics, panel, item, divider, spec, button, icon/popover anchors, show helpers, floating overlay |
| `lib/src/components/date_range/` | `TpDateRangePicker` (`TpPopover`), `TpRangeCalendar` (`TpHover` + `intl`), date utils |
| `lib/src/components/token_field/` | `TpTokenTextField`; chip mirror; backspace/delete token edit helpers; `TpTokenPalette` / resolver typedefs |
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
| `InlineTokenTextField` (+ chip mirror / edit helpers it needs) | `TpTokenTextField` (+ `TpTokenChipMirror` / edit APIs as needed) |

**Position util:** move `contextMenuGlobalPosition` into the package (or colocate under `action_menu/`). Leave `contextMenuPositionForGlobal` in TeamPilot only if still used by non-menu `showMenu` call sites; it is **not** required for `TpActionMenu` overlay.

### `TpTokenTextField` boundary (locked)

- **In package (required for a compiling shell):** `TpTokenTextField`, chip-mirror painting, token range / backspace-delete helpers the field uses, `TpTokenPalette` + `TpTokenPaletteResolver` typedefs. No imports of TeamPilot.
- **In TeamPilot:** product `resolveSlashAtTokenPalette` (or equivalent), default token `RegExp`s for compose, call-site wiring of resolver/pattern into `TpTokenTextField`. Re-export or thin-wrap package mirror only if other app widgets need the same painting API.

## Migration

1. **shared_ui:** Copy/rename TeamPilot menu (+ `contextMenuGlobalPosition`); lift Huji calendar with `TpPopover`/`TpHover`/`intl` rewires; move token field + chip mirror + edit helpers; add `intl` dependency; tests + README; merge to `main`; record SHA.
2. **TeamPilot:** Bump submodule; replace imports/symbols; delete local menu + inline_token widget; point remaining chip-mirror consumers at package; keep product palette services; analyze green.
3. **Huji:** Bump same SHA; replace symbols; delete vendored menu/calendar; drop unused `AppPopover` tree if nothing else needs it; analyze green.

Order inside the wave may be package-first commits then app remounts; consumers must not pin a broken intermediate on `main` without matching app changes (feature branches OK).

## Testing / acceptance

- `shared_ui`: `flutter test` (new widget tests for menu open/select, date-range selection smoke, token field basic render).
- TeamPilot + Huji: `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 errors.
- Grep: no `SidebarActionMenu`, `showSidebarActionMenu`, `showFloatingActionMenuOverlay`, `AppDateRangePicker`, `InlineTokenTextField` in app `lib/` (except comments/docs); product services may keep domain names wrapping package typedefs.
- Smoke: TeamPilot context/overflow menus; Huji task date filter; TeamPilot token input field.

## Risks

| Risk | Mitigation |
|------|------------|
| Huji behavior change dropping `PopupMenuEntry` / `AppPopover` paths | Accept `TpPopover` parity; smoke Huji filter menus + date picker |
| Large PR surface | Logical commits inside wave; single bump SHA for apps |
| Token field / mirror drift vs compose styles | Move mirror into package once; update all TeamPilot consumers in same wave |
| Hardcoded calendar clear label (`清除`) | Accept for this wave; i18n follow-up |

## Out of scope follow-ups

- Preferencing `TpSelect` vs action menu for dense settings rows.
- Full calendar i18n (clear label, weekday headers) beyond current Huji patterns.
