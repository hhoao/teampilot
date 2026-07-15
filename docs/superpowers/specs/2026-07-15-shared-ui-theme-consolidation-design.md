# Shared UI theme consolidation (v1.1)

**Status:** Approved (owner decision)  
**Date:** 2026-07-15  
**Parent:** [2026-07-15-shared-ui-design.md](./2026-07-15-shared-ui-design.md)

## Problem

After v1, geometric tokens exist in both places: `TpTheme` (`shared_ui`) and parallel `AppSpacingTheme` / `AppIconSizeTheme` / `AppControlTheme` ThemeExtensions in the client. Semantic text styles (`AppTextStyles`) and font family ThemeExtension (`AppFontTheme`) remain app-private, so the design system cannot express typography or glyph warmup without host-specific code.

## Goals

1. **Single geometric token source:** `TpTheme` / `TpThemeData` only. Delete client ThemeExtensions that duplicate `TpSpacing`, `TpIconSizes`, `TpControlMetrics`.
2. **Move semantic text styles into `shared_ui`:** `AppTextStyles` → `TpTextStyles` (no aliases).
3. **Move font-family ThemeExtension into `shared_ui`:** `AppFontTheme` → `TpFontTheme` (families + fallbacks only; no Google Fonts / catalog).
4. **First-class glyph warmup API in `shared_ui`:** enumerate styles + shape helpers; host supplies glyph charset and boot orchestration.
5. Preserve UX: font loading, markdown/input warmup extras, toast, workspace surfaces stay host-owned where they encode product policy.

## Non-goals

- Moving Google Fonts loading, `FontCatalog`, or `gen_warmup_glyphs` into the package.
- Moving markdown style sheets or toast themes into the package.
- Changing visual baselines of spacing / icons / control metrics (same numbers, one owner).

## Decisions

| Topic | Choice | Why |
|-------|--------|-----|
| Font ThemeExtension | **`TpFontTheme` in `shared_ui`** | `TpTextStyles.mono` and warmup need ThemeData-attached families without host types |
| Font loading | Stay in client | Bundled assets / Google Fonts / catalog are product concerns |
| Geometric tokens | **`TpTheme` only** | Dual ThemeExtension + InheritedWidget drifts and confuses scale |
| Icon multiplier policy | **`TpIconSizes.resolveIconMultiplier` in `shared_ui`** | Reusable damped mapping; host still passes result as `iconScale` |
| Control metrics for Material assembly | Pass `TpControlMetrics` into theme builders; **do not** reinstall as ThemeExtension | Assembly has no `TpTheme` ancestor yet; widgets at runtime use `context.tpTheme.control` |
| Warmup boundary | Package: style list + dedupe + `TextPainter` shape. Host: glyphs string, font pending, terminal engine, markdown/input extras | Reusable without ARB/l10n coupling |
| Naming | `TpTextStyles`, `TpFontTheme`, `TpGlyphWarmup` — delete `App*` counterparts | Same break policy as v1 |

## Architecture

```
MaterialApp.theme (client)
  ColorScheme + TextTheme sizes
  ThemeExtension: TpFontTheme only (for fonts)
  Button/input ThemeData built from TpControlMetrics(scale)

TpTheme (shared_ui InheritedWidget)
  TpSpacing / TpIconSizes / TpTypography / TpControlMetrics
  component themes…

Widgets
  geometry → context.tpTheme / tpSpacing / tpIconSizes / tpTheme.control
  text → TpTextStyles.of(context)
  mono family → TpFontTheme via Theme.of or TpTextStyles.mono
```

### Warmup

```dart
// shared_ui
final styles = TpTextStyles(theme).stylesForWarmup(); // semantic + mono
final deduped = TpGlyphWarmup.dedupeByShapeKey([...styles, ...hostExtras]);
TpGlyphWarmup.shapeAll(styles: deduped, glyphs: hostGlyphs);
```

Host keeps `bootstrapThemeForTextWarmup` / preference-aware theme (fonts + text scale), appends input/markdown styles, owns `warmup_glyphs.g.dart` and `UiInteractiveWarmup`.

## Boundary update

| In `shared_ui` | Stay in `client` |
|----------------|------------------|
| `TpTextStyles`, `TpFontTheme` | Font catalog, resolver, Google Fonts pending |
| `TpGlyphWarmup` (+ shape-key dedupe) | Glyph charset generation from ARB |
| Existing tokens / `TpTheme` | `AppTypographyScale` prefs → scale multipliers |
| | `AppIconSizes.resolveIconMultiplier`, `AppIconColors` |
| | Markdown / outline-input styles used as warmup *extras* |
| | Toast, workspace surfaces, MaterialApp assembly |

## Migration

1. Add `TpFontTheme`, `TpTextStyles`, `TpGlyphWarmup` to `shared_ui` + tests; export from barrel.
2. Client: switch ThemeData to `TpFontTheme`; replace `AppTextStyles` → `TpTextStyles`; delete `app_text_styles.dart` / `AppFontTheme`.
3. Rewire warmup to package APIs; keep host extras.
4. Remove `AppSpacingTheme` / `AppIconSizeTheme` / `AppControlTheme` from ThemeData and files; Material builders take `TpControlMetrics`; `uiScale` from `tpSpacing.scale`.
5. Keep thin client helpers only where needed (`resolveIconMultiplier`, icon ThemeData helper, toast spacing via `tpSpacing`).
6. Update CODE_QUALITY / AGENTS / package README.

## Acceptance

- [x] No `AppTextStyles` / `AppFontTheme` / `AppSpacingTheme` / `AppIconSizeTheme` / `AppControlTheme` / `AppIconSizes` in client
- [x] Call sites use `TpTextStyles` / `TpFontTheme` / `context.tpTheme`
- [x] Boot glyph warmup uses `TpGlyphWarmup`; host still supplies glyphs + extras
- [x] `shared_ui` + client analyze/tests green (theme suite; full suite unrelated CLI installer flakes noted separately)
