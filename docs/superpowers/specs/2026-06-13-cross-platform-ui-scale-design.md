# Cross-Platform UI Scale — Design

**Date:** 2026-06-13
**Status:** Implemented with a pivot — see Revision below
**Owner:** TeamPilot client

> ## Revision 2026-06-13 — Pivot to global zoom
>
> The original design (token migration: drive every spacing/icon/font off
> `uiScale`) was implemented for the **plumbing** (Tasks 1–6: `AppSpacingTheme`,
> `AppIconSizeTheme`, `context.uiScale`, **OS textScaler neutralization**), but
> measurement showed it would require migrating **~900 hard-coded call-sites**
> (146 icon sizes + 274 `EdgeInsets` + 479 `SizedBox` gaps across 104 files) for
> the scale to visibly reach the layout — large *and* fragile (any new hard-coded
> value silently breaks consistency).
>
> **New architecture:** a single root-level **global zoom** (`UiZoom`, a
> `Transform.scale` + rescaled `MediaQuery`) scales the entire UI subtree as one
> — fonts, icons, padding, every control — in ~30 lines, with zero per-widget
> migration and no regression surface. The theme is built at the **standard
> (1.0)** baseline; the interface-scale value feeds `UiZoom` only (no
> double-scaling). The OS-textScaler neutralization (Task 3) is **kept**. The
> token system (Tasks 1–6) remains as harmless base-scale design tokens.
>
> **Tradeoff accepted by user:** the embedded terminal (flutter_alacritty,
> bitmap glyph atlas) is crisp at 100% and when zooming **out** (the user's
> 175%→compact case); only zooming **in** past 100% can soften it. The
> `Transform`-based zoom keeps vector text/icons crisp at any scale.
>
> Task 7 (token migration of shells) is **superseded** and dropped.

## 1. Problem

The same Flutter UI renders at noticeably different densities across desktop
platforms. On Ubuntu/GNOME the layout looks compact and dense; on Windows and
macOS it looks larger and more spacious. The user develops on Ubuntu, prefers
that compact look, and wants all three platforms to look like Ubuntu.

### Root cause (confirmed)

The app uses **fixed logical-pixel sizes everywhere**: typography sizes are
fixed roles in `AppTypographyScale` (title 20 / body 14 / …), control density is
a uniform `VisualDensity.compact`, icon sizes are fixed in `AppIconSizes`, and
paddings/gaps are hard-coded `EdgeInsets`/`SizedBox` throughout the widget tree.
Flutter lays out in **logical pixels**, so the logical layout is *already
identical across platforms*.

The only platform-varying inputs to the rendered result are two values supplied
by the OS / window embedder — neither is in the Dart code:

1. **`MediaQuery.textScaler`** — On Linux, the GTK embedder folds the GNOME
   `text-scaling-factor` into `textScaler`; on Windows/macOS it stays `1.0`.
   This is the direct source of Linux-vs-others divergence. Already documented in
   `client/lib/services/terminal/terminal_fonts.dart` (lines 17–23) and consumed
   in places like `client/lib/pages/workspace_shell/workspace_shell.dart:67`
   (`82.0 * textScale`).

2. **`devicePixelRatio`** — Set by the OS display-scaling setting
   (`client/windows/runner/win32_window.cpp:134`: `scale_factor = dpi / 96.0`;
   GTK uses the GNOME scale factor). DPR does **not** change logical layout, but
   it changes how physically large each logical pixel appears, and how many
   logical pixels a window of a given physical size has. Ubuntu commonly runs at
   100% (DPR 1.0 → dense), Windows laptops at 125–150%, macOS Retina at ~2.0.

**Conclusion:** unifying to the Ubuntu look means *taking the UI scale away from
the OS and letting the app own it*.

## 2. Goals / Non-Goals

### Goals
- A single app-owned **`uiScale`** that is the one source of truth for UI
  density (typography + spacing + icon sizes + control density).
- Neutralize the OS-injected `textScaler` so platforms stop diverging on text.
- A compact default tuned to the Ubuntu density, applied identically on all
  three desktop platforms.
- A user-facing setting to fine-tune scale (generalize the existing typography
  scale setting).
- Keep the embedded terminal visually crisp (no geometric distortion).

### Non-Goals
- **No per-platform DPR auto-normalization** as the default. Auto-scaling by
  `referenceDPR / actualDPR` fights the OS accessibility contract (a user who set
  150% to see better would get an unusably tiny app) and is unreliable (DPR ≠
  PPI, so it does not truly equalize physical size across monitors). OS scaling
  remains the respected base; the app layers a deliberate compact scale on top.
- **No root `Transform.scale` global zoom.** It would scale everything including
  hard-coded paddings, but it blurs the flutter_alacritty terminal (Alacritty
  rasterizes a glyph atlas to a GPU texture; scaling that texture
  shimmers/blurs) and tangles with the hidden custom title bar,
  `DragToResizeArea` resize handles, and overlays. Wrong tradeoff for a
  terminal-centric app.
- No change to the Android/mobile layout behavior beyond inheriting the same
  token system (mobile is SSH-only and out of the reported scope).

## 3. Architecture Overview

```
Settings (SharedPreferences)
  └─ uiScale (double)  ◄── generalizes typographyScale + typographyScaleCustomMultiplier
        │
   LayoutCubit.setUiScale()
        │
   TeamPilotApp (main.dart)
        ├─ buildLightTheme/buildDarkTheme(colorPreset, uiScale)
        │     └─ ThemeData.extensions += [AppTypographyTheme, AppSpacingTheme, AppDensityTheme]
        │        (typography sizes, spacing tokens, icon sizes all derived from uiScale)
        │
        └─ MaterialApp.builder
              └─ MediaQuery(textScaler: app-owned)  ◄── neutralizes GNOME text-scaling-factor
                    └─ app content (reads tokens via context.appSpacing / appTypography / icon theme)
                          └─ Terminal: uses its own TerminalStyle.size path (NOT scaled here)
```

Single multiplier `uiScale` flows into the theme extensions; the OS textScaler is
replaced by an app-owned value at the root. Everything the app paints reads from
the tokens; the terminal is the one deliberate exception.

## 4. Components

### 4.1 `uiScale` — single source of truth
- **Generalize** the existing `typographyScale` (`compact`/`standard`/
  `comfortable`/`custom`) + `typographyScaleCustomMultiplier` into a single
  effective `uiScale` double. Reuse the existing settings field plumbing in
  `AppSettingsRepository` / `LayoutPreferences` and `LayoutCubit`
  (`setTypographyScale` / `setTypographyScaleCustom` become `setUiScale`, with the
  named presets mapping to multipliers as today: compact 0.92, standard 1.0,
  comfortable 1.08, custom 0.75–1.35).
- Rationale for reuse: the typography scale already does font-only scaling and is
  already wired through `LayoutCubit` → `main.dart` `BlocSelector` → theme. We
  extend its reach from "fonts only" to "whole design system" rather than adding
  a parallel knob.
- Back-compat is explicitly **not** a constraint (per direction); the persisted
  key may be renamed.

### 4.2 Root `textScaler` ownership
- In `MaterialApp.builder` (`client/lib/main.dart:297`), wrap the child in a
  `MediaQuery` whose `textScaler` is set to an app-owned value (default
  `TextScaler.noScaling`, i.e. 1.0), so the GNOME `text-scaling-factor` can no
  longer leak in and make Linux diverge.
- Because the design-system scale now lives in `uiScale` (theme tokens), text
  size is driven by the theme, not by the OS textScaler. Code that currently
  multiplies by `MediaQuery.textScalerOf(context)` for layout
  (`workspace_shell.dart:67`, `terminal_fonts.dart:29`,
  `file_editor_theme.dart`, file-tree / git visible-row math) is reviewed: UI
  surfaces switch to reading `uiScale`/tokens; the terminal keeps an explicit
  scale hook (see 4.5).
- Net effect: with the OS input neutralized, the three platforms render
  text-identically at a given `uiScale`.

### 4.3 Density token layer
Three `ThemeExtension`s, all derived from `uiScale`, attached in
`_applyTypography` (`client/lib/theme/app_theme.dart`):

- **Typography** — existing `AppTypographyTheme.fromScale(uiScale)`. Unchanged
  pattern; `uiScale` replaces the typography-only multiplier.
- **Spacing (new `AppSpacingTheme`)** — semantic spacing tokens
  (`xxs/xs/sm/md/lg/xl`, plus named gaps and corner radii) each `base *
  uiScale`. Exposed via `BuildContext.appSpacing` (mirrors the existing
  `context.appTypography` / `AppIconSizesContext` extension pattern).
- **Icon sizes** — make `AppIconSizes` scale live. Today
  `AppIconSizes.multiplier` is a hard-coded `const 1.0`
  (`client/lib/theme/app_icon_sizes.dart:15`), so icons ignore the user's scale.
  Move resolved icon sizes into an `AppIconSizeTheme` extension (or feed the
  `IconThemeData` size from `uiScale`) so icons follow `uiScale`.

Control density (`VisualDensity.compact`) stays as-is — it is already uniform
across platforms and is an orthogonal, well-behaved knob.

### 4.4 Spacing migration strategy
- Add the `AppSpacingTheme` tokens and `context.appSpacing` first.
- Migrate hard-coded `EdgeInsets`/`SizedBox` gaps to tokens **incrementally**,
  highest-visual-impact first: the shells visible in the report —
  `pages/workspace_shell/`, `pages/home_workspace/`, sidebars/cards
  (`widgets/`), and the config/member sections (`pages/team_config/`,
  `pages/config/`, `pages/home_workspace/project/`).
- A lint-style follow-up (grep audit) tracks remaining raw `EdgeInsets` so the
  token system does not silently regress. Full migration is the durable goal;
  the architecture is in place after the first shells land.

### 4.5 Terminal exclusion
- The terminal (`flutter_alacritty`) keeps its explicit sizing path in
  `appTerminalTextStyle` (`terminal_fonts.dart`). It must **not** be wrapped in
  any geometric UI scale.
- Its size should track `uiScale` numerically (so a denser UI also gets a denser
  terminal) by multiplying `TerminalStyle.size` by `uiScale` directly, instead
  of by the now-neutralized `MediaQuery.textScaler`. This keeps cell metrics and
  glyph rendering correct (the size drives both) — no texture scaling, no blur.

### 4.6 Settings UI
- The existing appearance/typography setting becomes the "Interface scale"
  control (keep the named presets + custom slider). Same screen, generalized
  label and effect. l10n strings updated in `app_en.arb` / `app_zh.arb` only,
  then `flutter pub get` + `dart run tool/gen_warmup_glyphs.dart` per AGENTS.md.

## 5. Data Flow
1. App start: `LayoutCubit` loads `uiScale` from `SharedPreferences` (default =
   compact baseline).
2. `main.dart` `BlocSelector` reads `uiScale`, builds light/dark themes with the
   three derived extensions, and sets the root `MediaQuery.textScaler`.
3. Widgets read sizes from `context.appTypography` / `context.appSpacing` /
   `IconTheme`; none read OS textScaler for layout (except the terminal's own
   explicit hook, which uses `uiScale`).
4. User changes the Interface-scale setting → `LayoutCubit.setUiScale` persists →
   theme rebuilds → whole UI (and terminal) rescales uniformly and identically on
   every platform.

## 6. Default Value Selection
- Pick the compact default empirically: instrument a one-time debug log of
  `devicePixelRatio` and `textScaler` (and chosen `uiScale`) so the value is
  grounded rather than guessed, then set the default to the multiplier that
  reproduces the developer's Ubuntu density. Likely in the `compact`/custom
  range (≈0.9). The exact number is finalized during implementation against a
  side-by-side comparison; it is a single constant, trivially tunable.

## 7. Testing
- **Unit:** `uiScale` → token resolution (typography/spacing/icon sizes) is
  pure-function and deterministic; test mapping of presets + custom clamp.
- **Theme:** golden/extension tests that the three `ThemeExtension`s are present
  and scale with `uiScale`.
- **Cubit:** `LayoutCubit.setUiScale` persists and emits; use
  `setUpTestAppStorage()` / `tearDownTestAppStorage()` per AGENTS.md.
- **Manual golden-path (documented, CI cannot cover cross-platform):**
  side-by-side Ubuntu vs Windows vs macOS screenshots at the same `uiScale`
  showing matching density; terminal remains crisp.
- Gate before done: `cd client && flutter analyze --no-fatal-infos
  --no-fatal-warnings && flutter test --exclude-tags integration`.

## 8. Risks & Tradeoffs
- **Migration surface:** moving hard-coded paddings to tokens touches many files.
  Accepted per direction (best architecture over least effort); mitigated by
  incremental, high-impact-first rollout and a grep audit.
- **Neutralizing OS textScaler** means GNOME accessibility text-scaling no longer
  enlarges the app. Mitigated: the Interface-scale setting + OS DPR (which still
  applies) cover accessibility; this is the same model VS Code uses.
- **Terminal size coupling:** terminal now scales with `uiScale` numerically;
  verify column/row reflow stays correct at non-1.0 scales.

## 9. Rollout Phases
1. `uiScale` settings generalization + `LayoutCubit.setUiScale` + theme wiring.
2. Root `MediaQuery.textScaler` neutralization; repoint terminal to `uiScale`.
3. `AppSpacingTheme` + `context.appSpacing`; live `AppIconSizes` scaling.
4. Migrate shells in the screenshots (workspace shell, home workspace, config /
   member sections, sidebars/cards).
5. Pick + set the compact default from instrumented measurement; manual
   cross-platform verification; l10n + warmup-glyph regen.
