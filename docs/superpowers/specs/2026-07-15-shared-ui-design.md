# TeamPilot `shared_ui` design system

**Status:** Approved  
**Date:** 2026-07-15

## Problem

TeamPilot UI primitives are scattered under `client/lib/widgets/` with inconsistent naming (`App*`, ad-hoc shells, raw Material). Theme tokens live in `client/lib/theme/` but are not packaged as a reusable component library. A vendored `packages/flutter-shadcn-ui` exists for reference, but the app does not depend on it at runtime and has already forked patterns into `AppForm` / `AppTextarea` / `AppDropdownField`. We need a first-class design-system package with clear categories (Button, Input, Select, Card, …), consistent APIs, and a clean extraction into a git submodule — **no backward-compatibility shims**.

## Goals

1. Introduce `shared_ui` as an independent Flutter package (git submodule at `client/packages/shared_ui`).
2. Adopt shadcn-style **component categories + theme slots**, implemented in-house (no runtime dependency on `flutter-shadcn-ui`).
3. Public API uses the **`Tp` prefix** (`TpButton`, `TpCard`, `TpInput`, `TpSelect`, …).
4. Move design tokens + component themes into `shared_ui`; keep app-level assembly (color presets, font loading, `MaterialApp` wiring) in `client`.
5. Migrate existing generic `App*` primitives into `Tp*` and delete the old sources (no aliases).

## Non-goals

- Migrating domain shells (workspace chrome, settings hub, terminal, file tree, provider panels, brand logo).
- Depending on or forking `flutter-shadcn-ui` into the runtime graph.
- Overnight replacement of every raw `FilledButton` / `TextField` call site (follow-up PRs may adopt `Tp*` progressively).
- Localization, routing, bloc, or repository code inside `shared_ui`.
- Mandatory deletion of the unused `packages/flutter-shadcn-ui` checkout in this change (optional later cleanup).

## Decisions

| Topic | Choice |
|-------|--------|
| Architecture | Custom library inspired by shadcn categories/theme slots; **not** a wrapper over `flutter-shadcn-ui` |
| Naming | `Tp` prefix |
| Scope (v1) | Tokens/theme + primitives + migrate existing generic `App*` widgets |
| Theme ownership | Tokens + component themes in `shared_ui`; client keeps presets / fonts / `ThemeData` + `TpTheme` wiring |
| Package form | Independent git submodule (`hhoao/shared_ui` → `client/packages/shared_ui`) |
| Compatibility | **None** — rename and delete; no `typedef` / deprecated re-exports |

## Package layout

```
shared_ui/
  lib/
    shared_ui.dart                 # single public barrel
    src/
      theme/
        tp_theme.dart              # InheritedWidget entry
        tp_theme_data.dart
        tokens/                    # spacing, radii, icon sizes, typography
        components/                # TpButtonTheme, TpInputTheme, …
      components/
        button/
        icon_button/
        input/
        textarea/
        select/                    # TpSelect
        popover/                   # TpPopover / TpPortal / TpAnchor (shared by Select + others)
        card/
        dialog/
        segmented_control/
        form/
        empty_state/
        tooltip/
        hover/
        separator/
      utils/                       # portal / anchor helpers (no business deps)
  test/
```

### Dependency rules

- `shared_ui` may depend on Flutter/Material and small pure-UI packages only.
- **Forbidden:** `package:teampilot/...`, flutter_bloc, go_router, app l10n, repositories, services.
- `client` depends on `shared_ui` via path: `packages/shared_ui`.

### Boundary

| In `shared_ui` | Stay in `client` |
|----------------|------------------|
| Tokens, `TpTheme`, component themes | Color preset table, font load/warmup, `MaterialApp` assembly |
| Migrated generic primitives (see mapping) | Domain widgets (workspace, settings, terminal, git, providers, updates) |
| Portal/popover primitives without product semantics | `workspace_surface_layers`, `workspace_topology_colors` |
| `TpToast*` + private toast engine | Thin `AppToast` facade (recorder / `showGlobal` / desktop title-bar inset) |

## Theme model

**Two-layer assembly:**

1. **`MaterialApp.theme`** — `ColorScheme` / FlexColorScheme built in `client` (colors + Material baselines).
2. **`TpTheme`** — InheritedWidget from `shared_ui` holding tokens + per-component themes. All `Tp*` widgets read `TpTheme.of(context)` (with sane defaults if missing).

```dart
TpTheme(
  data: TpThemeData.fromColorScheme(
    colorScheme,
    scale: uiScale,
    // component theme overrides…
  ),
  child: MaterialApp(
    theme: materialTheme,
    // …
  ),
)
```

### Token renames

| Current (`client`) | New (`shared_ui`) |
|--------------------|-------------------|
| `AppSpacingTheme` | `TpSpacing` |
| Typography scale / text styles used by controls | `TpTypography` |
| `AppIconSizes` | `TpIconSizes` |
| `AppControlTheme` | `TpControlMetrics` |
| Dialog / outline input / tooltip / toast theme pieces | Matching `Tp*Theme` (incl. `TpToastTheme`) |
| — | Thin `AppToast` product facade only (see [toast follow-up](./2026-07-16-shared-ui-toast-design.md)) |

Colors are **not** duplicated as a second palette: components use `Theme.of(context).colorScheme` plus geometric tokens.

### Access conventions

- Prefer `context.tpTheme`, `context.tpSpacing`, `context.tpIconSizes`.
- Delete old `App*` theme extensions and getters once migrated.
- New UI code must not hard-code spacing constants when a token exists.

`client` retains:

- Preset id → seed colors
- Font resolution / warmup
- Building `ThemeData` and constructing `TpThemeData` for the tree

## Component inventory (v1)

### Migrate and rename

| Current | New API |
|---------|---------|
| `AppIconButton` | `TpIconButton` |
| `AppDialog` (+ Header / Actions / Divider / PinnedLayout / TextPrompt) | `TpDialog` family |
| `AppToggleSwitch` | `TpSegmentedControl` (multi-segment control via `toggle_switch`; **not** a binary switch) |
| `AppDropdownField` + search / custom / decoration | `TpSelect` |
| Popover / portal / anchor / controller | `TpPopover` / `TpPortal` / `TpAnchor` |
| `AppTextarea*` | `TpTextarea` / `TpTextareaFormField` |
| `AppForm*` | `TpForm` / `TpFormField` / `TpFormFieldLayout` |
| `EmptyStateBlock` | `TpEmptyState` |
| `HoverTextTooltip` | `TpTooltip` (document coexistence with Material `Tooltip`) |
| `HoverWidget` / `HoverRow` | `TpHover` / `TpHoverRow` |

### New primitives (fill library surface)

| Component | Notes |
|-----------|-------|
| `TpButton` | Variants: primary / secondary / outline / ghost / destructive; sizes via `TpControlMetrics` |
| `TpInput` | Single-line + optional `TpInputFormField` |
| `TpCard` | Generic surface container |
| `TpSeparator` | Divider |

### Explicitly out of package (v1)

- `AppProvider*`, `AppUpdate*`, workspace/settings/terminal/git/file-tree widgets, brand logo, notification bell
- Full `AppToast` stack + `app_toast_theme.dart` (client only; no toast theme migration in v1)
- `TpSplitView`, `TpBadge` — defer unless a concrete v1 call site appears during migration
- `AppTextScaleBoundary` — stay in client (app text-scale policy, not a design-system primitive)
- Client theme assembly helpers that wire Material/`ThemeData`: e.g. `app_button_theme.dart`, `app_list_tile_theme.dart`, font/markdown/warmup modules — stay in client; only reusable tokens/component themes move
- When migrating `AppToggleSwitch` → `TpSegmentedControl`, strip `workspace_surface_layers` usage and restyle via `ColorScheme` + `Tp*` tokens so the package stays free of product surface colors

### Naming rules

- Public types: `Tp` + PascalCase category name aligned with shadcn categories (`Button`, `Input`, `Select`, …), not legacy `App` / `Dropdown` names.
- Form variants: `TpX` + `TpXFormField`.
- No compatibility aliases (`typedef AppDialog = TpDialog` forbidden).

## Migration plan

1. Create `hhoao/shared_ui` repo; add submodule at `client/packages/shared_ui`; depend from `client/pubspec.yaml`.
2. Land tokens + `TpTheme` + v1 components inside the package (move+rename existing primitives; implement new `TpButton` / `TpInput` / `TpCard` / …).
3. Update `client`:
   - Delete migrated `App*` sources and obsolete theme files
   - Rewrite imports and type names repo-wide
   - Wrap app with `TpTheme`; keep preset/font assembly in client
4. Ship tests for `shared_ui`; keep `client` analyze + unit/widget tests green.
5. Document in `docs/CODE_QUALITY.md` / `AGENTS.md`: new UI primitives belong in `shared_ui`, not ad-hoc under `client/lib/widgets/`.

## Testing & acceptance

### Testing

- `shared_ui`: widget tests per component + theme resolution tests.
- `client`: analyze + existing non-integration test suite after migration.
- CI / local gate: `shared_ui` must not import `teampilot`.

### Acceptance checklist

- [ ] `import 'package:shared_ui/shared_ui.dart'` exposes the full v1 surface
- [ ] Call sites use `Tp*` for migrated primitives; generic `AppDialog` / `AppDropdownField` / `AppTextarea` / `AppForm` / `AppIconButton` sources are gone
- [ ] Tokens are read via `TpTheme` / agreed extensions; new code does not hard-code spacing when tokens exist
- [ ] Submodule analyzes and tests independently
- [ ] AGENTS / CODE_QUALITY note the `shared_ui` rule

## Risks

| Risk | Mitigation |
|------|------------|
| Large rename churn | Single intentional break; mechanical rename + analyze; no dual API |
| Theme split confusion | Document two-layer model; factory `TpThemeData.fromColorScheme` in package |
| Accidental business deps | Package boundary + analyze/import lint |
| Segmented control vs product colors | Migrate as `TpSegmentedControl`; restyle without `workspace_surface_layers` |
| Toast theme drift | Leave toast theme entirely in client for v1 |

## Open follow-ups (out of v1)

- Progressive replacement of remaining raw Material buttons/inputs with `Tp*`
- Whether to remove unused `packages/flutter-shadcn-ui` from the monorepo
- Richer catalog (Tabs, Sheet, Checkbox, Slider, …) as demand appears

## Amendment (v1.1)

Theme consolidation: [2026-07-15-shared-ui-theme-consolidation-design.md](./2026-07-15-shared-ui-theme-consolidation-design.md) — `TpTextStyles` / `TpFontTheme` / `TpGlyphWarmup` in package; delete duplicate geometric ThemeExtensions in the client.

## Amendment (toast)

Toast follow-up: [2026-07-16-shared-ui-toast-design.md](./2026-07-16-shared-ui-toast-design.md) — absorb vendored toastification into `shared_ui` as a private engine; public `TpToast*` API; client keeps thin `AppToast` for recorder / `showGlobal` / desktop title-bar inset. Supersedes the v1 “toast stays client-only” rows above.
