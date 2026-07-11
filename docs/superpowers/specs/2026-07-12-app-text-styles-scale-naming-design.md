# AppTextStyles Tailwind-scale naming — Design

**Date:** 2026-07-12  
**Status:** Approved for implementation (naming direction confirmed with product owner)  
**Branch / worktree:** `refactor/app-text-styles-enforcement`

## Goal

Replace component-/role-semantic text style names (`caption`, `bodyStrong`, `toolPanelTitle`, `pageHeadline`, …) with a **Tailwind-like generic scale**: size tokens + optional weight/tracking modifiers. UI layers (`pages/`, `widgets/`) may only consume these extracted styles (or other `lib/theme/` helpers). **No backward-compatible aliases** — rename call sites in the same change set.

## Non-goals

- Visual redesign beyond intentional token normalization (e.g. 9px badges → `xsSemibold`)
- Changing Material `TextTheme` role wiring except as needed to back the scale
- Keeping deprecated getters or `@Deprecated` shims

## Size scale

| Token | Approx px (standard) | Theme source | Default height |
|-------|----------------------|--------------|----------------|
| `xs` | 11 | `labelSmall` | 1.35 |
| `sm` | 12 | `bodySmall` | 1.35 |
| `md` | 14 | `bodyMedium` | 1.35 |
| `lg` | 16 | `bodyLarge` | 1.35 |
| `lgSnug` | 16 | `titleMedium` | 1.25 |
| `xl` | 20 | `titleLarge` | 1.25 |
| `display` | 24 | `headlineSmall` (via `AppTypographyScale.headlineSmallBase`) | 1.25 |

Use `display` instead of `2xl` (awkward Dart identifier).

**`lg` vs `lgSnug`:** same pixel band, different rhythm. Prefer `lg` for body emphasis; `lgSnug` for subtitle / dialog title band (tighter leading).

## Weight modifiers

Bare size = theme default weight (do not force `w400` if Material base differs).

Suffixes:

| Suffix | Weight |
|--------|--------|
| *(none)* | theme default |
| `Thin` | `w300` |
| `Medium` | `w500` |
| `Semibold` | `w600` |
| `Bold` | `w700` |

Examples: `md`, `mdMedium`, `mdSemibold`, `xsSemibold`, `lgSemibold`.

**Closed set (ship these; add more only when a call site needs them during migration):**

- Sizes: `xs`, `sm`, `md`, `lg`, `lgSnug`, `xl`, `display`
- Weights: `xsSemibold`, `smMedium`, `smSemibold`, `mdThin`, `mdMedium`, `mdSemibold`, `lgMedium`, `lgSemibold`, `lgSnugSemibold`
- Do **not** ship `xsBold` unless a call site needs bold **without** tracking (tool-panel use `xsWide`)

### Special height on weight tokens

| Token | Extra |
|-------|--------|
| `xsSemibold` | `height: 1.2` (was `badge`) |
| `mdSemibold` | `height: 1.25` (was `bodyStrong`) |
| `lgSnugSemibold` | `height: 1.25` (was `dialogTitle`) |

## Tracking modifiers (Approach 2)

UI code must **not** set `letterSpacing`. Encode tracked/tight styles as generic modifiers:

| Token | Composition |
|-------|-------------|
| `xsWide` | `xs` + `Bold` + `letterSpacing: 0.8` (was `toolPanelTitle`) |
| `xsTrack` | `xs` + `letterSpacing: 0.2` (was `settingsGroupHeader`) |
| `mdTight` | `md` + `Semibold` + `letterSpacing: -0.15` + `height: 1.25` (was `sectionTitle`; base = `bodyMedium`, intentionally normalize off `titleSmall`) |
| `mdWide` | `md` + `Bold` + `letterSpacing: 0.4` (was `fileTreeRootLabel` metrics) |
| `mdSnug` | `md` + `height: 1.25` (no weight change) — for former `formLabel` / any 14px @ 1.25 without semibold |

## Color helpers

- Every shipped scale getter has `{token}Colored(Color color)`.
- Muted shortcuts: `mutedXs`, `mutedSm`, `mutedMd` (`onSurfaceVariant`).
- Do **not** put optional `fontWeight` on `*Colored` — pick the weight token first (`mdSemiboldColored(c)`), then color.

## Mono

`mono` / `monoColored` — family override on `md` size. Not a component name.

## Dropdown / terminal helpers

Keep `dropdownFieldTextStyle`, `dropdownHintTextStyle`, `appMonoTextStyle`, `appTerminalTextStyle` in `lib/theme/`. Internally they may build from `AppTextStyles.mdMedium` / `md`. Public names stay (theme helpers, not widget-layer styles).

## Facades to remove

Delete or hollow out page-local typography facades that re-export semantic names:

- `pages/llm_config/llm_workspace_typography.dart` (`LlmWorkspaceText`, `LlmProviderDetailLook`, …) → call sites use `AppTextStyles` directly (`xs`, `md`, `mdSemibold`, `mdTight`, …).
- Any similar `*Typography` / `*Text` wrappers under `pages/` / `widgets/` discovered during grep.

## Rename map (old → new)

| Old | New |
|-----|-----|
| `caption` / `captionColored` | `xs` / `xsColored` |
| `badge` / `badgeColored` | `xsSemibold` / `xsSemiboldColored` |
| `toolPanelTitle` / `*Colored` | `xsWide` / `xsWideColored` |
| `settingsGroupHeader` / `*Colored` | `xsTrack` / `xsTrackColored` |
| `fileTreeRootLabel` | `mdWideColored` |
| `fileTreeEntryLabel(active:)` | `mdSemiboldColored` / `mdMediumColored` |
| `bodySmall` / `bodySmallColored` | `sm` / `smColored` |
| `body` / `bodyColored` | `md` / `mdColored` |
| `formLabel` / `formLabelColored` | `mdSnug` / `mdSnugColored` |
| `bodyStrong` / `bodyStrongColored` | `mdSemibold` / `mdSemiboldColored` |
| `prominent` | `lg` |
| `sectionTitle` / `sectionTitleColored` | `mdTight` / `mdTightColored` |
| `subtitle` | `lgSnug` |
| `pageTitle` | `xl` |
| `pageHeadline` | `display` |
| `dialogTitle` | `lgSnugSemibold` |
| `mutedBody` | `mutedMd` |
| `mutedBodySmall` | `mutedSm` |
| `mutedCaption` | `mutedXs` |
| `mono` / `monoColored` | unchanged |

## Call-site `copyWith` policy

In `pages/` / `widgets/`:

- **Allowed:** `styles.mdSemibold.copyWith(color: …)` (color only), or prefer `mdSemiboldColored`.
- **Forbidden:** `copyWith` that sets `fontSize`, `letterSpacing`, `fontWeight`, or `height` — promote to a named scale token in `AppTextStyles` in the same PR.
- Layout-only **reads** of `style.fontSize` (e.g. ToggleSwitch width math) are allowed; do not hardcode literal sizes.

## CODE_QUALITY

Typography rule becomes:

> In `pages/` and `widgets/`, text styles must come from [`AppTextStyles`](../client/lib/theme/app_text_styles.dart) **scale tokens** (`xs`, `mdSemibold`, `xsWide`, …) or other helpers in `lib/theme/` (`dropdownFieldTextStyle`, `appMonoTextStyle`, `appTerminalTextStyle`, …). Do **not** construct `TextStyle(...)` inline, set `fontSize` / `letterSpacing` / `fontWeight` / `height` via `copyWith`, or use raw `ThemeData.textTheme` roles / component-semantic style names. Prefer `*Colored` / `muted*` for color. Exceptions: syntax highlighting, terminal `TerminalStyle`, size-driven avatar glyphs, diff views that inherit editor font metrics.

## Migration strategy

1. Rewrite `AppTextStyles` to the new API only (delete old getters same commit).
2. Mechanical rename across `client/lib/` + tests.
3. Update `app_text_styles_warmup.dart` to enumerate **all** shipped tokens; update `app_markdown_style_sheet.dart` bindings (`h2`→`lgSnug` / `lgSnugSemibold`, body→`md`, etc.).
4. Remove `LlmWorkspaceText` and other facades; fix call sites.
5. Finish remaining raw `textTheme` / inline `TextStyle` / weight-`copyWith` onto the scale.
6. Grep gate: no old names; no raw textTheme in UI layers (exceptions only).

No dual-API period. No compatibility typedefs.

## Out of scope exceptions (unchanged)

- `client/lib/theme/**` definition site
- `editor_syntax_theme.dart`
- Terminal `TerminalStyle` / `appTerminalTextStyle`
- Diff views rebuilding `TextStyle` from editor metrics
- Size-driven avatar / brand glyphs (`fontSize: size * factor`)
