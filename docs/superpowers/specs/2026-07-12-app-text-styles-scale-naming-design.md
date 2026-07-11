# AppTextStyles Tailwind-scale naming — Design

**Date:** 2026-07-12  
**Status:** Approved for implementation (naming direction confirmed with product owner)  
**Branch / worktree:** `refactor/app-text-styles-enforcement`

## Goal

Replace component-/role-semantic text style names (`caption`, `bodyStrong`, `toolPanelTitle`, `pageHeadline`, …) with a **Tailwind-like generic scale**: size tokens + optional weight/tracking modifiers. UI layers (`pages/`, `widgets/`) may only consume these extracted styles (or other `lib/theme/` helpers). **No backward-compatible aliases** — rename call sites in the same change set.

## Non-goals

- Visual redesign beyond intentional token normalization already in flight (e.g. 9px badges → `xsSemibold` at caption size)
- Changing Material `TextTheme` role wiring except as needed to back the scale
- Keeping deprecated getters or `@Deprecated` shims

## Size scale

| Token | Approx px (standard scale) | Theme source |
|-------|----------------------------|--------------|
| `xs` | 11 | `labelSmall` |
| `sm` | 12 | `bodySmall` |
| `md` | 14 | `bodyMedium` |
| `lg` | 16 | `bodyLarge` / `titleMedium` (same size band; prefer `bodyLarge` for `lg`, `titleMedium` only if height needs 1.25 subtitle feel — pick **one** base: `bodyLarge` for `lg`) |
| `xl` | 20 | `titleLarge` |
| `display` | 24 | `headlineSmall` (scaled via `AppTypographyScale.headlineSmallBase`) |

Use `display` instead of `2xl` (invalid / awkward Dart identifier).

Default line height: existing `_resolve` convention (`height: 1.35` for body bands; `1.25` for title-like / semibold emphasis where today’s tokens already use 1.25).

## Weight modifiers

Bare size = regular (`FontWeight.w400` unless the Material base already differs — do not force-override if theme base is w400/w500; prefer copyWith only when modifier is explicit).

Suffixes (PascalCase after size, camelCase overall):

| Suffix | Weight |
|--------|--------|
| *(none)* | regular (theme default) |
| `Thin` | `w300` |
| `Medium` | `w500` |
| `Semibold` | `w600` |
| `Bold` | `w700` |

Examples: `md`, `mdMedium`, `mdSemibold`, `xsBold`, `smThin`.

**Ship only the combinations that replace today’s usage** (plus a small closed set for obvious gaps). Do not generate a full Cartesian product of size×weight unless a call site needs it. Minimum set:

- Sizes: `xs`, `sm`, `md`, `lg`, `xl`, `display`
- Weights used today: `xsSemibold` (badge), `xsBold` (tool panel header weight), `mdMedium`, `mdSemibold` (bodyStrong / section titles), `lgSemibold` (dialog titles), and others discovered during rename grep
- Add further `size+Weight` getters only when a migrated call site needs them

## Tracking / letter-spacing modifiers (Approach 2)

UI code must **not** set `letterSpacing`. Encode today’s tracked/tight styles as **generic** modifiers on the size axis:

| Token | Base | Extra |
|-------|------|--------|
| `xsWide` | `xs` + `Bold` (w700) | `letterSpacing: 0.8` (was `toolPanelTitle`) |
| `xsTrack` | `xs` | `letterSpacing: 0.2` (was `settingsGroupHeader`) |
| `mdTight` | `md` + `Semibold` | `letterSpacing: -0.15`, `height: 1.25` (was `sectionTitle`) |
| `mdWide` | `md` + `Bold` | `letterSpacing: 0.4` (was `fileTreeRootLabel` weight/tracking; color via `mdWideColored`) |

No component names. If a call site only needed weight without tracking, use `xsBold` / `mdSemibold` instead of the Wide/Tight variants.

## Color helpers

- `mutedXs`, `mutedSm`, `mutedMd` — `onSurfaceVariant` on that size (replace `mutedCaption` / `mutedBodySmall` / `mutedBody`)
- `xsColored(Color, {FontWeight?})`, `smColored`, `mdColored`, … for one-off scheme colors (error, onError, …)
- Weight-specific colored helpers only where call volume warrants (`mdSemiboldColored`, `xsSemiboldColored`); otherwise `mdSemibold.copyWith(color: …)` is acceptable **only for color** (not fontSize/letterSpacing)

## Mono

Keep `mono` / `monoColored` — family override, not a UI component name. Base size = `md`.

## Dropdown / terminal helpers

Remain as theme helpers (`dropdownFieldTextStyle`, `dropdownHintTextStyle`, `appMonoTextStyle`, `appTerminalTextStyle`). Optionally reimplement dropdown helpers on top of `AppTextStyles.mdMedium` internally; public API names can stay (they are field-role helpers in `lib/theme/`, not widget-layer styles).

## Rename map (old → new)

| Old | New |
|-----|-----|
| `caption` | `xs` |
| `captionColored` | `xsColored` |
| `badge` / `badgeColored` | `xsSemibold` / `xsSemiboldColored` |
| `toolPanelTitle` / `*Colored` | `xsWide` / `xsWideColored` |
| `settingsGroupHeader` / `*Colored` | `xsTrack` / `xsTrackColored` |
| `fileTreeRootLabel` | `mdWideColored` (or `mdWide` + color) |
| `fileTreeEntryLabel(active:)` | `mdSemiboldColored` / `mdMediumColored` by `active` |
| `bodySmall` / `bodySmallColored` | `sm` / `smColored` |
| `body` / `bodyColored` | `md` / `mdColored` |
| `formLabel` / `formLabelColored` | `md` / `mdColored` (same size band as labelLarge; drop separate formLabel) |
| `bodyStrong` / `bodyStrongColored` | `mdSemibold` / `mdSemiboldColored` |
| `prominent` | `lg` |
| `sectionTitle` / `sectionTitleColored` | `mdTight` / `mdTightColored` |
| `subtitle` | `lg` (height 1.25 via dedicated `lg` resolve if needed) |
| `pageTitle` | `xl` |
| `pageHeadline` | `display` |
| `dialogTitle` | `lgSemibold` |
| `mutedBody` | `mutedMd` |
| `mutedBodySmall` | `mutedSm` |
| `mutedCaption` | `mutedXs` |
| `mono` / `monoColored` | unchanged |

## CODE_QUALITY

Update Typography rule to require **scale tokens** (`AppTextStyles.xs` / `mdSemibold` / …), forbid component-semantic style names, forbid inline `TextStyle`, `fontSize`, `letterSpacing`, and raw `textTheme` in `pages/` / `widgets/`. Exceptions unchanged (syntax highlight, terminal `TerminalStyle`, avatar glyphs, diff editor-inherit).

## Migration strategy

1. Rewrite `AppTextStyles` API to the new names only (delete old getters in the same commit).
2. Mechanical rename across `client/lib/` + tests + warmup list.
3. Finish any remaining raw `textTheme` / inline `TextStyle` migrations onto the new scale.
4. Grep gate: no old names, no raw textTheme in UI layers (exceptions only).

No dual-API period. No compatibility typedefs.

## Out of scope exceptions (unchanged)

- `client/lib/theme/**` definition site
- `editor_syntax_theme.dart`
- Terminal `TerminalStyle` / `appTerminalTextStyle`
- Diff views rebuilding `TextStyle` from editor metrics
- Size-driven avatar / brand glyphs (`fontSize: size * factor`)
