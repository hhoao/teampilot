# Onboarding CLI Row Narrow Layout + TpBreakpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Tailwind-aligned `TpBreakpoints` to `shared_ui`, and stack `OnboardingCliRow` into two lines when `width < sm` (640).

**Architecture:** Pure token + predicate helpers in `shared_ui` (`up` / `down` / `only`). CLI row uses `LayoutBuilder` + `TpBreakpoints.down(..., sm)`. Shell product breakpoint 840 stays untouched.

**Tech Stack:** Flutter, `shared_ui` design tokens, flutter_test.

## Global Constraints

- Breakpoint px: `sm=640`, `md=768`, `lg=1024`, `xl=1280`, `xxl=1536` (2xl).
- Semantics: `up` ⇒ `width >= token`; `down` ⇒ `width < token`; `only` ⇒ `[token, next)` except `xxl` ⇒ `width >= 1536`.
- Do not change `WorkspacePanePolicy.narrowBreakpointWidth` (840).
- Do not migrate existing 720/820/768 call sites in this plan.
- Do not change `CliExecutablePathSettingsRow`.
- Do not commit unless the user explicitly asks.

---

### Task 1: `TpBreakpoints` token + tests

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/tokens/tp_breakpoints.dart`
- Create: `client/packages/shared_ui/test/theme/tp_breakpoints_test.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (add export)
- Modify: `client/packages/shared_ui/README.md` (short Breakpoints section after Theme or before TpSidebar)

**Interfaces:**
- Consumes: none
- Produces:
  - `enum TpBreakpoint { sm, md, lg, xl, xxl }`
  - `abstract final class TpBreakpoints` with `sm/md/lg/xl/xxl` consts, `of`, `up`, `down`, `only`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  group('TpBreakpoints tokens', () {
    test('match Tailwind screens', () {
      expect(TpBreakpoints.sm, 640);
      expect(TpBreakpoints.md, 768);
      expect(TpBreakpoints.lg, 1024);
      expect(TpBreakpoints.xl, 1280);
      expect(TpBreakpoints.xxl, 1536);
      expect(TpBreakpoints.of(TpBreakpoint.sm), 640);
      expect(TpBreakpoints.of(TpBreakpoint.xxl), 1536);
    });
  });

  group('up (mobile first)', () {
    test('sm boundary', () {
      expect(TpBreakpoints.up(639, TpBreakpoint.sm), isFalse);
      expect(TpBreakpoints.up(640, TpBreakpoint.sm), isTrue);
    });
  });

  group('down (desktop first / <token)', () {
    test('sm boundary', () {
      expect(TpBreakpoints.down(639, TpBreakpoint.sm), isTrue);
      expect(TpBreakpoints.down(640, TpBreakpoint.sm), isFalse);
    });
  });

  group('only (@token band)', () {
    test('sm is [640, 768)', () {
      expect(TpBreakpoints.only(639, TpBreakpoint.sm), isFalse);
      expect(TpBreakpoints.only(640, TpBreakpoint.sm), isTrue);
      expect(TpBreakpoints.only(767, TpBreakpoint.sm), isTrue);
      expect(TpBreakpoints.only(768, TpBreakpoint.sm), isFalse);
    });

    test('xxl is width >= 1536', () {
      expect(TpBreakpoints.only(1535, TpBreakpoint.xxl), isFalse);
      expect(TpBreakpoints.only(1536, TpBreakpoint.xxl), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `client/packages/shared_ui`:

```bash
dart test test/theme/tp_breakpoints_test.dart
```

Expected: FAIL (library / symbols not found).

- [ ] **Step 3: Implement `tp_breakpoints.dart` and export**

```dart
/// Tailwind-aligned viewport width tokens and predicates.
///
/// Mobile first (`up`): `width >= token` — like `@media (min-width: …)`.
/// Desktop first (`down`): `width < token` — like `<sm` / `max-sm`.
/// Only (`only`): half-open band `[token, next)`; `xxl` is `width >= 1536`.
enum TpBreakpoint { sm, md, lg, xl, xxl }

abstract final class TpBreakpoints {
  static const double sm = 640;
  static const double md = 768;
  static const double lg = 1024;
  static const double xl = 1280;
  static const double xxl = 1536;

  static double of(TpBreakpoint breakpoint) => switch (breakpoint) {
        TpBreakpoint.sm => sm,
        TpBreakpoint.md => md,
        TpBreakpoint.lg => lg,
        TpBreakpoint.xl => xl,
        TpBreakpoint.xxl => xxl,
      };

  static bool up(double width, TpBreakpoint breakpoint) =>
      width >= of(breakpoint);

  static bool down(double width, TpBreakpoint breakpoint) =>
      width < of(breakpoint);

  static bool only(double width, TpBreakpoint breakpoint) {
    final start = of(breakpoint);
    if (breakpoint == TpBreakpoint.xxl) return width >= start;
    final end = of(TpBreakpoint.values[breakpoint.index + 1]);
    return width >= start && width < end;
  }
}
```

Export in `shared_ui.dart`:

```dart
export 'src/theme/tokens/tp_breakpoints.dart';
```

README — add under Theme / new **Breakpoints** section noting shell hosts may still pass product-specific widths (e.g. TeamPilot 840) and should not replace those with `TpBreakpoints.md` blindly.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client/packages/shared_ui && dart test test/theme/tp_breakpoints_test.dart
```

Expected: PASS.

---

### Task 2: Stack `OnboardingCliRow` below `sm`

**Files:**
- Modify: `client/lib/pages/onboarding/steps/onboarding_cli_row.dart`
- Create: `client/test/pages/onboarding/onboarding_cli_row_test.dart`

**Interfaces:**
- Consumes: `TpBreakpoints.down(width, TpBreakpoint.sm)` from Task 1
- Produces: same public `OnboardingCliRow` API; narrow vs wide layout only

- [ ] **Step 1: Write the failing widget test**

Pump a single `OnboardingCliRow` inside `TpTheme` + `MaterialApp` with fixed viewport. Use a fake `CliToolDefinition` from `CliToolRegistry.builtIn()` (e.g. flashskyai or claude). Assert:

- At width `390`: `TextField` top is below brand icon top (stacked) — compare `tester.getTopLeft` of icon key vs field key.
- At width `800`: field top ≈ icon top (same row; allow small delta for alignment).

Keys already exist via `AppKeys.cliExecutablePathFieldFor(cli)` and `ValueKey('onboarding-cli-icon-${cli.value}')`.

Sketch:

```dart
testWidgets('stacks path field below header when width < sm', (tester) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  // pump OnboardingCliRow …
  final iconTop = tester.getTopLeft(find.byKey(ValueKey('onboarding-cli-icon-…'))).dy;
  final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;
  expect(fieldTop, greaterThan(iconTop + 8));
});

testWidgets('keeps single row when width >= sm', (tester) async {
  tester.view.physicalSize = const Size(800, 800);
  // …
  expect((fieldTop - iconTop).abs(), lessThan(20));
});
```

- [ ] **Step 2: Run test to verify narrow assertion fails on current single-row layout**

```bash
cd client && flutter test test/pages/onboarding/onboarding_cli_row_test.dart
```

Expected: narrow test FAIL (field roughly same row as icon).

- [ ] **Step 3: Implement dual layout in `onboarding_cli_row.dart`**

Wrap content in `LayoutBuilder`. If `TpBreakpoints.down(constraints.maxWidth, TpBreakpoint.sm)`:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Row(children: [icon, SizedBox(10), Expanded(child: label), SizedBox(8), statusIcon]),
    SizedBox(height: 8),
    Row(children: [
      Expanded(child: pathField),
      if (supportsInstall) ...[SizedBox(4), installButton],
    ]),
  ],
)
```

Else keep existing single `Row`. Extract shared widgets (icon, label, status, field, install) as local builders to avoid duplication.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/pages/onboarding/onboarding_cli_row_test.dart
cd client/packages/shared_ui && dart test test/theme/tp_breakpoints_test.dart
```

Expected: PASS.

- [ ] **Step 5: Analyze touched packages**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/onboarding/steps/onboarding_cli_row.dart \
  test/pages/onboarding/onboarding_cli_row_test.dart
cd client/packages/shared_ui && dart analyze lib/src/theme/tokens/tp_breakpoints.dart
```

Expected: no errors.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `TpBreakpoints` tokens + up/down/only | Task 1 |
| README note + export | Task 1 |
| Shell 840 unchanged | Global constraint (no task mutates it) |
| CLI row dual layout below sm | Task 2 |
| Widget tests narrow/wide | Task 2 |
| No settings-row / migration | Global constraint |
