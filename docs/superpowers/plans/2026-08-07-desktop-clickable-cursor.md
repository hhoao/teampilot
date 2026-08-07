# Desktop Clickable Cursor + Unified Pressable Primitive — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every clickable control in TeamPilot shows a hand pointer on hover on desktop (arrow when disabled), via one platform-adaptive pressable primitive (`TpHover`) and a theme-level hand cursor for Material button families.

**Architecture:** Upgrade `TpHover` (shared_ui) into the single pressable entry point: on desktop (Linux/macOS/Windows/web) it stays `GestureDetector` + animated hover/active color + hand cursor; on touch (Android/iOS) it renders `Material`+`InkWell` ripple. Migrate all 44 remaining `InkWell` call sites to `TpHover`. Give Material buttons (`FilledButton`/`OutlinedButton`/`ElevatedButton`/`TextButton`/`IconButton`/`Checkbox`) a hand cursor via the app theme.

**Tech Stack:** Flutter 3.44 (Material 3), `shared_ui` design system, `flex_color_scheme` theme, `flutter_test`.

## Global Constraints

- Platform rule: `TpHover` touch branch = `!kIsWeb && (defaultTargetPlatform == android || defaultTargetPlatform == iOS)`; everything else (web/desktop) = desktop branch.
- Cursor rule everywhere: enabled/interactive → `SystemMouseCursors.click`; disabled/non-interactive → `SystemMouseCursors.basic`.
- Disabled buttons must NOT show a hand cursor.
- Keep every migrated site's existing size, color, border, tooltip, `Semantics`, keys, and disabled logic identical. Children of migrated `InkWell`s are unchanged unless the step says otherwise.
- Text fields keep I-beam; drag/resize handles are out of scope (none of the 44 sites are drag handles).
- Do not touch l10n. No new dependencies.
- Full gate before each commit: `flutter analyze --no-fatal-infos --no-fatal-warnings` (from `client/`) and the task's tests.
- `shared_ui` is a git submodule at `client/packages/shared_ui`; changes there are committed in the submodule repo first, then the parent bumps the pointer (`git add client/packages/shared_ui`).

Spec: `docs/superpowers/specs/2026-08-07-desktop-clickable-cursor-design.md`.

---

### Task 1: `TpHover` adaptive pressable primitive (shared_ui)

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart` (whole file)
- Create: `client/packages/shared_ui/test/flutter_test_config.dart`
- Modify: `client/packages/shared_ui/test/components/hover/tp_hover_test.dart`
- Test: `client/packages/shared_ui/test/components/hover/tp_hover_test.dart`

**Interfaces:**
- Produces: `enum TpPressableShape { rounded, stadium, circle }` (exported via `shared_ui` barrel — check `shared_ui/lib/shared_ui.dart` / the hover export and add if missing).
- `TpHover` gains: `shape` (`TpPressableShape.rounded` default), `onTapDown`/`onTapUp`/`onTapCancel` (`GestureTapDownCallback?` / `GestureTapUpCallback?` / `GestureTapCancelCallback?`), `canRequestFocus` (`bool`, default `true`), `splashColor` (`Color?`, touch path only). All other params unchanged.

- [ ] **Step 1: Add the shared_ui test platform config**

Create `client/packages/shared_ui/test/flutter_test_config.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// shared_ui is a desktop-first design system. Run widget tests on a desktop
/// platform so [TpHover] renders its desktop (GestureDetector + hover + cursor)
/// path by default. Touch-specific tests override inline with
/// `debugDefaultTargetPlatformOverride = TargetPlatform.android`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await testMain();
}
```

- [ ] **Step 2: Add failing tests for the new adaptive behavior**

Append these tests to `client/packages/shared_ui/test/components/hover/tp_hover_test.dart` (inside `main()`; the file's existing `wrap` helper stays as-is — it now runs under the linux override from Step 1):

```dart
  group('adaptive touch path', () {
    testWidgets('renders InkWell (ripple) on touch platforms', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        wrap(TpHover(onTap: () {}, child: const Text('t'))),
      );
      expect(find.byType(InkWell), findsOneWidget);
      // No animated hover fill on touch.
      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('desktop path keeps GestureDetector fill, no InkWell', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(TpHover(onTap: () {}, child: const Text('t'))),
      );
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(AnimatedContainer), findsOneWidget);
    });
  });

  group('shape', () {
    testWidgets('circle derives circular radius for desktop fill', (tester) async {
      await tester.pumpWidget(
        wrap(
          TpHover(
            shape: TpPressableShape.circle,
            width: 36,
            height: 36,
            onTap: () {},
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(18));
    });

    testWidgets('touch path circle uses CircleBorder', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        wrap(
          TpHover(
            shape: TpPressableShape.circle,
            width: 36,
            height: 36,
            onTap: () {},
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(TpHover),
          matching: find.byType(Material),
        ),
      );
      expect(material.shape, isA<CircleBorder>());
    });

    testWidgets('stadium touch path uses StadiumBorder', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        wrap(TpHover(shape: TpPressableShape.stadium, onTap: () {}, child: const Text('x'))),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(TpHover),
          matching: find.byType(Material),
        ),
      );
      expect(material.shape, isA<StadiumBorder>());
    });
  });

  group('tap passthrough', () {
    testWidgets('onTapDown and onTapUp deliver details', (tester) async {
      TapDownDetails? down;
      TapUpDetails? up;
      var cancelled = false;
      await tester.pumpWidget(
        wrap(
          TpHover(
            onTapDown: (d) => down = d,
            onTapUp: (d) => up = d,
            onTapCancel: () => cancelled = true,
            onTap: () {},
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await tester.tap(find.byType(TpHover));
      expect(down, isNotNull);
      expect(up, isNotNull);
      expect(cancelled, isFalse);
    });
  });

  testWidgets('canRequestFocus=false keeps focus out of the tap surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TpHover(
          canRequestFocus: false,
          onTap: () {},
          child: const Text('x'),
        ),
      ),
    );
    await tester.tap(find.byType(TpHover));
    expect(tester.binding.focusManager.primaryFocus, isNull);
  });
```

Run and verify they FAIL (they reference `TpPressableShape`, `shape`, `onTapDown`, `canRequestFocus` which do not exist yet, and the touch-path assertions fail because the current build has no touch branch):

```
cd client/packages/shared_ui && flutter test test/components/hover/tp_hover_test.dart
```
Expected: FAIL — compilation errors (`TpPressableShape` undefined) / failing new assertions.

- [ ] **Step 3: Rewrite `tp_hover.dart` as the adaptive primitive**

Replace the entire contents of `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shape of the [TpHover] pressable surface.
///
/// On desktop this drives the [BorderRadius] of the animated fill; on touch it
/// drives the [ShapeBorder] of the [Material] that hosts the [InkWell] ripple.
enum TpPressableShape { rounded, stadium, circle }

/// Platform-adaptive pressable surface — the single tap/hover primitive.
///
/// Desktop (Linux / macOS / Windows / web): `GestureDetector` + animated
/// hover/active fill (alpha-only fade) + hand cursor when interactive (arrow
/// when disabled), with keyboard `Focus` and `Semantics`.
///
/// Touch (Android / iOS): `Material` + `InkWell` ripple (no hover paint).
///
/// Prefer this over a bare [GestureDetector] or [InkWell] for tappable UI.
class TpHover extends StatefulWidget {
  const TpHover({
    super.key,
    required this.child,
    this.hoverColor,
    this.backgroundColor,
    this.border,
    this.onTap,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.duration = const Duration(milliseconds: 120),
    this.cursor,
    this.forceHover = false,
    this.onHoverChanged,
    this.width,
    this.height,
    this.enabled = true,
    this.pressScale = 1.0,
    this.shape = TpPressableShape.rounded,
    this.canRequestFocus = true,
    this.splashColor,
  });

  final Widget child;
  final Color? hoverColor;

  /// Idle fill behind [child]. Transparent when null.
  final Color? backgroundColor;

  /// Drawn on the same decoration as [backgroundColor] / hover fill so the
  /// stroke sits on the outer edge (not inside [padding]).
  final BoxBorder? border;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  /// Fired on pointer down (menu rows that select immediately). When unset and
  /// [pressScale] != 1.0, a press-scale bookkeeping callback is installed.
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Duration duration;
  final MouseCursor? cursor;

  /// Keeps the hover fill visible (e.g. while an anchored menu is open).
  final bool forceHover;
  final ValueChanged<bool>? onHoverChanged;
  final double? width;
  final double? height;
  final bool enabled;

  /// Scale applied while the pointer is down. `1.0` disables press feedback.
  final double pressScale;
  final TpPressableShape shape;

  /// Desktop path: whether the tap surface can take keyboard focus. Mirror of
  /// [InkWell.canRequestFocus] for call sites that must keep focus elsewhere.
  final bool canRequestFocus;

  /// Touch path: the [InkWell] splash color (defaults to theme splash).
  final Color? splashColor;

  /// Default sidebar row hover tint.
  static Color defaultHoverColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
  }

  @override
  State<TpHover> createState() => _TpHoverState();
}

class _TpHoverState extends State<TpHover> {
  var _hovered = false;
  var _pressed = false;

  static bool get _isTouchPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _interactive =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onSecondaryTap != null ||
          widget.onSecondaryTapDown != null ||
          widget.onLongPress != null ||
          widget.onTapDown != null);

  bool get _showHover => widget.enabled && (_hovered || widget.forceHover);

  /// Fully transparent idle must share [hoverFill]'s RGB so [Color.lerp]
  /// fades opacity instead of interpolating from black.
  static Color _animationIdleColor(Color idleColor, Color hoverFill) {
    if (idleColor.a == 0) {
      return hoverFill.withValues(alpha: 0);
    }
    return idleColor;
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  BorderRadius get _desktopRadius {
    return switch (widget.shape) {
      TpPressableShape.rounded => widget.borderRadius,
      TpPressableShape.stadium =>
        BorderRadius.circular((widget.height ?? 999) / 2),
      TpPressableShape.circle =>
        BorderRadius.circular(((widget.width ?? widget.height) ?? 0) / 2),
    };
  }

  ShapeBorder get _touchShape {
    final side = widget.border?.top ?? BorderSide.none;
    return switch (widget.shape) {
      TpPressableShape.rounded =>
        RoundedRectangleBorder(borderRadius: widget.borderRadius, side: side),
      TpPressableShape.stadium => StadiumBorder(side: side),
      TpPressableShape.circle => CircleBorder(side: side),
    };
  }

  GestureTapDownCallback? get _onTapDown {
    final custom = widget.onTapDown;
    if (custom != null) return custom;
    if (widget.pressScale != 1.0) {
      return (_) => setState(() => _pressed = true);
    }
    return null;
  }

  GestureTapUpCallback? get _onTapUp {
    final custom = widget.onTapUp;
    if (custom != null) return custom;
    if (widget.pressScale != 1.0) {
      return (_) => setState(() => _pressed = false);
    }
    return null;
  }

  GestureTapCancelCallback? get _onTapCancel {
    final custom = widget.onTapCancel;
    if (custom != null) return custom;
    if (widget.pressScale != 1.0) {
      return () => setState(() => _pressed = false);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isTouchPlatform) return _buildTouch(context);
    return _buildDesktop(context);
  }

  Widget _buildDesktop(BuildContext context) {
    final hoverFill = widget.hoverColor ?? TpHover.defaultHoverColor(context);
    final idleColor = _animationIdleColor(
      widget.backgroundColor ?? Colors.transparent,
      hoverFill,
    );
    final Color fill = _showHover ? hoverFill : idleColor;
    final cursor =
        widget.cursor ??
        (_interactive ? SystemMouseCursors.click : SystemMouseCursors.basic);

    Widget content = Container(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          // Fill + border behind the child. Keyed by RGB (alpha masked off) so
          // a fill color-family change replaces this layer instantly instead of
          // Color.lerp-ing through muddy intermediates.
          Positioned.fill(
            child: AnimatedContainer(
              key: ValueKey<int>(fill.toARGB32() & 0x00FFFFFF),
              duration: widget.duration,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: _desktopRadius,
                border: widget.border,
              ),
            ),
          ),
          Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ],
      ),
    );

    if (widget.pressScale != 1.0) {
      content = AnimatedScale(
        scale: _pressed && _interactive ? widget.pressScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: content,
      );
    }

    if (_interactive) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onSecondaryTap: widget.onSecondaryTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        onLongPress: widget.onLongPress,
        child: content,
      );
    }

    content = Semantics(
      button: _interactive,
      enabled: widget.enabled,
      onTap: widget.onTap != null
          ? () => widget.onTap!()
          : null,
      child: content,
    );

    return Focus(
      canRequestFocus: _interactive && widget.canRequestFocus,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) _setHovered(true);
        },
        onExit: (_) {
          _setHovered(false);
          if (_pressed) setState(() => _pressed = false);
        },
        cursor: cursor,
        child: content,
      ),
    );
  }

  Widget _buildTouch(BuildContext context) {
    final shape = _touchShape;
    final fill = widget.backgroundColor ?? Colors.transparent;

    Widget content = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Material(
        color: fill,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onSecondaryTap: widget.onSecondaryTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onLongPress: widget.onLongPress,
          customBorder: shape,
          canRequestFocus: widget.canRequestFocus,
          splashColor: widget.splashColor,
          hoverColor: Colors.transparent,
          child: Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.pressScale != 1.0) {
      content = AnimatedScale(
        scale: _pressed && _interactive ? widget.pressScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: content,
      );
    }

    return MouseRegion(
      cursor:
          widget.cursor ??
          (_interactive ? SystemMouseCursors.click : SystemMouseCursors.basic),
      child: content,
    );
  }
}
```

- [ ] **Step 4: Verify the adaptive behavior**

Run the shared_ui hover tests:

```
cd client/packages/shared_ui && flutter test test/components/hover/
```
Expected: PASS — all existing tests (desktop path under the linux override) plus the new adaptive/shape/tap tests.

Run the full shared_ui suite to catch regressions in dependents (`TpHoverRow`, `TpTabChip`, date picker):

```
cd client/packages/shared_ui && flutter test
```
Expected: PASS.

- [ ] **Step 5: Commit the primitive in the submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/hover/tp_hover.dart test/flutter_test_config.dart test/components/hover/tp_hover_test.dart
git commit -m "feat(hover): make TpHover a platform-adaptive pressable primitive

Desktop: GestureDetector + hover/active color fade + hand cursor + Focus/Semantics.
Touch: Material + InkWell ripple. Adds shape (rounded/stadium/circle),
onTapDown/onTapUp/onTapCancel passthrough, canRequestFocus, splashColor.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Theme-level hand cursor for Material buttons

**Files:**
- Modify: `client/lib/theme/app_button_theme.dart`
- Modify: `client/lib/theme/app_theme.dart`
- Test: `client/test/theme/clickable_cursor_test.dart` (create)

**Interfaces:**
- Produces: `final WidgetStateProperty<MouseCursor> kTpClickableMouseCursor` exported from `app_button_theme.dart` (resolves `click` when not disabled, `basic` when disabled).

- [ ] **Step 1: Write the failing test**

Create `client/test/theme/clickable_cursor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';

void main() {
  group('Material button themes resolve hand cursor on desktop', () {
    for (final (name, builder) in <(String, ThemeData Function())>[
      ('light', buildLightTheme),
      ('dark', buildDarkTheme),
    ]) {
      test('$name: filled/outlined/elevated/text/icon buttons -> click', () {
        final theme = builder();
        for (final cursor in <MouseCursor?>[
          theme.filledButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.outlinedButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.elevatedButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.textButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.iconButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
        ]) {
          expect(cursor, SystemMouseCursors.click, reason: name);
        }
      });

      test('$name: disabled buttons -> basic arrow', () {
        final theme = builder();
        for (final cursor in <MouseCursor?>[
          theme.filledButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.outlinedButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.elevatedButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.textButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.iconButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
        ]) {
          expect(cursor, SystemMouseCursors.basic, reason: name);
        }
      });
    }
  });
}
```

Run and verify it FAILS (iconButtonTheme is unset and the button themes resolve to the Material default arrow on desktop):

```
cd client && flutter test test/theme/clickable_cursor_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Add the cursor to the button themes**

In `client/lib/theme/app_button_theme.dart`, add at top level (after `kFilledButtonForeground`):

```dart
/// Hand cursor for interactive controls; arrow when disabled.
///
/// Material's default `WidgetStateMouseCursor.adaptiveClickable` resolves to an
/// arrow on non-web desktop, so we opt every button family into a hand pointer.
final WidgetStateProperty<MouseCursor> kTpClickableMouseCursor =
    WidgetStateProperty.resolveWith((states) {
  if (states.contains(WidgetState.disabled)) {
    return SystemMouseCursors.basic;
  }
  return SystemMouseCursors.click;
});
```

In `_buttonGeometry` (`app_button_theme.dart`), add `mouseCursor` to the returned `ButtonStyle`:

```dart
ButtonStyle _buttonGeometry({
  required TpControlSizeMetrics metrics,
  required double radius,
}) {
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(metrics.minWidth, metrics.height),
    ),
    maximumSize: WidgetStatePropertyAll(
      Size(double.infinity, metrics.height),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    mouseCursor: kTpClickableMouseCursor,
  );
}
```

- [ ] **Step 3: Add iconButtonTheme + checkboxTheme**

In `client/lib/theme/app_theme.dart`, `_applyTypography` already builds `buttons` and sets `filledButtonTheme`/`outlinedButtonTheme`/`elevatedButtonTheme`/`textButtonTheme`. Add `iconButtonTheme` and `checkboxTheme` to **both** return statements (the `!useRuntimeGoogleFonts` branch at ~line 302 and the runtime branch at ~line 365). After `textButtonTheme: buttons.text,` add:

```dart
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: kTpClickableMouseCursor),
      ),
      checkboxTheme: CheckboxThemeData(
        mouseCursor: kTpClickableMouseCursor,
      ),
```

Add `import 'app_button_theme.dart';` — already imported (`app_button_theme.dart` is imported at the top of `app_theme.dart`).

- [ ] **Step 4: Verify**

```
cd client && flutter test test/theme/clickable_cursor_test.dart
```
Expected: PASS.

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/theme/app_button_theme.dart lib/theme/app_theme.dart test/theme/clickable_cursor_test.dart
git commit -m "feat(theme): hand cursor for Material button families on desktop

Filled/Outlined/Elevated/Text/IconButton and Checkbox now resolve to a hand
cursor when enabled (arrow when disabled) instead of Material's
adaptiveClickable default, which is an arrow on non-web desktop.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Migration patterns + compose card + voice bar (7 sites)

This task establishes the migration patterns (used verbatim by later tasks) and migrates the chat compose toolbar — the user-reported area.

**Files:**
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing_voice_bar.dart`
- Test: run `client/test/widgets/compose/` and `client/test/pages/home_workspace/` suites after the change

**Migration patterns (DRY reference for later tasks):**

- **Pattern R** — rounded-rect surface:
  `Material(color: C, borderRadius: R, [clipBehavior: Clip.antiAlias,] child: InkWell(borderRadius: R, onTap: T, child: X))` →
  `TpHover(backgroundColor: C, borderRadius: R, onTap: T, child: X)` (child `X` unchanged; the antiAlias clip is dropped because `TpHover`'s fill is self-clipped and these children fit their box).
- **Pattern S** — stadium chip:
  `Material(color: C, shape: StadiumBorder(side: BorderSide(color: B)), clipBehavior: Clip.antiAlias, child: InkWell(onTap: T, child: X))` →
  `TpHover(backgroundColor: C, shape: TpPressableShape.stadium, border: Border.all(color: B), onTap: T, child: X)`.
- **Pattern C** — circle button:
  `Material(color: C, shape: CircleBorder(), [side…], clipBehavior: Clip.antiAlias, child: InkWell(customBorder: CircleBorder(), onTap: T, child: SizedBox(width: W, height: H, child: Center(child: I))))` →
  `TpHover(shape: TpPressableShape.circle, width: W, height: H, backgroundColor: C, [border: Border.all(color: B),] onTap: T, child: Center(child: I))`.
- **Pattern M** — bare InkWell (no Material): `InkWell(onTap: T, [borderRadius: R,] child: X)` → `TpHover(onTap: T, [borderRadius: R,] child: X)`.
- **Pattern W** — no-feedback surface: `InkWell(hoverColor: Colors.transparent, splashColor: Colors.transparent, highlightColor: Colors.transparent, onTap: T, child: X)` → `TpHover(hoverColor: Colors.transparent, onTap: T, child: X)`.

- [ ] **Step 1: Migrate `_TeamSettingsButton` (circle, chipFill)**

In `workspace_compose_card.dart`, replace the `Material(... InkWell(...))` inside `_TeamSettingsButton.build` (lines ~637-670):

```dart
    return Tooltip(
      message: tooltip,
      child: TpHover(
        shape: TpPressableShape.circle,
        width: _size,
        height: _size,
        backgroundColor: palette.chipFill,
        border: Border.all(color: palette.border),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.settings_outlined, size: icons.md, color: color),
              if (showAttention)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.chipFill, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
```

The `Stack` child's `Positioned` requires the `Stack` to have a bounded parent — the `Center` inside `TpHover` provides it (as the original `SizedBox` did). Keep the `color` computation (`enabled ? palette.muted : palette.disabled`) unchanged.

- [ ] **Step 2: Migrate `_StopButton` (filled circle)**

Replace the `Semantics > Material > InkWell` block in `_StopButton.build` (lines ~693-717) with:

```dart
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: TpHover(
          shape: TpPressableShape.circle,
          width: _size,
          height: _size,
          backgroundColor: palette.sendActive,
          onTap: throttledOnPressed('session_review_compose_stop', onStop),
          child: Center(
            child: Icon(
              Icons.stop_rounded,
              color: palette.sendIcon,
              size: icons.md,
            ),
          ),
        ),
      ),
    );
```

- [ ] **Step 3: Migrate `_VoicePrimaryButton` (circle, disabled-aware)**

Replace the `Semantics > Material > InkWell` block in `_VoicePrimaryButton.build` (lines ~743-768) with:

```dart
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: TpHover(
          shape: TpPressableShape.circle,
          width: _size,
          height: _size,
          backgroundColor: palette.sendIdle,
          enabled: enabled,
          onTap: enabled ? onTap : null,
          child: Center(
            child: Icon(
              Icons.mic_none_outlined,
              color: color,
              size: icons.md,
            ),
          ),
        ),
      ),
    );
```

- [ ] **Step 4: Migrate `_SendButton` (circle, active/inactive)**

Replace the `Material > InkWell` block in `_SendButton.build` (lines ~796-828) with:

```dart
    final button = TpHover(
      shape: TpPressableShape.circle,
      width: _size,
      height: _size,
      backgroundColor: active ? palette.sendActive : palette.sendIdle,
      enabled: active,
      onTap: active ? throttledOnPressed(throttleKey, onSubmit) : null,
      child: Center(
        child: isSubmitting
            ? SizedBox(
                width: icons.sm,
                height: icons.sm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.sendIcon,
                ),
              )
            : Icon(
                Icons.arrow_upward_rounded,
                color: active ? palette.sendIcon : palette.disabled,
                size: icons.md,
              ),
      ),
    );
```

Note: the old code installed a no-op `onTap: () {}` when blocked-with-tooltip (so the hand cursor showed); with `enabled: active` the blocked state now correctly shows an arrow while the `Tooltip` still appears on hover. Keep the trailing `if (tooltip == null || tooltip.isEmpty || active) return button; return Tooltip(message: tooltip, child: button);` lines unchanged.

- [ ] **Step 5: Migrate `_ComposeActionIcon` (transparent circle)**

Replace the `Material > InkWell` block in `_ComposeActionIcon.build` (lines ~863-888) with:

```dart
    return Tooltip(
      message: tooltip,
      child: TpHover(
        shape: TpPressableShape.circle,
        width: _size,
        height: _size,
        backgroundColor: Colors.transparent,
        enabled: interactive,
        onTap: interactive ? onTap : null,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: icons.sm,
                  height: icons.sm,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.muted,
                  ),
                )
              : Icon(icon, size: icons.md, color: color),
        ),
      ),
    );
```

- [ ] **Step 6: Migrate the two voice-bar buttons**

In `workspace_chat_landing_voice_bar.dart`:
- First site (lines ~178-194, transparent circle with icon): replace `Tooltip > Material(transparent, CircleBorder) > InkWell(customBorder: CircleBorder, onTap: onTap, child: SizedBox(W,H, Icon))` with:

```dart
    return Tooltip(
      message: tooltip,
      child: TpHover(
        shape: TpPressableShape.circle,
        width: _size,
        height: _size,
        backgroundColor: Colors.transparent,
        onTap: onTap,
        child: Center(child: Icon(icon, size: icons.md, color: palette.muted)),
      ),
    );
```
- Second site (lines ~217-233, chipFill rounded-rect with inner circle indicator): replace `Material(chipFill, RoundedRectangleBorder(10, side border), clip) > InkWell(borderRadius: 10, onTap: onTap, child: SizedBox(_outer,_outer, Center(inner circle)))` with Pattern R + `Center`, preserving the inner `Container` exactly:

```dart
        child: TpHover(
          backgroundColor: palette.chipFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
          onTap: onTap,
          child: SizedBox(
            width: _outer,
            height: _outer,
            child: Center(
              child: Container(
                width: _inner,
                height: _inner,
                decoration: BoxDecoration(
                  // … existing inner circle decoration unchanged …
                ),
              ),
            ),
          ),
        ),
```

(The second site keeps its `Tooltip` wrapper and any outer padding as-is; only the `Material`/`InkWell` pair is replaced.)

- [ ] **Step 7: Verify**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: no errors.

Run the compose + landing widget tests:

```
cd client && flutter test test/widgets/compose test/pages/home_workspace --exclude-tags integration
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/compose/workspace_compose_card.dart lib/pages/home_workspace/workspace/workspace_chat_landing_voice_bar.dart
git commit -m "refactor(compose): migrate compose toolbar buttons from InkWell to TpHover

Send/attach/enhance/voice/stop/team-settings and the voice-bar buttons now use
the adaptive TpHover primitive: desktop hover color + hand cursor, touch
ripple. Blocked send now shows an arrow instead of a misleading hand.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Compose chips + trigger field (3 sites)

**Files:**
- Modify: `client/lib/widgets/compose/compose_menu_chip.dart`
- Modify: `client/lib/widgets/compose/compose_at_file_chip_row.dart`
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart`
- Test: `cd client && flutter test test/widgets/compose` (run after change)

- [ ] **Step 1: Migrate `ComposeToolbarChip`**

In `compose_menu_chip.dart`, replace the `Material(chipFill, StadiumBorder(border), clip) > InkWell(onTap: onTap, child: ConstrainedBox(minHeight:36, …))` (lines ~81-110) with Pattern S:

```dart
    return TpHover(
      backgroundColor: palette.chipFill,
      shape: TpPressableShape.stadium,
      border: Border.all(color: palette.border),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading ?? Icon(icon, size: icons.sm, color: palette.muted),
              SizedBox(width: spacing.xs),
              Text(label, style: labelStyle),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: icons.md,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
```

- [ ] **Step 2: Migrate `compose_at_file_chip_row.dart`**

Replace `Material(chipFill, StadiumBorder(border), clip) > InkWell(onTap: onTap, child: ConstrainedBox(minHeight, …))` (lines ~69-90) with Pattern S, keeping the existing chip child (icon, text, close icon) unchanged:

```dart
    return TpHover(
      backgroundColor: palette.chipFill,
      shape: TpPressableShape.stadium,
      border: Border.all(color: palette.border),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ComposeToolbarChip.minHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: /* … existing Row unchanged … */,
        ),
      ),
    );
```

- [ ] **Step 3: Migrate the trigger suggestion row**

In `compose_trigger_field.dart` (lines ~518-560), replace `Material(color: selected ? primary 0.08 : transparent, child: InkWell(onTapDown:…, onTap:…, onHover:…, child: Padding(…Row…)))` with:

```dart
      children.add(
        TpHover(
          backgroundColor: selected
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          onTapDown: (_) => onSelected(suggestion),
          onTap: () => onSelected(suggestion),
          onHoverChanged: (_) => onHover(index),
          child: Padding(
            // … existing Padding/Row unchanged …
          ),
        ),
      );
```

(`onHover(index)` ignores the bool, matching the original `onHover: (_) => onHover(index)`.)

- [ ] **Step 4: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/widgets/compose --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/widgets/compose/compose_menu_chip.dart lib/widgets/compose/compose_at_file_chip_row.dart lib/widgets/compose/compose_trigger_field.dart
git commit -m "refactor(compose): migrate chips + trigger rows from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Chat pages (5 sites)

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_cli_task_panel.dart`
- Modify: `client/lib/pages/chat/ask_user_question_card.dart`
- Test: `cd client && flutter test test/pages/chat test/widgets/ai test/cubits --exclude-tags integration` (run after change)

- [ ] **Step 1: `session_history_thread.dart` (stadium "stick to tip" button)**

Replace `InkWell(customBorder: StadiumBorder(), onTap: _resumeStickToTip, child: Padding(…Row…))` (line ~412) with Pattern S (transparent background, default hover):

```dart
            child: TpHover(
              shape: TpPressableShape.stadium,
              onTap: _resumeStickToTip,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  // … existing Row unchanged …
                ),
              ),
            ),
```

- [ ] **Step 2: `session_cli_task_panel.dart` — pill with elevation**

The collapsed pill uses `Material(color: surface, elevation: 3, shadowColor, borderRadius: 999, child: InkWell(borderRadius: 999, onTap:…))` (lines ~73-96). Keep the `Material` for the elevation/shadow/color shell and swap the `InkWell` for `TpHover` (transparent fill so the pill color shows through):

```dart
    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(999),
      child: TpHover(
        shape: TpPressableShape.stadium,
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() {
          _expanded = true;
          _showAll = false;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            // … existing Row unchanged …
          ),
        ),
      ),
    );
```

- [ ] **Step 3: `session_cli_task_panel.dart` — collapse icon + "more" row**

- Collapse icon (lines ~154-172): replace `InkWell(onTap: collapse, borderRadius: 6, child: Padding(all 4, Icon(close_fullscreen)))` with Pattern M:

```dart
                  TpHover(
                    onTap: () => setState(() {
                      _expanded = false;
                      _showAll = false;
                    }),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_fullscreen_rounded,
                        size: 16,
                        // … existing Icon color/param unchanged …
                      ),
                    ),
                  ),
```
- "more" row (lines ~190-205): replace `InkWell(onTap: toggle showAll, borderRadius: 4, child: Padding(vertical 2, Row(Text)))` with Pattern M (borderRadius 4).

- [ ] **Step 4: `ask_user_question_card.dart` (special: preserve focus + no-splash)**

Replace the `Material(color: bg ?? transparent, borderRadius: radius, child: InkWell(canRequestFocus: false, onTap: enabled?…, mouseCursor:…, splashFactory: NoSplash, splashColor: transparent, highlightColor: transparent, hoverColor: primary 0.08, child: …))` block (lines ~939-955) with:

```dart
    return TpHover(
      backgroundColor: bg ?? Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      canRequestFocus: false,
      splashColor: Colors.transparent,
      hoverColor: cs.primary.withValues(alpha: 0.08),
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: /* … existing child unchanged … */,
    );
```

`TpHover` supplies the hand cursor when `enabled` and the arrow when disabled, so the removed `mouseCursor`/`splashFactory`/`splashColor`/`highlightColor` lines are no longer needed. (`NoSplash` comes from `package:flutter/material.dart`, which the file already imports — no import changes.)

- [ ] **Step 5: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/pages/chat --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/pages/chat/session_history_thread.dart lib/pages/chat/session_cli_task_panel.dart lib/pages/chat/ask_user_question_card.dart
git commit -m "refactor(chat): migrate chat-page tappables from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Home / team / expert / skills pages (7 sites)

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart`
- Modify: `client/lib/pages/team_hub/team_hub_body.dart`
- Modify: `client/lib/pages/team_hub/team_landing_picker_filter_bar.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_body.dart`
- Modify: `client/lib/pages/team_config/team_config_nav_panel.dart`
- Modify: `client/lib/pages/skills/skill_source_toggle.dart`
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart`
- Test: `cd client && flutter test test/pages --exclude-tags integration` (run after change)

- [ ] **Step 1: `home_workspace_title_bar.dart` home chip**

Replace `Material(color: active ? primary 0.16 : transparent, shape: RoundedRectangleBorder(8, side: active? primary 0.28 : transparent), clip) > InkWell(onTap: onTap, child: Padding(…))` (lines ~588-622) with Pattern R:

```dart
    return TpHover(
      backgroundColor: active ? cs.primary.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: active ? cs.primary.withValues(alpha: 0.28) : Colors.transparent,
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: kHomeTitleBarChipVerticalPadding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_filled, size: context.tpIconSizes.md, color: fg),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: styles.smColored(fg)),
            ],
          ],
        ),
      ),
    );
```

- [ ] **Step 2: stadium filter chips (`team_hub_body`, `team_landing_picker_filter_bar`, `expert_hub_body`)**

All three share the identical stadium-chip structure (`Material(color: selected ? cs.surfaceContainer : transparent, shape: StadiumBorder(side: BorderSide(color: border)), clip) > InkWell(onTap: onTap, child: Padding(horizontal 14, Row(icon?, label, count?)))`). In each file, replace with Pattern S:

```dart
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TpHover(
        backgroundColor: selected ? cs.surfaceContainer : Colors.transparent,
        shape: TpPressableShape.stadium,
        border: Border.all(color: border),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: fg != null ? styles.mdColored(fg) : styles.md),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(count, style: styles.smColored(fg)),
              ],
            ],
          ),
        ),
      ),
    );
```

Match each file's actual trailing count/row content (`team_hub_body.dart` and `expert_hub_body.dart` have a trailing `count`; `team_landing_picker_filter_bar.dart` has a chevron or count — preserve whichever exists).

- [ ] **Step 3: `team_config_nav_panel.dart` add-section row**

Replace `Material(transparent, borderRadius: 10) > InkWell(borderRadius: 10, onTap: onTap, child: DottedBorderContainer(…))` (lines ~85-91) with Pattern R (borderRadius 10), keeping the `DottedBorderContainer` child and the outer `Padding(top: 2, bottom: 6)` unchanged.

- [ ] **Step 4: `skill_source_toggle.dart`**

Replace `Material(color: selected ? primaryContainer : transparent, borderRadius: 8) > InkWell(borderRadius: 8, onTap: onTap, child: Container(padding, decoration(borderRadius, border), child: Text(label)))` (lines ~20-34) with Pattern R:

```dart
    return TpHover(
      backgroundColor: selected ? cs.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primaryContainer : cs.outlineVariant,
          ),
        ),
        child: Text(label),
      ),
    );
```

- [ ] **Step 5: `mixed_workspace_member_placement_panel.dart`**

Replace `Material(color: selected ? primaryContainer 0.35 : transparent) > InkWell(onTap: onTap, child: Padding(12,8, Column(…)))` (lines ~393-399) with Pattern R (no borderRadius → default 8 rounded):

```dart
    return TpHover(
      backgroundColor: selected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: /* … existing Column unchanged … */,
      ),
    );
```

- [ ] **Step 6: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/pages --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/pages/home_workspace/home_workspace_title_bar.dart lib/pages/team_hub/team_hub_body.dart lib/pages/team_hub/team_landing_picker_filter_bar.dart lib/pages/expert_hub/expert_hub_body.dart lib/pages/team_config/team_config_nav_panel.dart lib/pages/skills/skill_source_toggle.dart lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart
git commit -m "refactor(pages): migrate home/team/expert/skills tappables from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: MCP / LLM / workbench pages (4 sites)

**Files:**
- Modify: `client/lib/pages/mcp/mcp_registries_section.dart`
- Modify: `client/lib/pages/mcp/mcp_form_page.dart`
- Modify: `client/lib/pages/llm_config/llm_provider_models_view.dart`
- Modify: `client/lib/pages/workbench/workbench_welcome_page.dart`
- Test: `cd client && flutter test test/pages --exclude-tags integration`

- [ ] **Step 1: `mcp_registries_section.dart`**

Replace `Material(transparent) > InkWell(onTap: onEdit, borderRadius: 10, child: Container(padding, decoration: workspaceInsetDecoration, child: Row(…)))` (lines ~373-381) with Pattern R (borderRadius 10), keeping the `workspaceInsetDecoration` Container child and outer `Padding(vertical: 6)`.

- [ ] **Step 2: `mcp_form_page.dart` metadata toggle**

Replace `InkWell(onTap: toggle, borderRadius: 8, child: Padding(vertical 8, Row(Text, Spacer, …)))` (lines ~215-220) with Pattern M (borderRadius 8).

- [ ] **Step 3: `llm_provider_models_view.dart` "+ add"**

Replace `InkWell(borderRadius: 6, onTap: () => _addModel(...), child: Padding(8,6, Text('+ add')))` (lines ~100-108) with Pattern M (borderRadius 6).

- [ ] **Step 4: `workbench_welcome_page.dart` command row**

Replace `Material(transparent) > InkWell(key: AppKeys.workbenchWelcomeCommandRow(commandId), onTap: invoke, borderRadius: 8, child: Padding(4,10, Row(…)))` (lines ~82-91) with Pattern R (borderRadius 8), **preserving the `key`** on the `TpHover`:

```dart
    return TpHover(
      key: AppKeys.workbenchWelcomeCommandRow(commandId),
      backgroundColor: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.read<CommandBus>().invoke(commandId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: /* … existing Row unchanged … */,
      ),
    );
```

- [ ] **Step 5: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/pages --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/pages/mcp/mcp_registries_section.dart lib/pages/mcp/mcp_form_page.dart lib/pages/llm_config/llm_provider_models_view.dart lib/pages/workbench/workbench_welcome_page.dart
git commit -m "refactor(pages): migrate mcp/llm/workbench tappables from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Widgets batch 1 (7 sites)

**Files:**
- Modify: `client/lib/widgets/window_chrome_controls.dart`
- Modify: `client/lib/widgets/workspace_terminal/workspace_terminal_empty_pane.dart`
- Modify: `client/lib/widgets/workspace_icon_picker_dialog.dart`
- Modify: `client/lib/widgets/workbench/markdown_view_mode_toggle.dart`
- Modify: `client/lib/widgets/workbench/file_diff_surface_toggle.dart`
- Modify: `client/lib/widgets/diff/diff_toolbar.dart`
- Modify: `client/lib/widgets/diff/diff_hunk_apply_gutter.dart`
- Test: `cd client && flutter test test/widgets --exclude-tags integration`

- [ ] **Step 1: `window_chrome_controls.dart`**

Preserve the existing per-button `hoverColor`/`splashColor`/`highlightColor` values (some are transparent, some tinted — do not change them). Replace each `Material(color: background) > InkWell(onTap: …, hoverColor: …, splashColor: …, highlightColor: …, child: Icon(…))` (e.g. line ~583-594) with:

```dart
    return Material(
      color: background,
      child: TpHover(
        hoverColor: /* existing hoverColor value */,
        onTap: () => widget.onPressed(),
        child: Icon(
          widget.icon,
          size: context.tpIconSizes.md,
          color: foreground,
        ),
      ),
    );
```

If the file already draws the hover background through the `Material`'s own color change, keep that logic and set `TpHover`'s `hoverColor` to `Colors.transparent` so there is no double tint. Read each control's current hover logic and preserve it exactly.

- [ ] **Step 2: `workspace_terminal_empty_pane.dart`**

Replace `Material(transparent) > InkWell(onTap: onNewTerminal, borderRadius: 8, child: Padding(16,12, Row(icon, text)))` (lines ~26-38) with Pattern R (borderRadius 8).

- [ ] **Step 3: `workspace_icon_picker_dialog.dart`**

Replace `InkWell(borderRadius: 12, onTap: select, child: AnimatedContainer(…))` (lines ~123-128) with Pattern M (borderRadius 12), keeping the `AnimatedContainer` child unchanged (its own selected-fill logic stays).

- [ ] **Step 4: the three icon toggles (`markdown_view_mode_toggle`, `file_diff_surface_toggle`, `diff_toolbar`)**

These share the same shape (`Tooltip > Material(color: selected ? onSurface 0.12 : transparent) > InkWell(onTap, hoverColor: color 0.12, splashColor: color 0.2, child: SizedBox(30 × size, child: Icon))`). Replace each `Material > InkWell` with:

```dart
      child: TpHover(
        backgroundColor: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        width: 30,
        height: <each file's _size constant>,
        hoverColor: color.withValues(alpha: 0.12),
        splashColor: color.withValues(alpha: 0.2),
        onTap: onTap,
        child: Center(child: Icon(icon, size: context.tpIconSizes.sm, color: color)),
      ),
```

(`_size` = `MarkdownViewModeToggle._size`, `FileDiffSurfaceToggle._size`, `DiffToolbar._actionSize` respectively.)

- [ ] **Step 5: `diff_hunk_apply_gutter.dart`**

Replace `Tooltip > Material(type: transparency) > InkWell(key: Key('diff-apply-hunk-…'), onTap: apply, child: Center(Text('>>')))` (lines ~39-53) with Pattern M, preserving the `key` on the `TpHover`:

```dart
              child: TpHover(
                key: Key('diff-apply-hunk-${block.startRow}'),
                onTap: () => onApply(block),
                child: const Center(
                  child: Text(
                    '>>',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 6: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/widgets --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/widgets/window_chrome_controls.dart lib/widgets/workspace_terminal/workspace_terminal_empty_pane.dart lib/widgets/workspace_icon_picker_dialog.dart lib/widgets/workbench/markdown_view_mode_toggle.dart lib/widgets/workbench/file_diff_surface_toggle.dart lib/widgets/diff/diff_toolbar.dart lib/widgets/diff/diff_hunk_apply_gutter.dart
git commit -m "refactor(widgets): migrate toolbar/toggle/chrome tappables from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Widgets batch 2 (8 sites)

**Files:**
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Modify: `client/lib/widgets/right_tools/board_panel.dart`
- Modify: `client/lib/widgets/notification/progress_activity_tile.dart`
- Modify: `client/lib/widgets/run/run_toolbar.dart`
- Modify: `client/lib/widgets/run/run_toolbar_config_dropdown.dart`
- Modify: `client/lib/widgets/settings/workspace_hub_shell.dart`
- Modify: `client/lib/widgets/android_work_environment_selector.dart`
- Modify: `client/lib/widgets/android_ssh_profile_selector.dart`
- Test: `cd client && flutter test test/widgets --exclude-tags integration`

- [ ] **Step 1: `git_source_control_panel.dart` branch row**

Replace `InkWell(onTap: onBranch, borderRadius: 6, child: Padding(4,4, Row(…)))` (line ~597) with Pattern M (borderRadius 6).

- [ ] **Step 2: `board_panel.dart` task card row**

Replace `InkWell(onTap: onTap, child: Padding(12,8, Row(#seq, …)))` (line ~162) with Pattern M, keeping the child Row unchanged.

- [ ] **Step 3: `progress_activity_tile.dart`**

Replace `Material(transparent) > InkWell(onTap: onTap, child: Padding(12,10, Row(…)))` (lines ~53-57) with Pattern R but sharp corners (`borderRadius: BorderRadius.zero`) to match the original full-rect InkWell:

```dart
    return TpHover(
      backgroundColor: Colors.transparent,
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: /* … existing Row unchanged … */,
      ),
    );
```

- [ ] **Step 4: the two run-toolbar menu triggers**

In `run_toolbar.dart` and `run_toolbar_config_dropdown.dart`, each has `Material(transparent, borderRadius: 6, clipBehavior: antiAlias) > InkWell(borderRadius: 6, onTap: toggle, child: Padding(6,4, …))` (run_toolbar.dart ~123-135, run_toolbar_config_dropdown.dart ~80-92). Replace with Pattern R (borderRadius 6). The old comment about the Material clipping the hover to the rounded rect is now satisfied by `TpHover`'s self-clipped fill — drop the `Material`/`clipBehavior`.

- [ ] **Step 5: `workspace_hub_shell.dart`**

Replace `Material(color: selected ? selectedColor : hubStyle ? cs.workspaceSubtleSurface : transparent, borderRadius: borderRadius) > InkWell(borderRadius: borderRadius, onTap: onTap, child: SizedBox(height, Padding(Row(…))))` (lines ~100-114) with Pattern R (borderRadius: `borderRadius`), keeping the `SizedBox(height: height, child: Padding(…))` child.

- [ ] **Step 6: the two Android selector menu triggers**

In `android_work_environment_selector.dart` (line ~49) and `android_ssh_profile_selector.dart` (line ~42), replace the bare `InkWell(onTap: toggle, child: Padding(horizontal 8, Row(…)))` (inside `TpActionMenuIconAnchor.triggerBuilder`) with Pattern M:

```dart
        return TpHover(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: /* … existing Row unchanged … */,
          ),
        );
```

- [ ] **Step 7: Verify + commit**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/widgets --exclude-tags integration
```
Expected: PASS.

```bash
git add lib/widgets/git/git_source_control_panel.dart lib/widgets/right_tools/board_panel.dart lib/widgets/notification/progress_activity_tile.dart lib/widgets/run/run_toolbar.dart lib/widgets/run/run_toolbar_config_dropdown.dart lib/widgets/settings/workspace_hub_shell.dart lib/widgets/android_work_environment_selector.dart lib/widgets/android_ssh_profile_selector.dart
git commit -m "refactor(widgets): migrate remaining tappables from InkWell to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: shared_ui internal InkWells + submodule bump (4 sites)

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/icon_button/tp_icon_button.dart`
- Modify: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_nav_shell.dart`
- Modify: `client/packages/shared_ui/lib/src/toast/engine/src/built_in/widget/common/close_button.dart`
- Test: `cd client/packages/shared_ui && flutter test`

- [ ] **Step 1: `tp_icon_button.dart`**

Replace the `Ink + InkWell` construction (lines ~88-113) with `TpHover`. The existing explicit `mouseCursor` lines are dropped (`TpHover` supplies the cursor). New:

```dart
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: TpHover(
        width: size,
        height: size,
        borderRadius: radius,
        backgroundColor: fill,
        border: border,
        hoverColor: effectiveColor.withValues(alpha: 0.12),
        splashColor: effectiveColor.withValues(alpha: 0.2),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Center(child: iconChild),
      ),
    );
```

Keep the `iconChild`/`effectiveColor`/`fill`/`border` computations unchanged. The `Material` wrapper is retained only for the icon's ink/theme context (harmless with `TpHover`'s own fill).

- [ ] **Step 2: `tp_dialog_nav_shell.dart` — nav item + dropdown entry**

- Nav item (lines ~241-247): replace `Material(color: selected ? primaryContainer : transparent, borderRadius: 12) > InkWell(borderRadius: 12, onTap: onTap, child: SizedBox(height: _height, Padding(…)))` with Pattern R (borderRadius 12), keeping the outer `Padding(bottom: _itemGap)`.
- Dropdown entry (lines ~462-470): replace `Material(transparent) > InkWell(onTap: () => onSelect(index), child: Padding(lg, md+2, Row(…)))` with Pattern R (no borderRadius → default 8).

- [ ] **Step 3: `close_button.dart`**

Replace `Material(transparent, borderRadius: 5) > Builder > InkWell(onTap: onCloseTap, borderRadius: 5, child: Icon(…))` (lines ~149-161) with Pattern R (borderRadius 5), keeping the `Builder` if it still provides the `BuildContext` used by surrounding code:

```dart
        child: Builder(
          builder: (context) {
            return TpHover(
              borderRadius: BorderRadius.circular(5),
              onTap: onCloseTap,
              child: Icon(
                toastStyle.closeIcon,
                color: toastStyle.closeIconColor,
                size: 18,
              ),
            );
          },
        ),
```

- [ ] **Step 4: Verify + commit submodule**

```
cd client/packages/shared_ui && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client/packages/shared_ui && flutter test
```
Expected: PASS.

```bash
cd client/packages/shared_ui
git add lib/src/components/icon_button/tp_icon_button.dart lib/src/components/dialog/tp_dialog_nav_shell.dart lib/src/toast/engine/src/built_in/widget/common/close_button.dart
git commit -m "refactor(shared_ui): migrate internal InkWell uses to TpHover

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 5: Bump the submodule pointer in the parent**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui
git commit -m "chore(submodule): bump shared_ui for adaptive TpHover + InkWell migration

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Full gate + verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze + test**

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```
Expected: all pass. If any widget test asserts `TpHover`'s desktop structure (`AnimatedContainer` fill, `MouseRegion` cursor) and fails under the default Android test platform, add `debugDefaultTargetPlatformOverride = TargetPlatform.linux;` (+ reset in `tearDown`) to that specific test file — the known candidate is `test/pages/floating_workspace/floating_workspace_empty_test.dart`.

- [ ] **Step 2: Confirm no bare `InkWell(` remains in first-party UI**

```
cd client && grep -rn "InkWell(" lib/ --include="*.dart"
```
Expected: only `shared_ui`'s adaptive touch path in `tp_hover.dart` (and any non-tappable uses deliberately left). List remaining sites and confirm each is intentional (none should be a clickable button).

- [ ] **Step 3: Manual desktop check**

Run the app on Linux. Verify:
1. Compose card buttons (send / + / ✨ / mic / stop / team-settings / all chips) show a hand pointer on hover and an arrow when disabled (e.g. send with empty input).
2. Hover shows the color fade; click has no ink ripple on desktop.
3. Keyboard: Tab to a compose button and Enter/Space activates it.
4. Follow-up queue `IconButton`s and Material buttons elsewhere in the app now show the hand pointer.
5. No cursor change on text inputs (I-beam preserved).

- [ ] **Step 4: Manual touch check (Android)**

Run on an Android device/emulator. Verify: taps on migrated buttons show a ripple; no hover paint; nothing crashes; the touch path renders `Material`+`InkWell` (spot-check a stadium chip and a circle button).

---

## Self-Review Notes

- **Spec coverage:** Task 1 = spec §1 (adaptive `TpHover`), Task 2 = spec §2 (theme), Tasks 3–10 = spec §3 (44 `InkWell` migrations: compose 7, chips/trigger 3, chat 5, home/team/expert/skills 7, mcp/llm/workbench 4, widgets 7 + 8, shared_ui 4 = 45 site-groups; exact site counts verified per file during implementation). Task 11 = spec Testing/Risks.
- **Test impact of adaptive `TpHover`:** shared_ui tests are forced to the desktop path via the new `test/flutter_test_config.dart`; the one main-repo test asserting `TpHover`'s desktop fill (`floating_workspace_empty_test.dart`) gets a per-file override in Task 11 Step 1.
- **Type consistency:** `TpPressableShape.{rounded,stadium,circle}`, `onTapDown/onTapUp/onTapCancel`, `canRequestFocus`, `splashColor`, and `kTpClickableMouseCursor` are the only new names; every task uses the exact spellings defined in Tasks 1–2.
