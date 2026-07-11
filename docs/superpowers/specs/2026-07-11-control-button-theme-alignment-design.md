# Control & Button Theme Alignment

**Date:** 2026-07-11  
**Status:** Implemented  
**Owner decision:** Global `ThemeData` control track (height + Material semantic foregrounds); shared `AppControlTheme` token for inputs and standard buttons; remove conflicting local `styleFrom` overrides. No backward compatibility with the current 36px outlined / ad-hoc button heights.

## Problem

Standard buttons (`FilledButton`, `OutlinedButton`, `ElevatedButton`, `TextButton` and their `.icon` / `.tonal` variants) do not share a height with outline text fields. Inputs already use a global `InputDecorationTheme` with `minHeight: 40`, while `outlinedButtonTheme` hard-codes `minimumSize: Size(64, 36)` and filled/text buttons mostly inherit Flex Color Scheme defaults. Call sites further override padding, `minimumSize`, and foreground colors, so form rows (field + action) and settings pages look uneven, and label contrast is inconsistent across presets.

## Goals

- One **control height** shared by outline inputs and all standard Material buttons.
- Button label / icon colors follow **Material `ColorScheme` semantics** (`onPrimary`, `onSecondaryContainer`, `onSurface`, `primary`, etc.) — never hard-coded pure white/black at call sites for default variants.
- Configure once in theme; new screens get correct size and contrast without local style copies.
- Extensible: density / typography scale adjusts control height from the same multiplier as spacing.
- Delete conflicting local height / foreground overrides so theme is the source of truth.

## Non-goals

- Redesigning button shape language (pill radius 999 for filled/outlined/elevated stays; input radius 8 stays).
- Restyling `IconButton`, `SegmentedButton`, chips, custom toolbar chrome, or editor/diff toolbars beyond removing accidental standard-button overrides.
- Introducing a parallel widget kit (`AppPrimaryButton` wrappers) as the primary API — theme defaults are enough; wrappers only if a later feature needs a named variant.
- Changing ColorScheme seed palettes or Flex blend levels.
- Android-only / platform-specific button metrics.

## Decision

**Shared control token + full button theme suite on `ThemeData`, then purge conflicting local styles.**

```text
AppTypographyScale.multiplier
  → AppControlTheme (height, paddings, minWidth)
      → InputDecorationTheme.constraints.minHeight / contentPadding
      → filledButtonTheme / outlinedButtonTheme /
        elevatedButtonTheme / textButtonTheme
```

Do not rely on Flex `subThemesData` alone for height: FCS button min-heights are easy to drift from the hand-tuned input theme. Own the numbers in `AppControlTheme` and apply them in `_applyTypography` (same place input decoration is already applied).

## Architecture

### `AppControlTheme` (`ThemeExtension`)

New file: `client/lib/theme/app_control_theme.dart`.

| Field | Baseline @ scale 1.0 | Role |
|-------|----------------------|------|
| `height` | `40` | Shared min height for inputs and standard buttons |
| `minWidth` | `64` | Button `minimumSize.width` |
| `horizontalPadding` | `12` | Button + input horizontal padding |
| `verticalPadding` | `13` | Input `contentPadding` vertical (keep current visual); buttons use symmetric padding that yields `height` with `minimumSize` |
| `tapTargetSize` | `MaterialTapTargetSize.shrinkWrap` | Match existing compact density |
| `visualDensity` | `VisualDensity.compact` | Already set on `ThemeData`; document as part of control track |

Factory: `AppControlTheme.fromScale(AppTypographyScale)` — multiply `height`, paddings, and `minWidth` by `scale.multiplier` (same pattern as `AppSpacingTheme`).

**Scale wiring (v1):** Pass the same `typographyScale` argument already used for text/icon materialization in `_applyTypography` into `AppControlTheme.fromScale(typographyScale)`. Do **not** hard-code `AppTypographyScale.standard` the way `AppSpacingTheme` currently does — control height must track UI text scale so fields and buttons stay aligned when the user changes typography scale. (Optionally fix `AppSpacingTheme` to the same wiring in a follow-up; out of scope here except that control must not copy the “always standard” bug.)

Access: `Theme.of(context).extension<AppControlTheme>()` / `context.appControl`.

Register on both light/dark paths in `_applyTypography` `extensions: [...]`.

### Input decoration

`buildAppOutlineInputDecorationTheme` gains a required `AppControlTheme control` (or reads height/padding from it). Replace hard-coded `minHeight: 40` and `contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13)` with control tokens. Border radius stays `8` (shape, not control height).

### Button themes

In `_applyTypography`, replace the outlined-only `compactOutlinedButton` with a shared builder, e.g. `buildAppButtonThemes({required AppControlTheme control, required ThemeData flexTheme})` that **merges geometry into the Flex-produced button themes** already on `flexTheme` (do not construct bare `ButtonStyle`s that replace the whole theme and drop FCS shape).

Merge rule per variant (`filled` / `outlined` / `elevated` / `text`):

```text
base = flexTheme.filledButtonTheme.style  // (or outlined / elevated / text)
merged = base?.merge(geometry) ?? geometry
// geometry sets ONLY:
minimumSize, padding, tapTargetSize, visualDensity
```

- **Preserve** Flex pill / stadium shape from `_subThemes` (`filledButtonRadius` / `outlinedButtonRadius` / `elevatedButtonRadius: 999`) by merging, not replacing.
- Do **not** pass `ColorScheme` into the builder for painting colors (avoids reintroducing global filled colors that collapse tonal). Geometry-only.
- If merge ever proves insufficient (e.g. Flex left `style` null), fall back by copying shape from the sibling theme or re-declaring `StadiumBorder` / radius **999** without setting colors.

Shared **geometry only** for **Filled / Outlined / Elevated / Text** (including tonal and icon constructors, which read the same theme slots):

```text
minimumSize: Size(control.minWidth, control.height)
padding: EdgeInsets.symmetric(horizontal: control.horizontalPadding)
tapTargetSize: shrinkWrap
visualDensity: compact
// Do NOT set backgroundColor / foregroundColor / textStyle color.
// Do NOT set shape unless merge fallback requires re-declaring stadium radius.
```

**Critical Flutter constraint:** `FilledButton` and `FilledButton.tonal` share a single `ThemeData.filledButtonTheme`. Setting global `backgroundColor` / `foregroundColor` on that theme forces both variants to the same colors and **breaks tonal**. Therefore:

- `filledButtonTheme` / `elevatedButtonTheme` / `outlinedButtonTheme` / `textButtonTheme` set **geometry** (`minimumSize`, `padding`, `tapTargetSize`, `visualDensity`) only.
- **Colors stay on Material 3 + `ColorScheme` defaults** (and Flex sub-themes already applied before `_applyTypography`). Do not paint literal `Colors.white` / `Colors.black` on the global themes.
- Expected enabled roles (documentation / test expectations against M3 defaults, not values we assign on the shared filled theme):

| Variant | Background (M3 default) | Foreground (M3 default) |
|---------|-------------------------|-------------------------|
| `FilledButton` | `primary` | `onPrimary` |
| `FilledButton.tonal` | `secondaryContainer` | `onSecondaryContainer` |
| `ElevatedButton` | M3 elevated surface container (scheme-driven; do not assert exact token in tests) | `primary` |
| `OutlinedButton` | transparent | `primary` |
| `TextButton` | transparent | `primary` |

If a preset’s soft primary yields poor filled contrast, fix it by adjusting **palette / `ColorScheme.onPrimary`** (or Flex scheme mapping), not by hard-coding button theme foregrounds that would also hit tonal.

Disabled states: Material defaults (`onSurface` @ disabled opacity). Do not invent custom disabled colors.

TextButton may stay rectangular / low radius per FCS; do not force pill on text-only actions. Filled / outlined / elevated keep Flex stadium radii via the merge rule above.

### Local override cleanup

Scan `client/lib` for `FilledButton` / `OutlinedButton` / `ElevatedButton` / `TextButton` with `style:` / `styleFrom` that set any of:

- `minimumSize`, `fixedSize`, `maximumSize`
- `padding` / `visualDensity` / `tapTargetSize` when only used to fake height alignment
- `foregroundColor`, `backgroundColor`, `textStyle` color when duplicating scheme roles

**Remove** those properties (or the whole `style:` if empty after removal).

**Keep** local styles that encode *semantic* exceptions:

- Destructive confirm: `backgroundColor: colorScheme.error`, `foregroundColor: colorScheme.onError`
- Success / warning one-offs that intentionally diverge from primary
- Width constraints for layout (`fixedSize` width-only or `SizedBox` parent) when not changing height
- Opacity / disabled presentation that is not height-related

Rule of thumb for new code: prefer bare `FilledButton(...)` / `OutlinedButton.icon(...)`; only pass `style` for semantic color or rare layout width.

### Exceptions (out of standard track)

| Control | Policy |
|---------|--------|
| `IconButton` / `AppIconButton` | Unchanged; not height-aligned to inputs |
| Diff / editor toolbars using raw `ButtonStyle` | Leave unless they are standard Material button widgets with conflicting overrides |
| `log_viewer_toolbar` `_controlHeight = 36` | Migrate to `AppControlTheme.height` **or** introduce `AppControlTheme.compactHeight` only if product still needs denser log chrome; default decision: **use standard `height`** for consistency |
| Dialog actions | Use theme defaults (40); do not shrink |

### Tests

- Unit: `AppControlTheme.fromScale` scales height with multiplier.
- Theme: `buildLightTheme` / `buildDarkTheme` — `inputDecorationTheme.constraints.minHeight` equals `minimumSize.height` on `filledButtonTheme`, `outlinedButtonTheme`, `elevatedButtonTheme`, and `textButtonTheme`.
- Theme: with **no** color overrides on `filledButtonTheme`, a default `FilledButton` resolves enabled foreground to `onPrimary` and a `FilledButton.tonal` resolves to `onSecondaryContainer` (widget test or style resolution against `ThemeData`). Geometry `minimumSize.height` matches `AppControlTheme.height` for both.
- Theme: filled / outlined / elevated resolved `shape` remains stadium / pill (radius effectively full-height), proving Flex radius survived the merge.
- Widget (optional smoke): row with `TextField` + `OutlinedButton` shares painted height under standard scale.

Extend `client/test/theme/input_theme_test.dart` or add `client/test/theme/control_button_theme_test.dart`.

## File touch list (implementation)

| Area | Path |
|------|------|
| New token | `client/lib/theme/app_control_theme.dart` |
| Theme wire-up | `client/lib/theme/app_theme.dart` — **both** `_applyTypography` return branches (Google Fonts on and test/offline seed) must register `AppControlTheme` and merged button themes |
| Input theme | `client/lib/theme/app_outline_input_theme.dart` |
| Button theme builder | `client/lib/theme/app_button_theme.dart` (preferred split; keep `app_theme.dart` under soft size limits) |
| Warmup / other callers | `client/lib/theme/app_text_styles_warmup.dart` (and any other `buildAppOutlineInputDecorationTheme` call sites) must pass `AppControlTheme` when the signature requires it |
| Call-site cleanup | All `styleFrom` / `ButtonStyle` hits under `client/lib/pages` and `client/lib/widgets` that conflict with height/foreground |
| Tests | `client/test/theme/control_button_theme_test.dart` (+ adjust input theme tests if signatures change) |

## Migration / compatibility

**No compatibility shim.** Old 36px outlined minimum and scattered local heights are deleted. Visual change is intentional across the app.

## Success criteria

1. At standard typography scale, outline `TextField` min height and standard button min height are both 40 (scaled together when UI scale ≠ 1).
2. Default filled / tonal / outlined / text label colors come from M3 `ColorScheme` roles (`onPrimary`, `onSecondaryContainer`, `primary`, …) — global button themes do not hard-code white/black, and do not set filled colors that would collapse tonal into filled.
3. New form rows can place `TextField` + `OutlinedButton` / `FilledButton` without local `styleFrom` for height.
4. `flutter analyze` / unit tests for theme pass; no new max-lines pressure on `app_theme.dart` (split builder if needed).
