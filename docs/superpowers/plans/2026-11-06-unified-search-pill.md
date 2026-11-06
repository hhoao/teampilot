# Unified Search Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every search/filter input into the reference stadium-pill search bar without changing any behavior.

**Architecture:** Add one shared stadium `InputDecoration` helper in `shared_ui`, restyle the client find-bar primitives (`FindBarPanel` / `FindField`) into a borderless pill with a leading search icon, then migrate each call site by swapping only its decoration (or setting the new `standalone` flag). Controllers, callbacks, debounce, shortcuts, counters, toggles, navigation, and clear behavior stay exactly as they are.

**Tech Stack:** Flutter/Dart, `shared_ui` design system (git submodule), `flutter_test`.

## Global Constraints

- **Style only.** Do not change controllers, callbacks, debounce timings, shortcuts, match navigation, toggles, or clear behavior. Do not add a clear button where none exists today.
- **Never run `flutter test` directly.** Always `cd client && dart run tool/run_tests.dart <paths>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Single pill radius constant: `tpSearchPillRadius = 999` exported from `shared_ui`. `FindBarPanel.kPillRadius = tpSearchPillRadius`, `FindBarPanel.kCardRadius = 16`.
- `client/packages/shared_ui` is a **git submodule**. Every task that edits it must commit inside the submodule first, then bump the pointer in the main repo.
- The working tree already contains unrelated modifications. Stage only the paths listed in each task; never `git add -A`.
- No new l10n strings are expected. If one becomes necessary, edit only `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- UI style tasks follow TDD for the shared decoration contract and for representative site tests; the remaining site migrations are verified by existing widget tests plus the manual checklist in Task 12.

---

### Task 1: Shared pill decoration + `TpInput` radius override

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/input/tp_search_pill.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Modify: `client/packages/shared_ui/lib/src/components/input/tp_input.dart`
- Test: `client/test/theme/tp_search_pill_test.dart`

**Interfaces:**
- Produces:
  - `const double tpSearchPillRadius = 999;`
  - `InputDecoration tpSearchPillDecoration(BuildContext context, {String? hintText, Widget? prefixIcon, Widget? suffixIcon, Color? fillColor, EdgeInsetsGeometry? contentPadding})`
  - `InputDecoration tpOutlineInputDecoration(BuildContext context, {InputDecoration? decoration, bool hasError = false, double? borderRadius})`
  - `TpInput` gains a new optional `double? borderRadius` parameter; all existing parameters are unchanged.

- [ ] **Step 1: Write the failing test**

Create `client/test/theme/tp_search_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('pill decoration is a stadium search field', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    final decoration = tpSearchPillDecoration(
      context,
      hintText: 'Search messages',
    );
    final scheme = Theme.of(context).colorScheme;

    expect(decoration.hintText, 'Search messages');
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, scheme.surfaceContainer);
    expect(decoration.floatingLabelBehavior, FloatingLabelBehavior.never);
    expect(decoration.prefixIcon, isA<Icon>());

    final enabled = decoration.enabledBorder! as OutlineInputBorder;
    expect(
      enabled.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
    final focused = decoration.focusedBorder! as OutlineInputBorder;
    expect(
      focused.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
    expect(focused.borderSide.color, scheme.primary);
  });

  testWidgets('TpInput honors an explicit pill borderRadius', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(
          body: TpInput(borderRadius: tpSearchPillRadius),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/theme/tp_search_pill_test.dart`

Expected: FAIL — `tpSearchPillDecoration` / `tpSearchPillRadius` / `borderRadius` are not defined.

- [ ] **Step 3: Add the shared helper**

Create `client/packages/shared_ui/lib/src/components/input/tp_search_pill.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/tp_theme.dart';

/// Single source of truth for the stadium radius used by every search input.
const double tpSearchPillRadius = 999;

/// Stadium-shaped search/filter decoration.
///
/// Callers keep their own [TextField], controller, and callbacks; only the
/// chrome changes. Pass [prefixIcon] to replace the default search glyph, and
/// [fillColor] when a surface needs to keep its previous fill.
InputDecoration tpSearchPillDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  Color? fillColor,
  EdgeInsetsGeometry? contentPadding,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final inputTheme = theme.inputDecorationTheme;
  final tp = TpTheme.of(context);
  final metrics = tp.inputTheme;
  const radius = BorderRadius.all(Radius.circular(tpSearchPillRadius));

  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );

  final hintBase = theme.textTheme.bodyMedium ?? theme.textTheme.bodyLarge!;
  final hintStyle = (inputTheme.hintStyle ?? hintBase).copyWith(
    color: scheme.onSurfaceVariant.withValues(alpha: metrics.hintAlpha),
    height: 1.25,
    fontWeight: FontWeight.w400,
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle,
    isDense: true,
    filled: true,
    fillColor: fillColor ?? scheme.surfaceContainer,
    contentPadding:
        contentPadding ??
        EdgeInsets.symmetric(
          horizontal: tp.control.input.horizontalPadding + 2,
          vertical: tp.control.input.verticalPadding,
        ),
    prefixIcon:
        prefixIcon ??
        Icon(
          Icons.search_rounded,
          size: context.tpIconSizes.md,
          color: scheme.onSurfaceVariant,
        ),
    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    suffixIcon: suffixIcon,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    border: border(scheme.outlineVariant),
    enabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.7)),
    focusedBorder: border(scheme.primary, metrics.focusedBorderWidth),
  );
}
```

- [ ] **Step 4: Export the helper and add the `borderRadius` override**

In `client/packages/shared_ui/lib/shared_ui.dart`, add after the existing input export:

```dart
export 'src/components/input/tp_search_pill.dart';
```

In `client/packages/shared_ui/lib/src/components/input/tp_input.dart`, add `double? borderRadius` to the `tpOutlineInputDecoration` parameter list, then change the existing radius line from `BorderRadius.circular(control.radius)` to:

```dart
final radius = BorderRadius.circular(borderRadius ?? control.radius);
```

Leave the rest of `tpOutlineInputDecoration` (the `outlineBorder` / `themed` builders and every `copyWith`) untouched.

In `TpInput`, add `this.borderRadius,` to the constructor parameter list and add the matching field next to the other optional fields:

```dart
final double? borderRadius;
```

And in `_TpInputState.build`:

```dart
decoration: tpOutlineInputDecoration(
  context,
  decoration: widget.decoration,
  borderRadius: widget.borderRadius,
),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/theme/tp_search_pill_test.dart`

Expected: PASS (2 tests).

- [ ] **Step 6: Commit the submodule and the pointer bump**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
git add lib/shared_ui.dart lib/src/components/input/tp_input.dart lib/src/components/input/tp_search_pill.dart
git commit -m "style(shared_ui): add stadium search pill decoration"

cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui client/test/theme/tp_search_pill_test.dart
git commit -m "test(search): cover shared search pill decoration"
```

---

### Task 2: Pill find-bar primitives

**Files:**
- Modify: `client/lib/widgets/find/find_bar_palette.dart`
- Modify: `client/lib/widgets/find/find_bar_widgets.dart`
- Test: `client/test/widgets/find/find_bar_widgets_test.dart`

**Interfaces:**
- Consumes: `tpSearchPillRadius` from `shared_ui` (Task 1).
- Produces:
  - `FindBarPanel({required Widget child, double borderRadius = kPillRadius, FocusNode? focusNode})`
  - `static const double FindBarPanel.kPillRadius = tpSearchPillRadius;`
  - `static const double FindBarPanel.kCardRadius = 16;`
  - `FindField` gains `bool standalone`, `Widget? trailing`, and `ValueChanged<String>? onSubmitted`; existing parameters are unchanged.
  - `class FindBarDivider extends StatelessWidget` with `double height = 18`.

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/find/find_bar_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/find/find_bar_palette.dart';
import 'package:teampilot/widgets/find/find_bar_widgets.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      extensions: const [FindBarPalette.light],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('FindBarPanel defaults to a stadium pill', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FindBarPanel(
          child: SizedBox(width: 200, height: FindField.kHeight),
        ),
      ),
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(FindBarPanel),
            matching: find.byType(Material),
          ),
        )
        .first;
    final shape = material.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.all(Radius.circular(FindBarPanel.kPillRadius)),
    );
  });

  testWidgets('FindBarPanel accepts the expanded card radius', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FindBarPanel(
          borderRadius: FindBarPanel.kCardRadius,
          child: SizedBox(width: 200, height: FindField.kHeight),
        ),
      ),
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(FindBarPanel),
            matching: find.byType(Material),
          ),
        )
        .first;
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('FindBarPanel switches to the focus border', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _wrap(
        FindBarPanel(
          focusNode: focus,
          child: Focus(
            focusNode: focus,
            child: const SizedBox(width: 200, height: FindField.kHeight),
          ),
        ),
      ),
    );

    Color panelBorderColor() {
      final material = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(FindBarPanel),
              matching: find.byType(Material),
            ),
          )
          .first;
      return (material.shape! as RoundedRectangleBorder).side.color;
    }

    expect(panelBorderColor(), FindBarPalette.light.panelBorder);
    focus.requestFocus();
    await tester.pump();
    expect(panelBorderColor(), FindBarPalette.light.focusBorder);
  });

  testWidgets('FindField shows a search icon and renders the hint', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
        ),
      ),
    );

    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('FindField standalone mode draws its own pill border', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      _wrap(
        FindField(
          controller: controller,
          focusNode: focus,
          hint: 'Search',
          standalone: true,
        ),
      ),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FindField),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      const BorderRadius.all(Radius.circular(FindBarPanel.kPillRadius)),
    );
  });

  testWidgets('FindBarDivider is a hairline', (tester) async {
    await tester.pumpWidget(_wrap(const FindBarDivider()));
    final size = tester.getSize(find.byType(FindBarDivider));
    expect(size.height, 18);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/find/find_bar_widgets_test.dart`

Expected: FAIL — `borderRadius`, `focusNode`, `standalone`, and `FindBarDivider` do not exist; the default radius is 4.

- [ ] **Step 3: Update the palette**

In `client/lib/widgets/find/find_bar_palette.dart`, change the light values and the dark border:

```dart
static const FindBarPalette light = FindBarPalette(
  panelBg: Color(0xFFFFFFFF),
  panelBorder: Color(0xFFE3E3E3),
  fieldBg: Color(0xFFFFFFFF),
  border: Color(0xFFE3E3E3),
  focusBorder: Color(0xFF006BB1),
  text: Color(0xFF333333),
  mutedText: Color(0xFF6B6B6B),
  icon: Color(0xFF424242),
  hoverBg: Color(0xFFE5EBF1),
  activeBg: Color(0xFFC9E5FF),
  activeBorder: Color(0xFF006BB1),
  toggleOnText: Color(0xFF006BB1),
  shadow: Color(0x1F000000),
);

static const FindBarPalette dark = FindBarPalette(
  panelBg: Color(0xFF252526),
  panelBorder: Color(0xFF3A3A3A),
  fieldBg: Color(0xFF3C3C3C),
  border: Color(0xFF3C3C3C),
  focusBorder: Color(0xFF007FD4),
  text: Color(0xFFCCCCCC),
  mutedText: Color(0xFF858585),
  icon: Color(0xFFC5C5C5),
  hoverBg: Color(0xFF2A2D2E),
  activeBg: Color(0xFF3A3D41),
  activeBorder: Color(0xFF007FD4),
  toggleOnText: Color(0xFFFFFFFF),
  shadow: Color(0x5C000000),
);
```

Do not add or remove palette fields; `copyWith` / `lerp` stay untouched.

- [ ] **Step 4: Restyle `FindBarPanel` and add `FindBarDivider`**

Replace `FindBarPanel` in `client/lib/widgets/find/find_bar_widgets.dart`:

```dart
class FindBarPanel extends StatelessWidget {
  const FindBarPanel({
    required this.child,
    this.borderRadius = kPillRadius,
    this.focusNode,
    super.key,
  });

  static const double kPillRadius = tpSearchPillRadius;
  static const double kCardRadius = 16;

  final Widget child;
  final double borderRadius;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final radius = BorderRadius.circular(borderRadius);

    Widget buildPanel(Color borderColor) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: palette.panelBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
    }

    final node = focusNode;
    if (node == null) {
      return buildPanel(palette.panelBorder);
    }
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        return buildPanel(
          node.hasFocus ? palette.focusBorder : palette.panelBorder,
        );
      },
    );
  }
}

/// Vertical hairline separating search / counter / navigation groups.
class FindBarDivider extends StatelessWidget {
  const FindBarDivider({this.height = 18, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: FindBarPalette.of(context).panelBorder,
    );
  }
}
```

- [ ] **Step 5: Restyle `FindField`**

Replace the `FindField` class body with this version (keep `_ClearButton` unchanged):

```dart
class FindField extends StatelessWidget {
  const FindField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.toggles = const [],
    this.showClear = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.width,
    this.standalone = false,
    this.trailing,
    super.key,
  });

  /// Tall enough for the md text + vertical padding without clipping.
  static const double kHeight = 34;

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final List<Widget> toggles;
  final bool showClear;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final double? width;

  /// When true the field is not inside a [FindBarPanel] and draws its own
  /// pill border (right-tools search panel).
  final bool standalone;

  /// Optional non-interactive trailing content (e.g. terminal find status).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final styles = TpTextStyles.of(context);

    return SizedBox(
      width: width,
      height: kHeight,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final row = Row(
            children: [
              const SizedBox(width: 8),
              Icon(
                Icons.search_rounded,
                size: context.tpIconSizes.md,
                color: palette.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  maxLines: 1,
                  style: styles.md.copyWith(color: palette.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: styles.md.copyWith(color: palette.mutedText),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 5,
                    ),
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              ...toggles,
              if (trailing != null) trailing!,
              if (showClear)
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _ClearButton(
                    visible: controller.text.isNotEmpty,
                    color: palette.icon,
                    hoverColor: palette.hoverBg,
                    onTap: onClear,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          );
          if (!standalone) {
            return row;
          }
          return Container(
            decoration: BoxDecoration(
              color: palette.fieldBg,
              borderRadius: BorderRadius.circular(FindBarPanel.kPillRadius),
              border: Border.all(
                color: focused ? palette.focusBorder : palette.border,
              ),
            ),
            child: row,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/widgets/find/find_bar_widgets_test.dart`

Expected: PASS (6 tests).

- [ ] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/find/find_bar_palette.dart client/lib/widgets/find/find_bar_widgets.dart client/test/widgets/find/find_bar_widgets_test.dart
git commit -m "style(find): turn find bar primitives into a search pill"
```

---

### Task 3: Chat find bar

**Files:**
- Modify: `client/lib/pages/chat/chat_find_bar.dart`
- Test: `client/test/pages/chat/session_chat_view_find_test.dart`

**Interfaces:**
- Consumes: `FindBarPanel.kPillRadius`, `FindBarPanel.kCardRadius`, `FindBarDivider`, `FindField` without a fixed width (Task 2).
- Produces: no new API.

- [ ] **Step 1: Add the failing style test**

Append this test to `client/test/pages/chat/session_chat_view_find_test.dart` and add the import:

```dart
import 'package:teampilot/widgets/find/find_bar_widgets.dart';
```

```dart
testWidgets('ChatFindBar is a pill until results expand it', (tester) async {
  final messages = <AiMessage>[
    AiMessage(
      id: 'm-0',
      role: AiRole.user,
      parts: const [AiTextPart(text: 'alpha note')],
    ),
  ];
  final controller = ChatTranscriptFindController(
    messagesProvider: () => messages,
  );
  addTearDown(controller.dispose);
  final query = TextEditingController();
  final focus = FocusNode();
  addTearDown(query.dispose);
  addTearDown(focus.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatFindBar(
          controller: controller,
          queryController: query,
          focusNode: focus,
          onNavigate: (_) {},
          onClose: () {},
        ),
      ),
    ),
  );

  FindBarPanel panel() =>
      tester.widget<FindBarPanel>(find.byType(FindBarPanel));

  expect(panel().borderRadius, FindBarPanel.kPillRadius);

  await tester.enterText(find.byType(TextField), 'alpha');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();

  expect(controller.hits, isNotEmpty);
  expect(panel().borderRadius, FindBarPanel.kCardRadius);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_find_test.dart --plain-name "ChatFindBar is a pill until results expand it"`

Expected: FAIL — `FindBarPanel` has no `borderRadius` default of 999 (after Task 2 it exists but the chat bar still uses the default 999 for both states; the second expectation fails because there is no card radius).

- [ ] **Step 3: Apply the pill layout**

In `client/lib/pages/chat/chat_find_bar.dart`, add these two arguments to the existing `FindBarPanel(` call and leave its `child: Column(...)` untouched:

```dart
  focusNode: widget.focusNode,
  borderRadius: total > 0
      ? FindBarPanel.kCardRadius
      : FindBarPanel.kPillRadius,
```

Replace the row children so the field expands and group dividers appear:

```dart
children: [
  Expanded(
    child: FindField(
      controller: widget.queryController,
      focusNode: widget.focusNode,
      hint: l10n.chatFindHint,
      autofocus: true,
      showClear: true,
      onChanged: _onChanged,
      onClear: _clear,
      toggles: [
        FindToggleButton(
          iconAsset: FindBarIcons.caseSensitive,
          tooltip: l10n.chatFindMatchCase,
          checked: controller.caseSensitive,
          onTap: controller.toggleCaseSensitive,
        ),
        FindToggleButton(
          iconAsset: FindBarIcons.wholeWord,
          tooltip: l10n.chatFindWholeWord,
          checked: controller.wholeWord,
          onTap: controller.toggleWholeWord,
        ),
        FindToggleButton(
          iconAsset: FindBarIcons.regexp,
          tooltip: l10n.chatFindUseRegex,
          checked: controller.regex,
          onTap: controller.toggleRegex,
        ),
      ],
    ),
  ),
  const SizedBox(width: 4),
  FindCounterText(
    label: counter,
    empty: total == 0,
    width: 76,
  ),
  const FindBarDivider(),
  FindActionButton(
    icon: Icons.keyboard_arrow_up,
    tooltip: l10n.chatFindPrevious,
    enabled: total > 0,
    onTap: () {
      controller.previous();
      _navigateCurrent();
    },
  ),
  FindActionButton(
    icon: Icons.keyboard_arrow_down,
    tooltip: l10n.chatFindNext,
    enabled: total > 0,
    onTap: () {
      controller.next();
      _navigateCurrent();
    },
  ),
  const FindBarDivider(),
  FindActionButton(
    icon: Icons.close,
    tooltip: l10n.chatFindClose,
    onTap: widget.onClose,
  ),
],
```

Keep the results list and its padding unchanged.

- [ ] **Step 4: Run the chat find tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/session_chat_view_find_test.dart`

Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/chat/chat_find_bar.dart client/test/pages/chat/session_chat_view_find_test.dart
git commit -m "style(chat): render the find bar as a search pill"
```

---

### Task 4: Editor and Markdown find bars

**Files:**
- Modify: `client/lib/widgets/workbench/code_editor_find_panel.dart`
- Modify: `client/lib/widgets/workbench/markdown_preview_find_bar.dart`
- Test: `client/test/widgets/workbench/code_editor_find_panel_test.dart`
- Test: `client/test/widgets/workbench/markdown_preview_find_bar_test.dart`

**Interfaces:**
- Consumes: `FindBarPanel(focusNode:, borderRadius:)`, `FindBarDivider` (Task 2).
- Produces: no new API.

- [ ] **Step 1: Add the failing editor test**

Add to `client/test/widgets/workbench/code_editor_find_panel_test.dart` (import `package:teampilot/widgets/find/find_bar_widgets.dart`):

```dart
testWidgets('find row is a pill; replace row expands to a card', (
  tester,
) async {
  final ctrl = await pumpPanel(tester);
  ctrl.findMode();
  await tester.pump();

  FindBarPanel panel() =>
      tester.widget<FindBarPanel>(find.byType(FindBarPanel));
  expect(panel().borderRadius, FindBarPanel.kPillRadius);

  ctrl.replaceMode();
  await tester.pump();
  expect(panel().borderRadius, FindBarPanel.kCardRadius);

  ctrl.close();
  await tester.pump();
});
```

- [ ] **Step 2: Add the failing Markdown test**

Add to `client/test/widgets/workbench/markdown_preview_find_bar_test.dart`:

```dart
testWidgets('find bar uses the pill radius and group divider', (tester) async {
  final controller = await pumpBar(tester);
  final panel = tester.widget<FindBarPanel>(find.byType(FindBarPanel));
  expect(panel.borderRadius, FindBarPanel.kPillRadius);
  expect(find.byType(FindBarDivider), findsOneWidget);
  controller.dispose();
});
```

- [ ] **Step 3: Run both to verify they fail**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/workbench/code_editor_find_panel_test.dart --plain-name "find row is a pill; replace row expands to a card"
dart run tool/run_tests.dart test/widgets/workbench/markdown_preview_find_bar_test.dart --plain-name "find bar uses the pill radius and group divider"
```

Expected: FAIL — the editor panel stays at the default radius for both states, and the Markdown bar has no `FindBarDivider`.

- [ ] **Step 4: Update `CodeEditorFindPanel`**

In `client/lib/widgets/workbench/code_editor_find_panel.dart`, change the field width constant:

```dart
static const double _findFieldWidth = 240;
```

Add these two arguments to the existing `FindBarPanel(` call and leave its `child: Padding(...)` untouched:

```dart
  focusNode: controller.findInputFocusNode,
  borderRadius: showReplace
      ? FindBarPanel.kCardRadius
      : FindBarPanel.kPillRadius,
```

In `_buildFindRow`, insert `const FindBarDivider(),` immediately after `FindCounterText` and immediately before the final close `FindActionButton`. Leave the up/down/find-in-selection buttons unchanged.

Keep the replace-row content, `preferredSize` calculation, and all callbacks unchanged.

- [ ] **Step 5: Update `MarkdownPreviewFindBar`**

Add `focusNode: _focus,` to the existing `FindBarPanel(` call. Leave the `Padding` / `Row` untouched.

Insert `const FindBarDivider(),` after `FindCounterText` and before the close button. Keep the field width at 240.

- [ ] **Step 6: Run both test files**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/workbench/code_editor_find_panel_test.dart test/widgets/workbench/markdown_preview_find_bar_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/workbench/code_editor_find_panel.dart client/lib/widgets/workbench/markdown_preview_find_bar.dart client/test/widgets/workbench/code_editor_find_panel_test.dart client/test/widgets/workbench/markdown_preview_find_bar_test.dart
git commit -m "style(workbench): use the search pill in editor and markdown find bars"
```

---

### Task 5: Terminal find bar

**Files:**
- Modify: `client/lib/widgets/terminal_find_bar.dart`
- Test: `client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart`

**Interfaces:**
- Consumes: `FindBarPanel`, `FindField(trailing:, onSubmitted:)`, `FindActionButton` (Tasks 2).
- Produces: no new API.

- [ ] **Step 1: Add the failing assertion**

In `client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart`, add the import:

```dart
import 'package:teampilot/widgets/find/find_bar_widgets.dart';
```

Inside the first test (`openFind shows TerminalFindBar`), after the existing expectations:

```dart
expect(find.byType(FindBarPanel), findsOneWidget);
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart --plain-name "openFind shows TerminalFindBar"`

Expected: FAIL — the terminal bar uses a bare `Material`, not `FindBarPanel`.

- [ ] **Step 3: Migrate `TerminalFindBar`**

In `client/lib/widgets/terminal_find_bar.dart`, add imports:

```dart
import '../../widgets/find/find_bar_palette.dart';
import '../../widgets/find/find_bar_widgets.dart';
```

Add a focus node to the state:

```dart
final _focusNode = FocusNode();

@override
void dispose() {
  _focusNode.dispose();
  _queryController.dispose();
  super.dispose();
}
```

Replace `build` with:

```dart
@override
Widget build(BuildContext context) {
  final palette = FindBarPalette.of(context);
  final styles = TpTextStyles.of(context);
  final query = _queryController.text;
  final status = !widget.controller.searchValid && query.isNotEmpty
      ? widget.noResultsLabel
      : query.isEmpty
      ? ''
      : 'regex';

  return FindBarPanel(
    focusNode: _focusNode,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: FindField(
              controller: _queryController,
              focusNode: _focusNode,
              hint: widget.searchLabel,
              autofocus: true,
              onChanged: (_) => _runSearch(),
              onSubmitted: (_) => _step(true),
              trailing: status.isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        status,
                        style: styles.sm.copyWith(color: palette.mutedText),
                      ),
                    ),
            ),
          ),
          FindActionButton(
            tooltip: 'Previous',
            icon: Icons.keyboard_arrow_up,
            onTap: () => _step(false),
          ),
          FindActionButton(
            tooltip: 'Next',
            icon: Icons.keyboard_arrow_down,
            onTap: () => _step(true),
          ),
          FindActionButton(
            tooltip: 'Close',
            icon: Icons.close,
            onTap: _close,
          ),
        ],
      ),
    ),
  );
}
```

Keep `_runSearch`, `_step`, `_close`, and all shortcut wiring unchanged. Do not add a clear button.

- [ ] **Step 4: Run the terminal tests**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart`

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/terminal_find_bar.dart client/test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart
git commit -m "style(terminal): render the find bar as a search pill"
```

---

### Task 6: Right-tools search panel fields

**Files:**
- Modify: `client/lib/widgets/right_tools/search_panel.dart`
- Modify: `client/lib/widgets/right_tools/search_panel_form.dart`
- Test: `client/test/widgets/right_tools/search_panel_test.dart`

**Interfaces:**
- Consumes: `FindField(standalone: true)` (Task 2).
- Produces: no new API.

- [ ] **Step 1: Add the failing test**

Add to `client/test/widgets/right_tools/search_panel_test.dart` (import `package:teampilot/widgets/find/find_bar_widgets.dart`):

```dart
testWidgets('search fields render as standalone pills', (tester) async {
  final cubit = buildCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(wrap(cubit));

  final fields = tester.widgetList<FindField>(find.byType(FindField)).toList();
  expect(fields, isNotEmpty);
  expect(fields.every((field) => field.standalone), isTrue);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/right_tools/search_panel_test.dart --plain-name "search fields render as standalone pills"`

Expected: FAIL — `standalone` is false.

- [ ] **Step 3: Set `standalone: true`**

In `client/lib/widgets/right_tools/search_panel.dart`, add `standalone: true` to both existing `FindField` constructors:

- Query field: keep `controller: _queryController`, `focusNode: _focusNode`, `hint: l10n.workspaceSearchQueryHint`, and its existing `toggles`.
- Replace field: keep `controller: _replaceController`, `focusNode: _replaceFocusNode`, `hint: l10n.workspaceSearchReplaceHint`.

In `client/lib/widgets/right_tools/search_panel_form.dart`, both include/exclude fields:

```dart
FindField(
  controller: includeController,
  focusNode: includeFocusNode,
  hint: l10n.workspaceSearchIncludeHint,
  standalone: true,
  onChanged: onGlobChanged,
),
```

```dart
FindField(
  controller: excludeController,
  focusNode: excludeFocusNode,
  hint: l10n.workspaceSearchExcludeHint,
  standalone: true,
  onChanged: onGlobChanged,
),
```

Do not change toggles, replace buttons, details toggle, or results.

- [ ] **Step 4: Run the search panel tests**

Run: `cd client && dart run tool/run_tests.dart test/widgets/right_tools/search_panel_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/right_tools/search_panel.dart client/lib/widgets/right_tools/search_panel_form.dart client/test/widgets/right_tools/search_panel_test.dart
git commit -m "style(right-tools): render search panel fields as standalone pills"
```

---

### Task 7: Workspace search dialog and content search

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_widgets.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_content_section.dart`
- Test: `client/test/widgets/search/workspace_search_field_test.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`

**Interfaces:**
- Consumes: `tpSearchPillDecoration` (Task 1).
- Produces: no new API.

- [ ] **Step 1: Write the failing tests**

Create `client/test/widgets/search/workspace_search_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_widgets.dart';

void main() {
  testWidgets('WorkspaceSearchField uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchField(
            controller: controller,
            hint: 'Search workspace',
            onChanged: (_) {},
            onClear: controller.clear,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
```

Add to `client/test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart`:

```dart
testWidgets('content search field uses the pill decoration', (tester) async {
  await tester.pumpWidget(wrapSection(onOpenFile: (_) {}));

  final field = tester.widget<TextField>(find.byType(TextField).first);
  final border = field.decoration!.enabledBorder! as OutlineInputBorder;
  expect(
    border.borderRadius,
    const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
  );
});
```

Add the shared_ui import to the content test file:

```dart
import 'package:shared_ui/shared_ui.dart';
```

- [ ] **Step 2: Run both to verify they fail**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/search/workspace_search_field_test.dart
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart --plain-name "content search field uses the pill decoration"
```

Expected: FAIL — current radii are 12 and the theme default 8.

- [ ] **Step 3: Migrate `WorkspaceSearchField`**

Replace the `InputDecoration` in `client/lib/pages/home_workspace/workspace/workspace_search_widgets.dart` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: hint,
  suffixIcon: controller.text.isNotEmpty
      ? TpIconButton(
          icon: Icons.clear,
          compact: true,
          size: TpIconButton.kCompactSize,
          onTap: onClear,
        )
      : null,
),
```

Keep the surrounding `SizedBox(height: 44)`, `controller`, `autofocus`, `style`, and `onChanged` exactly as they are.

- [ ] **Step 4: Migrate the content section**

In `client/lib/pages/home_workspace/workspace/workspace_search_content_section.dart`, add:

```dart
import 'package:shared_ui/shared_ui.dart';
```

Replace the bare `InputDecoration` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: l10n.workspaceSearchQueryHint,
),
```

Keep the regex/case `FilterChip`s, debounce, and the results list unchanged.

- [ ] **Step 5: Run both tests**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/search/workspace_search_field_test.dart test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/home_workspace/workspace/workspace_search_widgets.dart client/lib/pages/home_workspace/workspace/workspace_search_content_section.dart client/test/widgets/search/workspace_search_field_test.dart client/test/pages/home_workspace/workspace/workspace_search_dialog_content_test.dart
git commit -m "style(workspace-search): use the search pill in the dialog and content filter"
```

---

### Task 8: File tree filter and workspaces toolbar filter

**Files:**
- Modify: `client/lib/widgets/right_tools/file_tree_panel.dart`
- Modify: `client/lib/pages/home_workspace/workspaces_tab.dart`
- Test: `client/test/widgets/home_workspace/workspaces_filter_field_test.dart`

**Interfaces:**
- Consumes: `tpSearchPillDecoration` (Task 1).
- Produces: no new API.

- [ ] **Step 1: Write the failing filter test**

Create `client/test/widgets/home_workspace/workspaces_filter_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspaces_tab.dart';

void main() {
  testWidgets('WorkspacesFilterField uses a stadium radius', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspacesFilterField(
            controller: controller,
            hintText: 'Filter workspaces',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final containerFinder = find.descendant(
      of: find.byType(WorkspacesFilterField),
      matching: find.byType(AnimatedContainer),
    );
    final size = tester.getSize(containerFinder);
    final container = tester.widget<AnimatedContainer>(containerFinder);
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(size.height / 2),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/home_workspace/workspaces_filter_field_test.dart`

Expected: FAIL — the radius is 8.

- [ ] **Step 3: Migrate the file tree filter**

In `client/lib/widgets/right_tools/file_tree_panel.dart`, replace the decoration:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: hintText,
  suffixIcon: value.text.isNotEmpty
      ? TpIconButton(
          icon: Icons.clear,
          compact: true,
          size: TpIconButton.kCompactSize,
          onTap: onClear,
        )
      : null,
),
```

Keep the `ValueListenableBuilder`, `controller`, and `onChanged` unchanged.

- [ ] **Step 4: Migrate the workspaces toolbar filter**

In `client/lib/pages/home_workspace/workspaces_tab.dart`, change the container decoration:

```dart
decoration: BoxDecoration(
  color: cs.surfaceContainer,
  borderRadius: BorderRadius.circular(controlHeight / 2),
  border: Border.all(color: borderColor),
),
```

Change the inline search icon size to `context.tpIconSizes.md`. Keep the focus animation, clear button, text style, and padding unchanged.

- [ ] **Step 5: Run the test and file tree regressions**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/home_workspace/workspaces_filter_field_test.dart test/widgets/file_tree/
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/right_tools/file_tree_panel.dart client/lib/pages/home_workspace/workspaces_tab.dart client/test/widgets/home_workspace/workspaces_filter_field_test.dart
git commit -m "style(filters): use the search pill in file tree and workspaces filters"
```

---

### Task 9: Catalog header and hub search fields

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_discovery_header.dart`
- Modify: `client/lib/pages/team_hub/team_hub_body.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_body.dart`
- Modify: `client/lib/pages/team_hub/team_landing_picker_catalog_body.dart`
- Test: `client/test/widgets/catalog/tp_catalog_discovery_header_pill_test.dart`

**Interfaces:**
- Consumes: `tpSearchPillDecoration` (Task 1).
- Produces: no new API.

- [ ] **Step 1: Write the failing header test**

Create `client/test/widgets/catalog/tp_catalog_discovery_header_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('catalog search header uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpCatalogDiscoveryHeader(
            title: 'Skills',
            searchController: controller,
            searchHint: 'Search skills',
            onSearchChanged: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/catalog/tp_catalog_discovery_header_pill_test.dart`

Expected: FAIL — the header uses the theme default radius.

- [ ] **Step 3: Migrate the shared header**

In `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_discovery_header.dart`:

```dart
TextField(
  controller: searchController,
  onChanged: onSearchChanged,
  onSubmitted: onSearchSubmitted ?? onSearchChanged,
  decoration: tpSearchPillDecoration(
    context,
    hintText: searchHint,
  ),
)
```

Add the relative import:

```dart
import '../input/tp_search_pill.dart';
```

Keep `showSearch`, `belowSearch`, filters, and refresh behavior unchanged.

- [ ] **Step 4: Migrate the three hub fields**

In each file, replace the `InputDecoration` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: l10n.teamHubSearchHint,
),
```

Use `l10n.expertHubSearchHint` in `expert_hub_body.dart`. Keep the `LayoutBuilder` stacking breakpoints, `onChanged` callbacks, sort controls, and padding unchanged. `shared_ui` is already imported in all three files; if not, add `import 'package:shared_ui/shared_ui.dart';`.

- [ ] **Step 5: Run the header test and hub regressions**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/catalog/tp_catalog_discovery_header_pill_test.dart test/pages/team_hub/ test/pages/expert_hub/ test/pages/plugins/plugin_discovery_section_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the submodule and the pointer bump**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
git add lib/src/components/catalog/tp_catalog_discovery_header.dart
git commit -m "style(catalog): use the search pill in the discovery header"

cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui client/lib/pages/team_hub/team_hub_body.dart client/lib/pages/expert_hub/expert_hub_body.dart client/lib/pages/team_hub/team_landing_picker_catalog_body.dart client/test/widgets/catalog/tp_catalog_discovery_header_pill_test.dart
git commit -m "style(hubs): use the search pill in catalog and hub search fields"
```

---

### Task 10: Git graph, log viewer, and usage toolbars

**Files:**
- Modify: `client/lib/pages/git_graph/git_graph_toolbar.dart`
- Modify: `client/lib/pages/git_graph/git_graph_filterable_action_menu_panel.dart`
- Modify: `client/lib/pages/system/log_viewer_toolbar.dart`
- Modify: `client/lib/pages/usage/widgets/usage_table_toolbar.dart`
- Test: `client/test/pages/system/log_viewer_test.dart`

**Interfaces:**
- Consumes: `TpInput(borderRadius:)` and `tpSearchPillDecoration` (Task 1).
- Produces: no new API.

- [ ] **Step 1: Add the failing log viewer test**

Add to `client/test/pages/system/log_viewer_test.dart`:

```dart
testWidgets('search field uses the pill decoration', (tester) async {
  await tester.pumpWidget(
    _host(
      _toolbar(onCopyAll: () async {}, onCopyPath: () async {}),
    ),
  );
  await tester.pumpAndSettle();

  final field = tester.widget<TextField>(find.byType(TextField));
  final border = field.decoration!.enabledBorder! as OutlineInputBorder;
  expect(
    border.borderRadius,
    const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/system/log_viewer_test.dart --plain-name "search field uses the pill decoration"`

Expected: FAIL — the current radius is 8.

- [ ] **Step 3: Migrate the log viewer decoration**

Replace the body of `_fieldDecoration` in `client/lib/pages/system/log_viewer_toolbar.dart` with:

```dart
InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
}) {
  final cs = Theme.of(context).colorScheme;
  return tpSearchPillDecoration(
    context,
    hintText: hintText,
    prefixIcon: prefixIcon,
    fillColor: cs.workspaceInset,
  );
}
```

Keep the callers and the rest of the toolbar unchanged.

- [ ] **Step 4: Migrate the usage table search**

Replace the usage search `InputDecoration` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: context.l10n.sessionUsageSearchHint,
  suffixIcon: searchController.text.isEmpty
      ? null
      : IconButton(
          tooltip: context.l10n.sessionUsageResetFilters,
          iconSize: 18,
          onPressed: () {
            searchController.clear();
            onQueryChanged('');
          },
          icon: const Icon(Icons.close),
        ),
),
```

Keep the `SizedBox(height: usageFilterControlHeight)`, controller, `onChanged`, and style unchanged.

- [ ] **Step 5: Migrate the Git graph commit search**

In `client/lib/pages/git_graph/git_graph_toolbar.dart`, add `borderRadius: tpSearchPillRadius` to the `TpInput`:

```dart
return TpInput(
  initialValue: state.searchQuery.isEmpty ? null : state.searchQuery,
  textInputAction: TextInputAction.search,
  style: TpTextStyles.of(context).md,
  borderRadius: tpSearchPillRadius,
  decoration: InputDecoration(
    hintText: l10n.gitGraphSearchHint,
    prefixIcon: Icon(
      Icons.search_rounded,
      size: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 28),
    suffixIcon: Padding(
      padding: const EdgeInsets.only(right: 4),
      child: _modeDropdown(context),
    ),
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
  ),
  onSubmitted: (query) =>
      context.read<GitGraphCubit>().search(query, state.searchMode),
);
```

`shared_ui` is already imported in this file.

- [ ] **Step 6: Migrate the Git graph action-menu filter**

In `client/lib/pages/git_graph/git_graph_filterable_action_menu_panel.dart`, replace the `InputDecoration` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: filterHint,
),
```

Add `import 'package:shared_ui/shared_ui.dart';` if it is not already imported. Keep `focusNode`, `autofocus`, `onChanged`, and the style.

- [ ] **Step 7: Run the affected tests**

Run:

```bash
cd client
dart run tool/run_tests.dart test/pages/system/log_viewer_test.dart test/pages/git_graph/ test/pages/usage/usage_detail_table_test.dart test/pages/usage/session_usage_page_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/git_graph/git_graph_toolbar.dart client/lib/pages/git_graph/git_graph_filterable_action_menu_panel.dart client/lib/pages/system/log_viewer_toolbar.dart client/lib/pages/usage/widgets/usage_table_toolbar.dart client/test/pages/system/log_viewer_test.dart
git commit -m "style(toolbars): use the search pill in git graph, logs, and usage"
```

---

### Task 11: Settings, vault, provider, full-disk, and select search fields

**Files:**
- Modify: `client/lib/pages/config/shortcuts_config_section.dart`
- Modify: `client/lib/pages/vault/vault_page.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_list_panel.dart`
- Modify: `client/packages/shared_ui/lib/src/components/select/tp_select_search_field.dart`
- Modify: `client/packages/shared_ui/lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart`
- Test: `client/test/widgets/search/tp_select_search_field_test.dart`

**Interfaces:**
- Consumes: `tpSearchPillDecoration`, `tpSearchPillRadius` (Task 1).
- Produces: no new API.

- [ ] **Step 1: Write the failing select test**

Create `client/test/widgets/search/tp_select_search_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('TpSelectSearchField uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpSelectSearchField(
            controller: controller,
            focusNode: focus,
            hintText: 'Search',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/search/tp_select_search_field_test.dart`

Expected: FAIL — the current radius is 6.

- [ ] **Step 3: Migrate the select search field**

In `client/packages/shared_ui/lib/src/components/select/tp_select_search_field.dart`:

```dart
import '../input/tp_search_pill.dart';
```

Replace the whole `InputDecoration` with:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: widget.hintText,
  suffixIcon: hasQuery
      ? TpIconButton(
          icon: Icons.clear,
          compact: true,
          size: TpIconButton.kCompactSize,
          onTap: _clear,
        )
      : null,
),
```

Remove the now-unused `spacing` local and the `tp_theme.dart` import if it becomes unused. Keep the controller listener, `_clear`, and `textInputAction` unchanged.

- [ ] **Step 4: Migrate full-disk search**

In `client/packages/shared_ui/lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart`:

```dart
import '../../../input/tp_search_pill.dart';
```

Add the radius to `TpInput`:

```dart
TpInput(
  key: const Key('tp_full_disk_search_query'),
  controller: _queryController,
  borderRadius: tpSearchPillRadius,
  decoration: InputDecoration(
    hintText: strings.inputFileNameKeywordHint,
    prefixIcon: const Icon(Icons.search),
  ),
  onChanged: (value) => _query = value,
  onSubmitted: (_) => _performSearch(),
),
```

- [ ] **Step 5: Migrate shortcuts, vault, and provider fields**

`client/lib/pages/config/shortcuts_config_section.dart`:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: l10n.shortcutsSearchHint,
),
```

`client/lib/pages/vault/vault_page.dart`:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: l10n.vaultSearchHint,
),
```

`client/lib/widgets/app_provider/app_provider_list_panel.dart`:

```dart
decoration: tpSearchPillDecoration(
  context,
  hintText: l10n.filterProviders,
),
```

Keep every controller, `onChanged`, clear action, and surrounding button unchanged. `shared_ui` is already imported in these three files; if not, add `import 'package:shared_ui/shared_ui.dart';`.

- [ ] **Step 6: Run the affected tests**

Run:

```bash
cd client
dart run tool/run_tests.dart test/widgets/search/tp_select_search_field_test.dart test/pages/config/shortcuts_config_section_test.dart test/pages/vault/ test/pages/managed_providers/managed_provider_management_page_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the submodule and the pointer bump**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/shared_ui
git add lib/src/components/select/tp_select_search_field.dart lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart
git commit -m "style(shared_ui): use the search pill in select and full-disk search"

cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui client/lib/pages/config/shortcuts_config_section.dart client/lib/pages/vault/vault_page.dart client/lib/widgets/app_provider/app_provider_list_panel.dart client/test/widgets/search/tp_select_search_field_test.dart
git commit -m "style(settings): use the search pill in settings, vault, and provider filters"
```

---

### Task 12: Full verification

**Files:** none.

- [ ] **Step 1: Run the analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues.

- [ ] **Step 2: Run the affected test suite**

```bash
cd client
dart run tool/run_tests.dart \
  test/theme/tp_search_pill_test.dart \
  test/widgets/find/ \
  test/pages/chat/session_chat_view_find_test.dart \
  test/widgets/workbench/code_editor_find_panel_test.dart \
  test/widgets/workbench/markdown_preview_find_bar_test.dart \
  test/widgets/workspace_terminal/workspace_terminal_find_host_test.dart \
  test/widgets/right_tools/search_panel_test.dart \
  test/widgets/search/ \
  test/widgets/catalog/ \
  test/widgets/home_workspace/workspaces_filter_field_test.dart \
  test/pages/home_workspace/workspace/ \
  test/pages/team_hub/ \
  test/pages/expert_hub/ \
  test/pages/plugins/plugin_discovery_section_test.dart \
  test/pages/git_graph/ \
  test/pages/system/log_viewer_test.dart \
  test/pages/usage/ \
  test/pages/config/shortcuts_config_section_test.dart \
  test/pages/vault/ \
  test/pages/workspace_search_dialog_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run the full suite once, in the background**

Run: `cd client && dart run tool/run_tests.dart`

Expected: PASS. Do not claim completion until this command exits successfully.

- [ ] **Step 4: Manual visual checklist**

Run the app (`dart run tool/run_app.dart` or the repo's documented launch command) and check both light and dark themes:

- Chat find bar: pill when no results, 16-radius card when results show; counter, up/down, close, Aa/ab/.* all still work.
- Editor find: pill for find-only; card when the replace row expands; replace/replace-all work.
- Markdown preview find: pill, Enter/Shift+Enter/Escape work.
- Terminal find: pill, status text appears, Ctrl+Shift+F/F3/Shift+F3/Escape work.
- Right-tools Search: query/replace/include/exclude fields are standalone pills; search/replace work.
- Workspace search dialog (Mod+F): field is a pill in both `all` and `content` modes; results render.
- File tree filter, workspaces list filter, skills/plugins/MCP headers, team/expert hubs, team picker, Git commit search, branch filter menu, log viewer, usage table, shortcuts settings, Vault, provider list, full-disk search, and dropdown search all show the pill.
- Narrow/mobile widths do not overflow, and pill corners do not clip icons or text.

- [ ] **Step 5: Final commit (only if manual fixes were needed)**

If the checklist required code adjustments, commit them with a focused message, then re-run Steps 1–3.
