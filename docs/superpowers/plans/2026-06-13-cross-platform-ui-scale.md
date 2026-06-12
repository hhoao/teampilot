# Cross-Platform UI Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TeamPilot's desktop UI render at one consistent, app-owned density on Linux, Windows, and macOS — matching the compact Ubuntu look — by taking UI scale away from the OS.

**Architecture:** A single app-owned scale multiplier (reusing the existing `AppTypographyScale.multiplier`, already persisted via the typography-scale setting) drives typography **and** new spacing tokens **and** icon sizes. The root `MediaQuery.textScaler` is neutralized so the OS (notably GNOME's `text-scaling-factor`, folded into `textScaler` by the GTK embedder on Linux) can no longer make platforms diverge. The embedded terminal keeps its own explicit sizing (no geometric distortion). Spec: `docs/superpowers/specs/2026-06-13-cross-platform-ui-scale-design.md`.

**Tech Stack:** Flutter, `flutter_bloc`, `flex_color_scheme`, `google_fonts`, `window_manager`, `flutter_alacritty`, `flutter_test`.

**Refinement vs spec:** Rather than rename the persisted `typographyScale` / `typographyScaleCustomMultiplier` fields to `uiScale` (the spec allowed but did not require this), we **reuse** them as the scale carrier (DRY — they are already plumbed through `LayoutPreferences` → `LayoutCubit` → `main.dart` → theme). The single source of truth is the resulting `AppTypographyScale.multiplier`, surfaced app-wide as `context.uiScale`. Spacing tokens live on a new `AppSpacingTheme`; icon roles on a new `AppIconSizeTheme`. A separate `AppDensityTheme` is not added (YAGNI — the raw multiplier rides on `AppSpacingTheme.scale`).

---

## File Structure

**Create:**
- `client/lib/theme/app_spacing.dart` — `AppSpacingTheme` ThemeExtension (spacing tokens + raw `scale`) + `context.appSpacing` / `context.uiScale`.
- `client/lib/widgets/app_text_scale_boundary.dart` — `AppTextScaleBoundary` widget that neutralizes the OS textScaler.
- `client/test/theme/app_spacing_test.dart`
- `client/test/theme/app_icon_sizes_test.dart`
- `client/test/widgets/app_text_scale_boundary_test.dart`
- `client/test/theme/ui_scale_theme_test.dart`

**Modify:**
- `client/lib/theme/app_icon_sizes.dart` — add `AppIconSizeTheme` extension; make `iconTheme` scale-aware.
- `client/lib/theme/app_theme.dart` — attach `AppSpacingTheme` + `AppIconSizeTheme`; pass scale to `iconTheme`.
- `client/lib/main.dart` — wrap builder child in `AppTextScaleBoundary`.
- `client/lib/services/terminal/terminal_fonts.dart` — terminal size from theme (`typography.terminal`), drop OS-textScaler dependence; update comment.
- `client/lib/pages/workspace_shell/workspace_shell.dart` — `82.0 * textScale` reads `context.uiScale` instead of OS textScaler.
- `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` — interface-scale label wording.
- Migration shells (Task 7): `pages/workspace_shell/`, `pages/home_workspace/` cards/list tiles, `pages/team_config/team_config_member_section.dart`, `pages/config/` sections.

---

## Task 0: Diagnostic — measure the real scaling inputs (evidence first)

**Why:** We must ground the compact default and the neutralization on the developer's actual Ubuntu values rather than guessing. `devicePixelRatio` and `textScaler` differ per platform; logging them once tells us what "the Ubuntu look" is in concrete numbers.

**Files:**
- Modify: `client/lib/main.dart` (temporary log, removed in Task 8)

- [ ] **Step 1: Add a one-time post-frame log in `TeamPilotApp.build`'s `MaterialApp.builder`**

In `client/lib/main.dart`, inside the `builder:` closure, before returning `content`, add:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final mq = MediaQuery.maybeOf(context);
  appLogger.i(
    'UI_SCALE_DIAG platform=${Platform.operatingSystem} '
    'dpr=${mq?.devicePixelRatio} textScaler=${mq?.textScaler} '
    'size=${mq?.size}',
  );
});
```

Add `import 'utils/logger.dart';` if not already present (it is imported as `installWindowsKeyboardWorkaround`'s neighbor — verify `appLogger` is in scope; the import is `import 'utils/logger.dart';`).

- [ ] **Step 2: Run on Ubuntu and capture the line**

Run: `cd client && flutter run -d linux`
Expected: a log line like `UI_SCALE_DIAG platform=linux dpr=1.0 textScaler=... size=...`. Record `dpr` and `textScaler`. (If available, repeat on Windows/macOS and record those too — used in Task 8.)

- [ ] **Step 3: Commit the diagnostic**

```bash
git add client/lib/main.dart
git commit -m "chore: add temporary UI scale diagnostic logging"
```

---

## Task 1: `AppSpacingTheme` token system

**Files:**
- Create: `client/lib/theme/app_spacing.dart`
- Test: `client/test/theme/app_spacing_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/theme/app_spacing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_spacing.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale multiplies base tokens by the scale multiplier', () {
    final compact = AppSpacingTheme.fromScale(AppTypographyScale.compact);
    expect(compact.scale, AppTypographyScale.compact.multiplier);
    expect(compact.md, AppSpacingTheme.mdBase * AppTypographyScale.compact.multiplier);
    expect(compact.lg, AppSpacingTheme.lgBase * AppTypographyScale.compact.multiplier);
  });

  test('standard scale leaves tokens at baseline', () {
    final std = AppSpacingTheme.fromScale(AppTypographyScale.standard);
    expect(std.scale, 1.0);
    expect(std.md, AppSpacingTheme.mdBase);
    expect(std.xxl, AppSpacingTheme.xxlBase);
  });

  test('lerp returns the target half is the switchover', () {
    final a = AppSpacingTheme.fromScale(AppTypographyScale.compact);
    final b = AppSpacingTheme.fromScale(AppTypographyScale.comfortable);
    expect(a.lerp(b, 0.6), b);
    expect(a.lerp(b, 0.4), a);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/theme/app_spacing_test.dart`
Expected: FAIL — `app_spacing.dart` does not exist.

- [ ] **Step 3: Create the implementation**

```dart
// client/lib/theme/app_spacing.dart
import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

/// Resolved spacing tokens on [ThemeData.extensions], derived from the active
/// [AppTypographyScale] multiplier (the app-owned UI scale). Read via
/// [BuildContext.appSpacing]; never hard-code [EdgeInsets] gaps in new code.
@immutable
final class AppSpacingTheme extends ThemeExtension<AppSpacingTheme> {
  const AppSpacingTheme({
    required this.scale,
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  /// Raw UI scale multiplier (1.0 = design baseline). Single source of truth for
  /// density; typography and icon sizes derive from the same value.
  final double scale;

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  // --- Baselines at scale 1.0 ---
  static const double xxsBase = 2;
  static const double xsBase = 4;
  static const double smBase = 8;
  static const double mdBase = 12;
  static const double lgBase = 16;
  static const double xlBase = 24;
  static const double xxlBase = 32;

  factory AppSpacingTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppSpacingTheme(
      scale: m,
      xxs: xxsBase * m,
      xs: xsBase * m,
      sm: smBase * m,
      md: mdBase * m,
      lg: lgBase * m,
      xl: xlBase * m,
      xxl: xxlBase * m,
    );
  }

  static AppSpacingTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppSpacingTheme>() ??
      AppSpacingTheme.fromScale(AppTypographyScale.standard);

  @override
  AppSpacingTheme copyWith({
    double? scale,
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) => AppSpacingTheme(
    scale: scale ?? this.scale,
    xxs: xxs ?? this.xxs,
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    xl: xl ?? this.xl,
    xxl: xxl ?? this.xxl,
  );

  @override
  AppSpacingTheme lerp(ThemeExtension<AppSpacingTheme>? other, double t) {
    if (other is! AppSpacingTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppSpacingContext on BuildContext {
  AppSpacingTheme get appSpacing => AppSpacingTheme.fromContext(this);

  /// Active app-owned UI scale multiplier (1.0 = baseline).
  double get uiScale => appSpacing.scale;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/theme/app_spacing_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/app_spacing.dart client/test/theme/app_spacing_test.dart
git commit -m "feat: add AppSpacingTheme density tokens"
```

---

## Task 2: Wire `AppSpacingTheme` into the theme + `context.uiScale`

**Files:**
- Modify: `client/lib/theme/app_theme.dart` (the `_applyTypography` function, both branches — lines ~248 and ~281 attach `extensions:`)
- Test: `client/test/theme/ui_scale_theme_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/theme/ui_scale_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_spacing.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('theme carries AppSpacingTheme that scales with typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdSpacing = std.extension<AppSpacingTheme>();
    final comfySpacing = comfy.extension<AppSpacingTheme>();

    expect(stdSpacing, isNotNull);
    expect(stdSpacing!.md, AppSpacingTheme.mdBase);
    expect(comfySpacing!.md, greaterThan(stdSpacing.md));
    expect(comfySpacing.scale, AppTypographyScale.comfortable.multiplier);
  });

  testWidgets('context.uiScale reflects the active theme scale', (tester) async {
    late double captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(null, AppTypographyScale.compact),
        home: Builder(
          builder: (context) {
            captured = context.uiScale;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, AppTypographyScale.compact.multiplier);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/theme/ui_scale_theme_test.dart`
Expected: FAIL — `extension<AppSpacingTheme>()` returns null.

- [ ] **Step 3: Attach the extension in both branches of `_applyTypography`**

In `client/lib/theme/app_theme.dart`, add the import near the other theme imports:

```dart
import 'app_spacing.dart';
```

In the **test/no-runtime-fonts** branch, change:

```dart
      extensions: [AppFontTheme.fallback, typographyTheme],
```
to:
```dart
      extensions: [
        AppFontTheme.fallback,
        typographyTheme,
        AppSpacingTheme.fromScale(typographyScale),
      ],
```

In the **runtime-fonts** branch, change:

```dart
    extensions: [
      buildAppFontTheme(uiFont: appUiFont),
      typographyTheme,
    ],
```
to:
```dart
    extensions: [
      buildAppFontTheme(uiFont: appUiFont),
      typographyTheme,
      AppSpacingTheme.fromScale(typographyScale),
    ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/theme/ui_scale_theme_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/app_theme.dart client/test/theme/ui_scale_theme_test.dart
git commit -m "feat: expose app-owned UI scale via theme (context.uiScale)"
```

---

## Task 3: Neutralize the OS textScaler at the root

**Files:**
- Create: `client/lib/widgets/app_text_scale_boundary.dart`
- Test: `client/test/widgets/app_text_scale_boundary_test.dart`
- Modify: `client/lib/main.dart` (the `MaterialApp.router` `builder:` closure, ~line 297)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/widgets/app_text_scale_boundary_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/app_text_scale_boundary.dart';

void main() {
  testWidgets('replaces inherited textScaler with noScaling', (tester) async {
    late TextScaler seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: AppTextScaleBoundary(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen, TextScaler.noScaling);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/app_text_scale_boundary_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create the widget**

```dart
// client/lib/widgets/app_text_scale_boundary.dart
import 'package:flutter/widgets.dart';

/// Replaces the OS-supplied [MediaQuery.textScaler] with [TextScaler.noScaling].
///
/// Platform text-scaling diverges the UI: on Linux the GTK embedder folds the
/// GNOME `text-scaling-factor` into [MediaQuery.textScaler]; Windows/macOS keep
/// it at 1.0. The app owns its density through the theme (typography + spacing +
/// icon sizes, driven by the interface-scale setting), so the OS textScaler is
/// neutralized here to keep all platforms identical at a given scale.
class AppTextScaleBoundary extends StatelessWidget {
  const AppTextScaleBoundary({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.textScaler == TextScaler.noScaling) return child;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.noScaling),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/app_text_scale_boundary_test.dart`
Expected: PASS.

- [ ] **Step 5: Wrap the app builder child**

In `client/lib/main.dart`, add the import with the other widget imports:

```dart
import 'widgets/app_text_scale_boundary.dart';
```

In the `builder:` closure, change:

```dart
          builder: (context, child) {
            Widget content = UiWarmup(child: child ?? const SizedBox.shrink());
```
to:
```dart
          builder: (context, child) {
            Widget content = AppTextScaleBoundary(
              child: UiWarmup(child: child ?? const SizedBox.shrink()),
            );
```

(`DragToResizeArea` still wraps `content` below this line — leave it unchanged.)

- [ ] **Step 6: Run the full suite to confirm nothing regressed**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/app_text_scale_boundary.dart client/lib/main.dart client/test/widgets/app_text_scale_boundary_test.dart
git commit -m "feat: neutralize OS textScaler so platforms share one UI scale"
```

---

## Task 4: Make icon sizes follow the UI scale

**Files:**
- Modify: `client/lib/theme/app_icon_sizes.dart`
- Modify: `client/lib/theme/app_theme.dart` (the two `AppIconSizes.iconTheme(scheme)` calls; attach `AppIconSizeTheme`)
- Test: `client/test/theme/app_icon_sizes_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/theme/app_icon_sizes_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('AppIconSizeTheme scales roles by the multiplier', () {
    final comfy = AppIconSizeTheme.fromScale(AppTypographyScale.comfortable);
    expect(comfy.md, AppIconSizes.mdBase * AppTypographyScale.comfortable.multiplier);
    expect(comfy.list, AppIconSizes.listBase * AppTypographyScale.comfortable.multiplier);
  });

  test('default IconThemeData size scales with the active scale', () {
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    expect(std.iconTheme.size, AppIconSizes.mdBase);
    expect(comfy.iconTheme.size, greaterThan(std.iconTheme.size!));
    expect(comfy.extension<AppIconSizeTheme>(), isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/theme/app_icon_sizes_test.dart`
Expected: FAIL — `AppIconSizeTheme` undefined.

- [ ] **Step 3: Add `AppIconSizeTheme` and a scale-aware `iconTheme`**

In `client/lib/theme/app_icon_sizes.dart`, add the import at the top:

```dart
import 'app_typography_scale.dart';
```

Change the `iconTheme` helper to take a multiplier:

```dart
  /// Default [IconThemeData] for app themes, scaled by [multiplier].
  static IconThemeData iconTheme(ColorScheme scheme, {double multiplier = 1.0}) =>
      IconThemeData(size: mdBase * multiplier, color: scheme.icon);
```

Append, after the `AppIconSizesContext` extension (end of file):

```dart
/// Resolved icon sizes on [ThemeData.extensions], scaled by the active
/// [AppTypographyScale] multiplier. Read non-default roles via
/// [BuildContext.appIconSizes]; the default size also flows through
/// [ThemeData.iconTheme].
@immutable
final class AppIconSizeTheme extends ThemeExtension<AppIconSizeTheme> {
  const AppIconSizeTheme({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.navRelaxed,
    required this.list,
    required this.empty,
    required this.hero,
    required this.display,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double navRelaxed;
  final double list;
  final double empty;
  final double hero;
  final double display;

  factory AppIconSizeTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppIconSizeTheme(
      xxs: AppIconSizes.xxsBase * m,
      xs: AppIconSizes.xsBase * m,
      sm: AppIconSizes.smBase * m,
      md: AppIconSizes.mdBase * m,
      lg: AppIconSizes.lgBase * m,
      xl: AppIconSizes.xlBase * m,
      navRelaxed: AppIconSizes.navRelaxedBase * m,
      list: AppIconSizes.listBase * m,
      empty: AppIconSizes.emptyBase * m,
      hero: AppIconSizes.heroBase * m,
      display: AppIconSizes.displayBase * m,
    );
  }

  static AppIconSizeTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppIconSizeTheme>() ??
      AppIconSizeTheme.fromScale(AppTypographyScale.standard);

  @override
  AppIconSizeTheme copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? navRelaxed,
    double? list,
    double? empty,
    double? hero,
    double? display,
  }) => AppIconSizeTheme(
    xxs: xxs ?? this.xxs,
    xs: xs ?? this.xs,
    sm: sm ?? this.sm,
    md: md ?? this.md,
    lg: lg ?? this.lg,
    xl: xl ?? this.xl,
    navRelaxed: navRelaxed ?? this.navRelaxed,
    list: list ?? this.list,
    empty: empty ?? this.empty,
    hero: hero ?? this.hero,
    display: display ?? this.display,
  );

  @override
  AppIconSizeTheme lerp(ThemeExtension<AppIconSizeTheme>? other, double t) {
    if (other is! AppIconSizeTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppIconSizeThemeContext on BuildContext {
  AppIconSizeTheme get appIconSizes => AppIconSizeTheme.fromContext(this);
}
```

- [ ] **Step 4: Pass the scale into `iconTheme` and attach `AppIconSizeTheme`**

In `client/lib/theme/app_theme.dart`, in **both** branches of `_applyTypography`, change:

```dart
      iconTheme: AppIconSizes.iconTheme(scheme),
```
to:
```dart
      iconTheme: AppIconSizes.iconTheme(scheme, multiplier: typographyScale.multiplier),
```

and add `AppIconSizeTheme.fromScale(typographyScale)` to **both** `extensions:` lists (alongside `AppSpacingTheme.fromScale(typographyScale)` from Task 2). Example for the runtime-fonts branch:

```dart
    extensions: [
      buildAppFontTheme(uiFont: appUiFont),
      typographyTheme,
      AppSpacingTheme.fromScale(typographyScale),
      AppIconSizeTheme.fromScale(typographyScale),
    ],
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/theme/app_icon_sizes_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/theme/app_icon_sizes.dart client/lib/theme/app_theme.dart client/test/theme/app_icon_sizes_test.dart
git commit -m "feat: scale icon sizes with the app-owned UI scale"
```

---

## Task 5: Repoint UI layout off OS textScaler onto `uiScale`

**Why:** With the OS textScaler neutralized (Task 3), code that multiplied layout by `MediaQuery.textScalerOf(context)` now multiplies by 1.0 — so those surfaces stop scaling at all. Repoint the ones that should follow density onto `context.uiScale`. The terminal reads its size from the theme (`typography.terminal`), which already bakes in the multiplier.

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart:67`
- Modify: `client/lib/services/terminal/terminal_fonts.dart` (~lines 24-34)

- [ ] **Step 1: Repoint the workspace topbar height**

In `client/lib/pages/workspace_shell/workspace_shell.dart`, add the import (with the other theme imports):

```dart
import 'package:teampilot/theme/app_spacing.dart';
```

Change line 67:

```dart
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
```
to:
```dart
    final textScale = context.uiScale;
```

(The `82.0 * textScale` usage below stays as-is; it now scales with the app-owned UI scale instead of the neutralized OS textScaler.)

- [ ] **Step 2: Make the terminal size from the theme**

In `client/lib/services/terminal/terminal_fonts.dart`, replace `appTerminalTextStyle` (lines ~24-34) with:

```dart
/// Terminal face + size from [AppTypographyTheme.terminal].
///
/// The terminal renders via [TerminalView] (a [CustomPaint], not a [Text]
/// widget), so it never picks up [MediaQuery.textScaler]. Density now comes from
/// the app-owned UI scale baked into [AppTypographyTheme.terminal]
/// (= terminalBase * uiScale), so the terminal scales with the rest of the UI
/// without any OS-textScaler dependence. The size drives both cell metrics and
/// glyph rendering, so columns stay aligned.
TerminalStyle appTerminalTextStyle(BuildContext context) {
  final typography = context.appTypography;
  final fonts = context.appFonts;
  return TerminalStyle(
    size: typography.terminal,
    family: fonts.monoFontFamily,
    lineHeight: 1.3,
    fallback: fonts.monoFontFamilyFallback,
  );
}
```

(Removes the now-unused `final textScaler = MediaQuery.textScalerOf(context);` line.)

- [ ] **Step 3: Analyze + run the suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: no new analyzer issues; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell.dart client/lib/services/terminal/terminal_fonts.dart
git commit -m "refactor: drive topbar + terminal density from uiScale, not OS textScaler"
```

---

## Task 6: Rename the user-facing setting to "Interface scale"

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Find the heading string for the typography-scale row**

Run: `cd client && grep -n "typographyScale\|字体\|Typography\|字号" lib/pages/config/layout_appearance_in_layout_section.dart`
Identify the `l10n.<key>` used as the row's title/label (e.g. `typographyScaleLabel` or similar).

- [ ] **Step 2: Update the label values (keys unchanged) in both ARB files**

In `client/lib/l10n/app_en.arb`, set the matched title key's value to `"Interface scale"` (and its description, if any, to "Overall UI density; applies the same on every platform.").

In `client/lib/l10n/app_zh.arb`, set the same key's value to `"界面缩放"` (description: "整体界面密度；三端一致。").

Leave the segment labels (`typographyScaleCompact` = Compact/紧凑, etc.) unchanged — they read well as density labels.

- [ ] **Step 3: Regenerate localizations + warmup glyphs**

Run: `cd client && flutter pub get && dart run tool/gen_warmup_glyphs.dart`
Expected: `app_localizations*.dart` and `lib/widgets/warmup_glyphs.g.dart` regenerate without error.

- [ ] **Step 4: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/ client/lib/widgets/warmup_glyphs.g.dart
git commit -m "feat: label the scale setting as Interface scale"
```

---

## Task 7: Migrate the visible shells to spacing tokens

> **SUPERSEDED (2026-06-13).** Replaced by a single root-level global zoom
> (`UiZoom`, `lib/widgets/ui_zoom.dart`) wired in `main.dart`, which scales the
> whole UI uniformly without migrating ~900 call-sites. The theme is built at the
> standard (1.0) baseline; the interface-scale value feeds `UiZoom` only. See the
> spec's "Revision 2026-06-13 — Pivot to global zoom". This task is not executed.

**Why:** The `uiScale` now reaches typography, icons, and the topbar — but most paddings are still hard-coded, so they do not get denser/looser with the scale. Migrate the shells shown in the bug report so the scale visibly reaches the layout. This is mechanical and incremental; do it shell-by-shell with its own commit.

**Migration recipe (apply per file):**
1. Add `import 'package:teampilot/theme/app_spacing.dart';` (or the correct relative import).
2. In each `build` (or section) that has hard-coded gaps, read `final s = context.appSpacing;` once.
3. Replace literal spacing with the nearest token:
   - `EdgeInsets.all(8)` → `EdgeInsets.all(s.sm)`; `12` → `s.md`; `16` → `s.lg`; `24` → `s.xl`.
   - `SizedBox(height: 8)` → `SizedBox(height: s.sm)`; `width: 12` → `s.md`; etc.
   - `EdgeInsets.symmetric(horizontal: 16, vertical: 10)` → `EdgeInsets.symmetric(horizontal: s.lg, vertical: s.md)` (round to the nearest token; exact pixel parity at scale 1.0 is not required, visual proportion is).
4. Leave structural constants that must NOT scale (border widths `1`, hairlines, `BorderRadius` already themed) alone. Do not touch panel min/max width constants in `LayoutPreferences` (those are user-draggable extents).
5. Do not touch the terminal widget tree.

**Worked example — `workspace_shell.dart` topbar padding (line ~74):**

```dart
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
```
becomes (note: drop `const`, and `s` is `context.appSpacing` read at top of `build`):

```dart
            padding: EdgeInsets.symmetric(horizontal: s.lg, vertical: s.md),
```

**Files (one commit each):**
- [ ] `client/lib/pages/workspace_shell/workspace_shell.dart` + `workspace_shell_tabs.dart`
- [ ] `client/lib/pages/home_workspace/home_workspace_project_card.dart`, `home_workspace_project_list_tile.dart`, `home_workspace_title_bar.dart`
- [ ] `client/lib/pages/team_config/team_config_member_section.dart`
- [ ] `client/lib/pages/config/session_config_section.dart`, `ai_features_config_section.dart`
- [ ] `client/lib/pages/home_workspace/project/` config/section files visible in the screenshots

- [ ] **Per file — Step A: apply the recipe.**
- [ ] **Per file — Step B:** Run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` → no new issues.
- [ ] **Per file — Step C:** Commit, e.g. `git commit -m "refactor: use spacing tokens in <file>"`.

- [ ] **Final audit:** Run `cd client && grep -rn "EdgeInsets\.\(all\|symmetric\|only\|fromLTRB\)([^)]*[0-9]" lib/pages/workspace_shell lib/pages/home_workspace lib/pages/team_config` and confirm the remaining literals are intentional (borders, zero, themed radii). Record any deferred files in the spec's Rollout section.

---

## Task 8: Pick + set the compact default; verify cross-platform; remove diagnostic

**Files:**
- Modify: `client/lib/theme/app_typography_scale.dart` (`kDefaultTypographyScaleId` and/or `AppTypographyScale.compact` multiplier, per measurement)
- Modify: `client/lib/main.dart` (remove the Task 0 diagnostic)

- [ ] **Step 1: Choose the default from the Task 0 measurements**

Using the recorded Ubuntu `dpr`/`textScaler` and the side-by-side comparison: the goal is that the **default** scale reproduces the developer's preferred Ubuntu density on all platforms. Decision rule:
- If Ubuntu measured `textScaler ≈ 1.0`: keep `kDefaultTypographyScaleId = 'standard'` (1.0). Neutralization alone aligns Windows/macOS to Ubuntu; the user can pick `compact` to taste.
- If Ubuntu measured `textScaler > 1.0` (GNOME text-scaling boosted the dev's UI): set the default so the baked-in multiplier reproduces that look — set `kDefaultTypographyScaleId = 'custom'` is wrong for a constant default; instead bump the `standard`/`compact` multiplier or change `kDefaultTypographyScaleId` to the preset nearest the measured value. Document the chosen number in a code comment citing the measurement.

- [ ] **Step 2: Apply the default**

Example (only if measurement calls for a denser default) — in `client/lib/theme/app_typography_scale.dart`:

```dart
// Default tuned to match Ubuntu @100% density measured 2026-06-13
// (dpr=<recorded>, textScaler=<recorded>). See plan Task 8.
const String kDefaultTypographyScaleId = 'compact';
```

- [ ] **Step 3: Remove the diagnostic logging from Task 0**

In `client/lib/main.dart`, delete the `WidgetsBinding.instance.addPostFrameCallback` `UI_SCALE_DIAG` block added in Task 0 (and the `utils/logger.dart` import if it is now unused).

- [ ] **Step 4: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: clean analyze; all tests PASS.

- [ ] **Step 5: Manual cross-platform verification (documented golden path; CI cannot cover)**

Build/run on each available platform at the default scale and capture the workspace shell + a team config page:
- Run: `cd client && flutter run -d linux` (and `-d windows` / `-d macos` where available).
- Confirm: the three platforms show matching density/proportions; the terminal text is crisp (no shimmer); changing the Interface-scale setting rescales typography + spacing + icons + terminal together.
Record the screenshots/notes in the PR description.

- [ ] **Step 6: Commit**

```bash
git add client/lib/theme/app_typography_scale.dart client/lib/main.dart
git commit -m "feat: set compact UI scale default and remove scale diagnostic"
```

---

## Self-Review (completed)

- **Spec coverage:** §4.1 uiScale source → Tasks 1,2,8 (reuse of typography scale). §4.2 textScaler neutralization → Task 3. §4.3 token layer (typography/spacing/icons) → Tasks 1,2,4. §4.4 spacing migration → Task 7. §4.5 terminal exclusion → Task 5. §4.6 settings UI → Task 6. §6 default selection → Tasks 0,8. §7 testing → Tasks 1-4 unit/widget + Task 8 manual. All covered.
- **Placeholder scan:** No `TBD`/`TODO`; every code step shows complete code; Task 6 Step 1 and Task 7 audit use concrete `grep` commands (not placeholders).
- **Type consistency:** `AppSpacingTheme` (`scale`, `xxs…xxl`, `fromScale`, `fromContext`), `context.appSpacing`/`context.uiScale`, `AppIconSizeTheme` (`fromScale`, `fromContext`), `AppIconSizes.iconTheme(scheme, {multiplier})`, `AppTextScaleBoundary` — names used consistently across tasks. `buildDarkTheme(colorPreset, typographyScale)` matches the existing signature in `app_theme.dart`.
