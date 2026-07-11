# Control & Button Theme Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share one control height between outline inputs and all standard Material buttons via `AppControlTheme`, merge geometry into Flex button themes without breaking tonal colors or pill radii, and remove conflicting local `styleFrom` overrides.

**Architecture:** `AppTypographyScale` → `AppControlTheme` → `InputDecorationTheme` + merged `*ButtonThemeData`. Button themes set geometry only (merge into Flex styles); colors stay on M3 `ColorScheme`. Call sites keep only semantic exceptions (e.g. error fills).

**Tech Stack:** Flutter Material 3, Flex Color Scheme, existing `client/lib/theme/` extensions.

**Spec:** [docs/superpowers/specs/2026-07-11-control-button-theme-alignment-design.md](../specs/2026-07-11-control-button-theme-alignment-design.md)

**Locked choices (from spec):**

| Topic | Choice |
|-------|--------|
| Height token | `AppControlTheme.height` baseline **40**, scales with `typographyScale` |
| Button theme colors | **Geometry only** — never set filled bg/fg on shared `filledButtonTheme` (tonal shares it) |
| Flex pill radius | **Merge** geometry into existing Flex `*ButtonTheme.style`; do not replace whole style |
| Local overrides | Purge height/padding/default-fg conflicts; keep error/destructive and intentional semantic colors |
| Log toolbar | Use `AppControlTheme.height` (drop local 36) |
| Compatibility | None — 36px outlined minimum deleted |

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/theme/app_control_theme.dart` | `AppControlTheme` extension + `context.appControl` |
| `client/lib/theme/app_button_theme.dart` | `buildAppButtonThemes` — merge geometry into Flex button themes |
| `client/lib/theme/app_outline_input_theme.dart` | Input min height / padding from `AppControlTheme` |
| `client/lib/theme/app_theme.dart` | Wire control + button themes in **both** `_applyTypography` branches |
| `client/lib/theme/app_text_styles_warmup.dart` | Pass `AppControlTheme` into input decoration builder |
| `client/lib/pages/system/log_viewer_toolbar.dart` | Drop `_controlHeight = 36`; use control theme height |
| Call sites under `client/lib/pages/**`, `client/lib/widgets/**` | Remove conflicting `styleFrom` geometry / default fg |
| `client/test/theme/app_control_theme_test.dart` | Scale math |
| `client/test/theme/control_button_theme_test.dart` | Height equality, tonal colors, stadium shape |

---

### Task 1: `AppControlTheme` + failing scale test

**Files:**
- Create: `client/lib/theme/app_control_theme.dart`
- Create: `client/test/theme/app_control_theme_test.dart`

- [x] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('fromScale uses baseline 40 at multiplier 1', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.standard);
    expect(c.height, 40);
    expect(c.minWidth, 64);
    expect(c.horizontalPadding, 12);
    expect(c.verticalPadding, 13);
  });

  test('fromScale multiplies tokens by typography multiplier', () {
    final c = AppControlTheme.fromScale(AppTypographyScale.comfortable);
    expect(c.height, 40 * AppTypographyScale.comfortable.multiplier);
    expect(c.minWidth, 64 * AppTypographyScale.comfortable.multiplier);
    expect(c.horizontalPadding, 12 * AppTypographyScale.comfortable.multiplier);
    expect(c.verticalPadding, 13 * AppTypographyScale.comfortable.multiplier);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/theme/app_control_theme_test.dart
```

Expected: FAIL (library / type not found).

- [x] **Step 3: Implement `AppControlTheme`**

Create `client/lib/theme/app_control_theme.dart` mirroring `AppSpacingTheme` patterns:

```dart
import 'package:flutter/material.dart';

import 'app_typography_scale.dart';

@immutable
final class AppControlTheme extends ThemeExtension<AppControlTheme> {
  const AppControlTheme({
    required this.scale,
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.verticalPadding,
  });

  final double scale;
  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double verticalPadding;

  static const double heightBase = 40;
  static const double minWidthBase = 64;
  static const double horizontalPaddingBase = 12;
  static const double verticalPaddingBase = 13;

  factory AppControlTheme.fromScale(AppTypographyScale scale) {
    final m = scale.multiplier;
    return AppControlTheme(
      scale: m,
      height: heightBase * m,
      minWidth: minWidthBase * m,
      horizontalPadding: horizontalPaddingBase * m,
      verticalPadding: verticalPaddingBase * m,
    );
  }

  static AppControlTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppControlTheme>() ??
      AppControlTheme.fromScale(AppTypographyScale.standard);

  @override
  AppControlTheme copyWith({
    double? scale,
    double? height,
    double? minWidth,
    double? horizontalPadding,
    double? verticalPadding,
  }) => AppControlTheme(
    scale: scale ?? this.scale,
    height: height ?? this.height,
    minWidth: minWidth ?? this.minWidth,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    verticalPadding: verticalPadding ?? this.verticalPadding,
  );

  @override
  AppControlTheme lerp(ThemeExtension<AppControlTheme>? other, double t) {
    if (other is! AppControlTheme) return this;
    return AppControlTheme(
      scale: lerpDouble(scale, other.scale, t)!,
      height: lerpDouble(height, other.height, t)!,
      minWidth: lerpDouble(minWidth, other.minWidth, t)!,
      horizontalPadding: lerpDouble(horizontalPadding, other.horizontalPadding, t)!,
      verticalPadding: lerpDouble(verticalPadding, other.verticalPadding, t)!,
    );
  }
}

extension AppControlContext on BuildContext {
  AppControlTheme get appControl => AppControlTheme.fromContext(this);
}
```

Import `dart:ui` show `lerpDouble` or use `package:flutter/foundation.dart` / Material export as elsewhere in the repo (`app_spacing.dart` pattern).

- [x] **Step 4: Run test to verify it passes**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/theme/app_control_theme_test.dart
```

Expected: PASS.

- [x] **Step 5: Commit** (only if the user asked for commits in this session; otherwise skip and continue)

```bash
git add client/lib/theme/app_control_theme.dart client/test/theme/app_control_theme_test.dart
git commit -m "$(cat <<'EOF'
feat(theme): add AppControlTheme shared control height token

EOF
)"
```

---

### Task 2: Button theme merge helper + theme integration tests (TDD)

**Files:**
- Create: `client/lib/theme/app_button_theme.dart`
- Create: `client/test/theme/control_button_theme_test.dart`
- Modify: `client/lib/theme/app_outline_input_theme.dart`
- Modify: `client/lib/theme/app_theme.dart`
- Modify: `client/lib/theme/app_text_styles_warmup.dart`
- Modify: `client/test/theme/input_theme_test.dart` (if signature breaks compile)

- [x] **Step 1: Write failing integration tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('input and standard button min heights share AppControlTheme.height', () {
    final theme = buildDarkTheme();
    final control = theme.extension<AppControlTheme>()!;
    final inputMin = theme.inputDecorationTheme.constraints?.minHeight;
    expect(inputMin, control.height);

    Size? minOf(ButtonStyle? style) => style?.minimumSize?.resolve({});
    expect(minOf(theme.filledButtonTheme.style)?.height, control.height);
    expect(minOf(theme.outlinedButtonTheme.style)?.height, control.height);
    expect(minOf(theme.elevatedButtonTheme.style)?.height, control.height);
    expect(minOf(theme.textButtonTheme.style)?.height, control.height);
  });

  test('control height tracks typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    expect(
      comfy.extension<AppControlTheme>()!.height,
      greaterThan(std.extension<AppControlTheme>()!.height),
    );
    expect(
      comfy.inputDecorationTheme.constraints?.minHeight,
      comfy.extension<AppControlTheme>()!.height,
    );
  });

  testWidgets('FilledButton and tonal keep distinct scheme foregrounds', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('filled')),
              FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
            ],
          ),
        ),
      ),
    );

    Color fg(String label) {
      final text = tester.widget<Text>(find.text(label));
      // Resolve via DefaultTextStyle / ButtonStyle — prefer reading
      // DefaultTextStyle.of around the Text, or styleFrom resolution.
      final element = tester.element(find.text(label));
      return DefaultTextStyle.of(element).style.color!;
    }

    expect(fg('filled'), theme.colorScheme.onPrimary);
    expect(fg('tonal'), theme.colorScheme.onSecondaryContainer);
  });

  test('filled/outlined/elevated retain stadium-like shape after merge', () {
    final theme = buildDarkTheme();
    OutlinedBorder? shapeOf(ButtonStyle? style) {
      final s = style?.shape?.resolve({});
      return s is OutlinedBorder ? s : null;
    }

    bool looksPill(OutlinedBorder? b) {
      if (b == null) return false;
      if (b is StadiumBorder) return true;
      if (b is RoundedRectangleBorder) {
        final r = b.borderRadius;
        if (r is BorderRadius) {
          return r.topLeft.x >= 20; // pill-ish vs input 8
        }
      }
      return false;
    }

    expect(looksPill(shapeOf(theme.filledButtonTheme.style)), isTrue);
    expect(looksPill(shapeOf(theme.outlinedButtonTheme.style)), isTrue);
    expect(looksPill(shapeOf(theme.elevatedButtonTheme.style)), isTrue);
  });
}
```

Adjust `fg` resolution if `DefaultTextStyle` is not enough — use `tester.widget<FilledButton>(...).style` merged with theme via `style?.foregroundColor?.resolve({})` after pumping. Goal: prove tonal ≠ filled foreground.

- [x] **Step 2: Run tests — expect FAIL**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/theme/control_button_theme_test.dart
```

Expected: FAIL (extension missing / heights 36 vs 40 / shape wiped if naive replace).

- [x] **Step 3: Implement `buildAppButtonThemes`**

`client/lib/theme/app_button_theme.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_control_theme.dart';

typedef AppButtonThemes = ({
  FilledButtonThemeData filled,
  OutlinedButtonThemeData outlined,
  ElevatedButtonThemeData elevated,
  TextButtonThemeData text,
});

AppButtonThemes buildAppButtonThemes({
  required AppControlTheme control,
  required ThemeData flexTheme,
}) {
  final geometry = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(control.minWidth, control.height),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: control.horizontalPadding),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  ButtonStyle merge(ButtonStyle? base) =>
      base?.merge(geometry) ?? geometry;

  // If Flex left style null and stadium tests fail, fall back by merging
  // geometry with `shape: WidgetStatePropertyAll(const StadiumBorder())`
  // (or radius 999 RoundedRectangleBorder) — still no colors.

  return (
    filled: FilledButtonThemeData(
      style: merge(flexTheme.filledButtonTheme.style),
    ),
    outlined: OutlinedButtonThemeData(
      style: merge(flexTheme.outlinedButtonTheme.style),
    ),
    elevated: ElevatedButtonThemeData(
      style: merge(flexTheme.elevatedButtonTheme.style),
    ),
    text: TextButtonThemeData(
      style: merge(flexTheme.textButtonTheme.style),
    ),
  );
}
```

- [x] **Step 4: Update input decoration to take `AppControlTheme`**

In `buildAppOutlineInputDecorationTheme`, add `required AppControlTheme control` and replace hard-coded padding / minHeight:

```dart
contentPadding: EdgeInsets.symmetric(
  horizontal: control.horizontalPadding,
  vertical: control.verticalPadding,
),
constraints: BoxConstraints(minHeight: control.height),
```

- [x] **Step 5: Wire `_applyTypography` (both branches)**

1. After `flexTheme = _withSoftenedForeground(flexTheme);`, build:
   `final control = AppControlTheme.fromScale(typographyScale);`
2. Remove `compactOutlinedButton`.
3. `final buttons = buildAppButtonThemes(control: control, flexTheme: flexTheme);`
4. In **both** `copyWith` returns:
   - Add `control` to `extensions: [...]`
   - `inputDecorationTheme: buildAppOutlineInputDecorationTheme(..., control: control)`
   - `filledButtonTheme: buttons.filled`
   - `outlinedButtonTheme: buttons.outlined`
   - `elevatedButtonTheme: buttons.elevated`
   - `textButtonTheme: buttons.text`

- [x] **Step 6: Fix warmup caller**

In `app_text_styles_warmup.dart`, pass `control: AppControlTheme.fromScale(AppTypographyScale.standard)` (or the `textScale` in interactive warmup path when available).

- [x] **Step 7: Run theme tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/theme/
```

Expected: all PASS. Fix tonal fg assertion technique if needed without setting global filled colors.

- [x] **Step 8: Commit** (if user requested commits)

```bash
git add client/lib/theme/ client/test/theme/
git commit -m "$(cat <<'EOF'
feat(theme): align input and button control heights via AppControlTheme

EOF
)"
```

---

### Task 3: Purge conflicting local button styles

**Files:** every `style:` / `styleFrom` under `client/lib/pages` and `client/lib/widgets` for Filled/Outlined/Elevated/Text buttons (discover via Task 3 Step 1 `rg`). Also `client/lib/pages/system/log_viewer_toolbar.dart`.

**Keep** when the style is semantic:
- `backgroundColor: colorScheme.error` / `foregroundColor: colorScheme.onError` (delete confirms)
- Other intentional non-primary fills (success/warning) if present
- Width-only layout via parent `SizedBox` / `Expanded` (prefer parent over `fixedSize` height)

**Remove** when the style only duplicates theme:
- `minimumSize` / height-related `fixedSize` / compact padding used to match fields
- `foregroundColor` / `backgroundColor` that restate `primary` / `onPrimary` / default outlined fg
- Entire `style:` argument if empty after cleanup

Known hits to inspect (not necessarily all delete):

| File | Likely action |
|------|----------------|
| `team_delete_confirm_dialog.dart`, `worktree_delete_dialog.dart`, `team_config_member_dialogs.dart` | Keep error colors; drop geometry if any |
| `skill_management_cards.dart`, `plugin_management_cards.dart`, `skill_discover_card.dart` | Drop default primary restatements |
| `workspace_info_section.dart`, `team_config_info_section.dart`, `ai_features_config_section.dart` | Drop outlined geometry/padding |
| `app_dropdown_with_custom_input.dart` | Align to theme height; remove local min sizes |
| `workspace_folder_directory_row.dart` | `minimumSize: Size.zero` — replace with theme or document as dense text action exception; prefer theme |
| `app_toast.dart` | Toast actions may stay denser — **exception**: keep compact toast actions (not form controls) |
| `diff_toolbar.dart` | Out of standard track per spec — leave unless it is a standard Material button fighting form rows |
| `log_viewer_toolbar.dart` | Replace `_controlHeight = 36` with `context.appControl.height` |

- [x] **Step 1: Grep inventory**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && rg -n "FilledButton\.styleFrom|OutlinedButton\.styleFrom|TextButton\.styleFrom|ElevatedButton\.styleFrom|minimumSize:" lib/
```

- [x] **Step 2: Edit call sites per keep/remove rules**

Work file-by-file; run analyzer on touched files periodically.

- [x] **Step 3: Migrate log viewer toolbar**

Replace `static const _controlHeight = 36.0` with `AppControlTheme.fromContext(context).height` (or `context.appControl.height`).

- [x] **Step 4: Analyze + focused tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/theme/ --exclude-tags integration
```

Expected: clean / PASS.

- [x] **Step 5: Commit** (if user requested commits)

```bash
git add -u client/lib client/test
git commit -m "$(cat <<'EOF'
refactor(ui): drop local button styles that fight control theme

EOF
)"
```

---

### Task 4: Verification

- [x] **Step 1: Full unit test suite (exclude integration)**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test --exclude-tags integration
```

**Verification results (2026-07-11):**

- Focused `flutter test test/theme/`: **29/29 PASS**
- Full `flutter test --exclude-tags integration`: **+2891 −6** (approx; count may vary)
- **5 failures** in `client/test/widget_test.dart`: missing `Provider<UiZoomBaseline>` / `LayoutCubit` harness — pre-existing on main, unrelated to control theme
- **1 intermittent load flake:** `test/services/file_tree/workspace_file_tree_store_test.dart` (`HttpException` connection closed) — infra flake, passes alone
- **No failures** attributed to `AppControlTheme` / button geometry / style purge

- [x] **Step 2: Manual smoke checklist** (human or agent with UI)

1. Settings / About: Filled + Outlined + tonal in one row — same height as nearby fields.
2. Form row: path field + Browse `OutlinedButton` — tops/bottoms align.
3. Dark + light, amber + graphite presets: filled label readable (`onPrimary`); tonal still distinct.
4. Delete confirm dialog: error-colored filled button still red with `onError` text.

- [x] **Step 3: Mark spec status Implemented** when landed (edit spec header Status line).

---

## Out of scope (do not do in this plan)

- `IconButton` / chip / segmented redesign
- Fixing `AppSpacingTheme` always-standard wiring (noted in spec as optional follow-up)
- New `AppPrimaryButton` widget wrappers
- Palette redesign for contrast (only if tonal/filled tests fail due to scheme; then fix seeds, not button theme colors)
