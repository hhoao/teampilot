# Shared UI theme consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `shared_ui` the single owner of semantic text styles, font ThemeExtension, geometric tokens, and glyph-shaping warmup helpers; delete client duplicates.

**Architecture:** `TpFontTheme` + `TpTextStyles` + `TpGlyphWarmup` live in the package. Client keeps font *loading*, glyph charset, typography prefs → scale, and MaterialApp assembly. Geometric ThemeExtensions (`AppSpacing` / `AppIconSize` / `AppControl`) are deleted; runtime reads `TpTheme` only.

**Tech Stack:** Flutter/Dart, `shared_ui` git submodule, existing TeamPilot theme assembly.

**Spec:** [docs/superpowers/specs/2026-07-15-shared-ui-theme-consolidation-design.md](../specs/2026-07-15-shared-ui-theme-consolidation-design.md)

---

## File map

| Area | Create / modify |
|------|-----------------|
| Package theme | `client/packages/shared_ui/lib/src/theme/tp_font_theme.dart` |
| Package text | `client/packages/shared_ui/lib/src/theme/tp_text_styles.dart` |
| Package warmup | `client/packages/shared_ui/lib/src/theme/tp_glyph_warmup.dart` |
| Barrel | `client/packages/shared_ui/lib/shared_ui.dart` |
| Package tests | `test/theme/tp_text_styles_test.dart`, `tp_glyph_warmup_test.dart`, `tp_font_theme_test.dart` |
| Client fonts | Rewrite `app_fonts.dart` to produce `TpFontTheme`; drop `AppFontTheme` |
| Client theme | `app_theme.dart`, `app_button_theme.dart`, `app_outline_input_theme.dart`, `main.dart` — use `TpControlMetrics`, stop installing duplicate extensions |
| Client delete | `app_text_styles.dart`, `app_spacing.dart` ThemeExtension half, `AppIconSizeTheme` / `AppControlTheme` classes |
| Client keep | `AppTypographyScale`, `AppIconSizes.resolveIconMultiplier` + `AppIconColors`, warmup orchestration, markdown extras |
| Call sites | Mechanical `AppTextStyles` → `TpTextStyles`, `AppFontTheme` → `TpFontTheme`, `appFonts` → `tpFonts`, `appControl` → `tpTheme.control` |

---

### Task 1: `TpFontTheme` in shared_ui

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/tp_font_theme.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/theme/tp_font_theme_test.dart`

- [ ] **Step 1: Write failing test** for ThemeExtension copy/lerp/fallback and `context.tpFonts`.

- [ ] **Step 2: Implement `TpFontTheme`** — fields: `uiFontFamily`, `uiFontFamilyFallback`, `monoFontFamily`, `monoFontFamilyFallback`; `fallback` with null UI + `'monospace'` mono; `BuildContext.tpFonts`.

- [ ] **Step 3: Export and run** `flutter test test/theme/tp_font_theme_test.dart` in `shared_ui`.

---

### Task 2: `TpTextStyles` in shared_ui

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/tp_text_styles.dart` (port from `client/lib/theme/app_text_styles.dart`)
- Modify: barrel
- Test: `client/packages/shared_ui/test/theme/tp_text_styles_test.dart`

- [ ] **Step 1: Failing test** — `TpTextStyles.of(context).md` tracks `textTheme.bodyMedium`; `mono` uses `TpFontTheme`.

- [ ] **Step 2: Port API** — rename `AppTextStyles` → `TpTextStyles`; `mono` reads `TpFontTheme`; move `dropdownFieldTextStyle` / `dropdownHintTextStyle` into this file (or adjacent) as `tpDropdownFieldTextStyle`.

- [ ] **Step 3: Add `stylesForWarmup()`** — return the semantic getter set (xs…display, muted*, mono) with UI family applied from `TpFontTheme` when present. Do **not** include markdown/input (host extras).

- [ ] **Step 4: Export + test.**

---

### Task 3: `TpGlyphWarmup` in shared_ui

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/tp_glyph_warmup.dart`
- Test: `client/packages/shared_ui/test/theme/tp_glyph_warmup_test.dart`

- [ ] **Step 1: Failing test** — `dedupeByShapeKey` collapses color-only variants; `shape` / `shapeAll` run without throw on a short glyph string.

- [ ] **Step 2: Implement** `textStyleShapeKey`, `dedupeByShapeKey`, `shape`, `shapeAll` (TextPainter layout + dispose).

- [ ] **Step 3: Export + test.**

---

### Task 4: Client — fonts + text styles migration

**Files:**
- Modify: `client/lib/theme/app_fonts.dart` (emit `TpFontTheme`; keep Google Fonts / `buildAppUiTextTheme`)
- Delete: `client/lib/theme/app_text_styles.dart`
- Repo-wide: `AppTextStyles` → `TpTextStyles`, imports to `package:shared_ui/shared_ui.dart`, `AppFontTheme` → `TpFontTheme`, `appFonts` → `tpFonts`, `buildAppFontTheme` return type
- Modify: `app_text_styles_warmup.dart`, `ui_interactive_warmup.dart`
- Fix: any `dropdownFieldTextStyle` renames

- [ ] **Step 1: Switch ThemeData extensions to `TpFontTheme`.**

- [ ] **Step 2: Mechanical rename AppTextStyles → TpTextStyles** (sed / codemod); delete local file.

- [ ] **Step 3: Warmup** — `textStylesForThemeWarmup` = `TpTextStyles(theme).stylesForWarmup()` + host input/markdown extras; shape via `TpGlyphWarmup`.

- [ ] **Step 4: `flutter analyze` on client until clean for these symbols.**

---

### Task 5: Client — delete duplicate geometric ThemeExtensions

**Files:**
- Modify: `app_theme.dart`, `app_button_theme.dart`, `app_outline_input_theme.dart`, `app_toast_theme.dart`, `app_text_styles_warmup.dart`, `main.dart`
- Slim or delete: `app_spacing.dart`, `app_control_theme.dart`, `app_icon_sizes.dart` (keep resolveIconMultiplier + colors + IconTheme helper)
- Update tests under `client/test/theme/`

- [ ] **Step 1: Theme builders** take/create `TpControlMetrics.fromScale(m)`; stop putting `AppSpacingTheme` / `AppIconSizeTheme` / `AppControlTheme` in `extensions`.

- [ ] **Step 2: Replace `context.appControl` / `AppControlTheme.fromContext` with `context.tpTheme.control` (map size enum to `TpControlSize`).

- [ ] **Step 3: Move `uiScale` getter to read `tpSpacing.scale` (client extension or use `tpTheme.spacing.scale`).

- [ ] **Step 4: Toast / remaining AppSpacingTheme reads → `context.tpSpacing`.

- [ ] **Step 5: Delete dead ThemeExtension classes; update unit tests.**

- [ ] **Step 6: Ensure `TpTheme` in `main.dart` still gets correct `scale` / `iconScale` from prefs (not from deleted extensions).

---

### Task 6: Docs + verify

- [ ] Update `docs/superpowers/specs/2026-07-15-shared-ui-design.md` boundary table (link to v1.1).
- [ ] Update `client/packages/shared_ui/README.md`, `docs/CODE_QUALITY.md` / `AGENTS.md` if they mention AppTextStyles / dual tokens.
- [ ] Run `cd client/packages/shared_ui && flutter test`
- [ ] Run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

---

## Notes for implementers

- Work on a teampilot feature branch; checkout a branch in the `shared_ui` submodule (do not commit on detached HEAD).
- Prefer one submodule commit then bump teampilot pin, or keep submodule commits atomic per task.
- No `typedef` / deprecated aliases for deleted `App*` types.
- Do not move `warmup_glyphs.g.dart` or Google Fonts into the package.
