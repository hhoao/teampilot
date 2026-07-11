# AppTextStyles four-axis scale naming — Design

**Date:** 2026-07-12  
**Status:** Approved direction (product owner); ready for implementation after user confirms this revision  
**Branch / worktree:** `refactor/app-text-styles-enforcement`

## Goal

Define UI text styles as a **four-axis scale** (size × weight × letter-spacing × line-height), exposed only as **named getters** on `AppTextStyles`. No component-semantic names. **No public `compose`**. **No backward-compatible aliases.**

## Axes

| Axis | Values | Meaning |
|------|--------|---------|
| **Size** | `xs`, `sm`, `md`, `lg`, `xl`, `display` | ~11 / 12 / 14 / 16 / 20 / 24 px (standard typography scale) |
| **Weight** | `Normal`, `Medium`, `Semibold`, `Bold` | w400 / w500 / w600 / w700 (`Thin` optional later if needed) |
| **Spacing** | `Tight`, `Normal`, `Track`, `Spread`, `Wide` | letterSpacing (fixed per value; see metric table) |
| **Height** | `Snug`, `Normal`, `Relaxed` | line height: `1.25` / `1.35` / `1.45` |

### Naming

Order: `{size}{Weight?}{Spacing?}{Height?}`

**Elision:** omit a segment when it is `Normal`. All-normal → size only (`md`).

Examples:

| Getter | Size | Weight | Spacing | Height |
|--------|------|--------|---------|--------|
| `md` | md | normal | normal | normal |
| `mdSemibold` | md | semibold | normal | normal |
| `mdSemiboldTight` | md | semibold | tight | normal |
| `mdSemiboldTightSnug` | md | semibold | tight | snug |
| `xsWide` | xs | normal | wide | normal |
| `xsBoldWide` | xs | bold | wide | normal |
| `lgSnug` | lg | normal | normal | snug |
| `xsSemiboldSnug` | xs | semibold | normal | snug |

Illegal / discouraged names: `mdNormalNormalNormal`, component names (`toolPanelTitle`, `pageHeadline`, …).

### Metric tables (theme-owned; UI must not override)

**Size → TextTheme role**

| Size | Source |
|------|--------|
| `xs` | `labelSmall` |
| `sm` | `bodySmall` |
| `md` | `bodyMedium` |
| `lg` | `bodyLarge` |
| `xl` | `titleLarge` |
| `display` | `headlineSmall` (scaled via `AppTypographyScale.headlineSmallBase`) |

**Spacing → letterSpacing** (fixed per enum value; `_compose` maps 1:1)

| Spacing | letterSpacing |
|---------|---------------|
| `Tight` | `-0.15` |
| `Normal` | unset / `0` |
| `Track` | `0.2` |
| `Wide` | `0.8` |
| `Spread` | `0.4` (file-tree root tracking; between Track and Wide) |

Naming elision treats `Normal` only; `Track` / `Wide` / `Spread` / `Tight` always appear in the getter name when used (`xsTrack`, `xsBoldWide`, `mdBoldSpread`).

**Height → height** (fixed; no per-token exceptions)

| Height | height |
|--------|--------|
| `Snug` | `1.25` |
| `Normal` | `1.35` |
| `Relaxed` | `1.45` |

**Badge:** `xsSemiboldSnug` at standard Snug (`1.25`) — normalize away former `1.2`.

## Public API

- Named getters only for **shipped combinations** (closed list below + any added during migration when a call site needs a new combo).
- Each shipped getter has `{name}Colored(Color color)`.
- Muted shortcuts: `mutedXs`, `mutedSm`, `mutedMd` (= size + normal axes + `onSurfaceVariant`).
- `mono` / `monoColored` — monospace family on `md` metrics (not a four-axis name; theme helper role).

### Private compose

```dart
TextStyle _compose({
  required _TextSize size,
  _TextWeight weight = _TextWeight.normal,
  _TextSpacing spacing = _TextSpacing.normal,
  _TextHeight height = _TextHeight.normal,
}) { ... }
```

- **Not** part of the public API.
- Named getters are thin wrappers: `TextStyle get mdSemiboldTightSnug => _compose(...)`.
- UI code must not call `_compose` / must not invent combinations via `copyWith` on metrics.

### Warmup

`_appUiTextStylesFromTheme` must list **every shipped named getter** (and `mono`). Adding a getter without a warmup entry is a review failure. No public compose ⇒ no untracked runtime fingerprints from the scale API.

## Initial shipped combination set

Minimum to replace today’s API (add more only when migration discovers need):

| Getter | Replaces |
|--------|----------|
| `xs` | `caption` |
| `xsSemiboldSnug` | `badge` |
| `xsBoldWide` | `toolPanelTitle` |
| `xsTrack` | `settingsGroupHeader` |
| `sm` | `bodySmall` |
| `md` | `body` / most `formLabel` uses |
| `mdSnug` | `formLabel` if 1.25 leading required without weight change |
| `mdMedium` | medium body / `fileTreeEntryLabel(active: false)` |
| `mdSemibold` | `bodyStrong` / `fileTreeEntryLabel(active: true)` |
| `mdSemiboldTightSnug` | `sectionTitle` |
| `mdBoldSpread` | `fileTreeRootLabel` metrics (`Spread` = 0.4) |
| `lg` | `prominent` |
| `lgSnug` | `subtitle` |
| `lgSemiboldSnug` | `dialogTitle` |
| `xl` | `pageTitle` |
| `display` | `pageHeadline` |
| `mutedXs` / `mutedSm` / `mutedMd` | muted* |
| `mono` | `mono` |

Weight/spacing/height-only `copyWith` at call sites → promote to a new named getter + warmup entry in the same change.

## Call-site policy (`pages/` / `widgets/`)

**Allowed:** `styles.mdSemiboldColored(cs.error)`, `styles.mutedMd`, color-only `copyWith(color: …)` if needed.  
**Forbidden:** inline `TextStyle(...)`; raw `textTheme`; `copyWith` on `fontSize` / `letterSpacing` / `fontWeight` / `height`; public or local compose helpers.  
**Allowed read:** `style.fontSize` for layout math (e.g. toggle width).

## Facades

Remove `LlmWorkspaceText` / similar page typography facades; call sites use `AppTextStyles` scale names directly.

## CODE_QUALITY

> In `pages/` and `widgets/`, text styles must come from [`AppTextStyles`](../client/lib/theme/app_text_styles.dart) **named scale tokens** (`md`, `mdSemibold`, `xsBoldWide`, …) or other `lib/theme/` helpers (`dropdownFieldTextStyle`, `appMonoTextStyle`, `appTerminalTextStyle`, …). Do **not** construct `TextStyle(...)` inline, set `fontSize` / `letterSpacing` / `fontWeight` / `height` via `copyWith`, use raw `ThemeData.textTheme`, or invent combinations outside shipped getters. Prefer `*Colored` / `muted*`. Exceptions: syntax highlighting, terminal `TerminalStyle`, size-driven avatar glyphs, diff views that inherit editor font metrics. Every new `AppTextStyles` getter must be added to text warmup.

## Migration

1. Rewrite `AppTextStyles` with private `_compose` + new named getters only (delete old names same commit).
2. Mechanical rename across `client/lib/` + tests.
3. Update warmup + markdown style sheet bindings.
4. Remove facades; finish remaining `textTheme` / inline / metric-`copyWith` migrations.
5. Grep gate: no old semantic names; no raw textTheme in UI layers (documented exceptions only).

No dual-API period. No compatibility shims. No public `compose`.

## Exceptions (unchanged)

- `client/lib/theme/**` definition site  
- `editor_syntax_theme.dart`  
- Terminal `TerminalStyle` / `appTerminalTextStyle`  
- Diff views rebuilding `TextStyle` from editor metrics  
- Size-driven avatar / brand glyphs  
