# Long Model / Preset Name Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every long model/preset name that gets visually truncated reveal its full text via a single shared_ui primitive, adaptive on desktop (hover) and mobile (long-press).

**Architecture:** One reusable `TpEllipsisText` in `shared_ui` measures overflow with `LayoutBuilder` + `TextPainter` and wraps the text in a platform-adaptive Material `Tooltip` **only when it actually overflows**. It replaces the raw `Text` in `TpSelect` headers/list rows (fixes all dropdowns), the preset manage-list rows, and the compose chip label. Spec: `docs/superpowers/specs/2026-08-18-long-model-name-display-design.md`.

**Tech Stack:** Flutter (Dart), `shared_ui` package (Tp design system), `flutter_test`.

## Global Constraints

- Tooltips must use Material `Tooltip` (platform-adaptive: hover on desktop / long-press on touch) — **not** the hover-only `TpTooltip`.
- Tooltip appears only when the text overflows at the requested `maxLines`; a short label renders as a plain `Text` with no `Tooltip`.
- No behavior change for caller-provided `itemBuilder`/`listItemBuilder` rows in `TpSelect` — only the fallback `itemLabel` path changes.
- shared_ui tests run from `client/packages/shared_ui`; app-side tests run from `client/`.
- Do NOT touch the in-progress credential-login WIP files (`app_provider_cubit.dart`, `provider_credential_action_bar.dart`, `credential_login_progress.dart`, `provider_credential_device_code_panel.dart`). If `flutter test` fails to compile because of those files mid-edit, wait and re-run; never modify them.
- Commit after each task. Message style follows the repo: `feat(shared_ui): ...`, `feat(ui): ...`.

---

### Task 1: `TpEllipsisText` primitive (shared_ui)

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/text/tp_ellipsis_text.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (add export)
- Test: `client/packages/shared_ui/test/components/text/tp_ellipsis_text_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `TpEllipsisText({required String text, TextStyle? style, int? maxLines, TextAlign? textAlign, TextDirection? textDirection, TextOverflow? overflow, bool softWrap})`. Renders an ellipsized `Text`; wraps in `Tooltip(message: text)` only when overflowed. Later tasks use `TpEllipsisText(label, style: ..., maxLines: n)`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/text/tp_ellipsis_text_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

Widget _wrap(Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
  return MaterialApp(
    theme: ThemeData(colorScheme: scheme, useMaterial3: true),
    home: Scaffold(body: child),
  );
}

void main() {
  const long = 'deepseek-v4-pro[1m]-very-long-model-name-that-must-overflow';

  testWidgets('long text ellipsizes and wraps in Tooltip with full text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 120,
          child: TpEllipsisText(long, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );

    final tooltip = find.byType(Tooltip);
    expect(tooltip, findsOneWidget);
    expect(tester.widget<Tooltip>(tooltip).message, long);

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('short text renders plain Text and no Tooltip', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 400,
          child: TpEllipsisText('short-model', style: const TextStyle(fontSize: 16)),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
    expect(find.text('short-model'), findsOneWidget);
  });

  testWidgets('unbounded maxLines never adds a Tooltip', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 120,
          child: TpEllipsisText(
            long,
            maxLines: null,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/packages/shared_ui`):

```bash
flutter test test/components/text/tp_ellipsis_text_test.dart
```

Expected: FAIL — `TpEllipsisText` is not exported (`TpEllipsisText` not found).

- [ ] **Step 3: Write the implementation**

Create `client/packages/shared_ui/lib/src/components/text/tp_ellipsis_text.dart`:

```dart
import 'package:flutter/material.dart';

/// A label that ellipsizes at [maxLines] and, only when the text actually
/// overflows its bounds, reveals the full content in a platform-adaptive
/// [Tooltip] (hover on desktop, long-press on touch devices).
///
/// Prefer this over a raw `Text(overflow: TextOverflow.ellipsis)` wherever a
/// truncated label must stay discoverable (model names, preset names, …).
class TpEllipsisText extends StatelessWidget {
  const TpEllipsisText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.textDirection,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final TextOverflow overflow;
  final bool softWrap;

  bool _overflows(BuildContext context, double width) {
    final max = maxLines;
    if (max == null || max <= 0) return false;
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textDirection: textDirection ?? Directionality.of(context),
      textAlign: textAlign ?? TextAlign.start,
      maxLines: max,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width.isFinite ? width : double.infinity);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final rendered = Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!_overflows(context, width)) return rendered;
      return Tooltip(message: text, child: rendered);
    });
  }
}
```

Add the export to `client/packages/shared_ui/lib/shared_ui.dart` (alphabetical, after `src/components/tab/...` entries):

```dart
export 'src/components/text/tp_ellipsis_text.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/packages/shared_ui`):

```bash
flutter test test/components/text/tp_ellipsis_text_test.dart
```

Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/text/tp_ellipsis_text.dart \
        client/packages/shared_ui/lib/shared_ui.dart \
        client/packages/shared_ui/test/components/text/tp_ellipsis_text_test.dart
git commit -m "feat(shared_ui): add TpEllipsisText — ellipsized label with overflow-only Tooltip"
```

---

### Task 2: Use `TpEllipsisText` in `TpSelect` header and list rows

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/select/tp_select.dart` (the final `Text` fallback in `_buildItemChild`)
- Test: `client/packages/shared_ui/test/components/select/tp_select_test.dart`

**Interfaces:**
- Consumes: `TpEllipsisText` from Task 1.
- Produces: `TpSelect<T>` renders its header and menu row text (the `itemLabel` path) through `TpEllipsisText`; custom `itemBuilder`/`listItemBuilder` rows are unchanged.

- [ ] **Step 1: Write the failing tests**

Append to `client/packages/shared_ui/test/components/select/tp_select_test.dart` (inside `main()`):

```dart
group('TpSelect long labels', () {
  const longName = 'deepseek-v4-pro[1m]-a-very-long-model-name-overflow';

  testWidgets('closed header shows a Tooltip with the full item label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 160,
          child: TpSelect<String>(
            items: const [longName],
            initialItem: longName,
            searchable: false,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final tooltip = find.byType(Tooltip);
    expect(tooltip, findsOneWidget);
    expect(tester.widget<Tooltip>(tooltip).message, longName);
  });

  testWidgets('short header item does not show a Tooltip', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: TpSelect<String>(
            items: const ['sonnet'],
            initialItem: 'sonnet',
            searchable: false,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('long open-menu row shows a Tooltip with the full label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 160,
          child: TpSelect<String>(
            items: const ['sonnet', longName],
            searchable: false,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TpSelect<String>));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsWidgets);
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    expect(messages, contains(longName));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/packages/shared_ui`):

```bash
flutter test test/components/select/tp_select_test.dart
```

Expected: the three new tests FAIL (`Tooltip` not found — `pumpWidget` may throw «Tooltip was used after its widget was disposed» or the finds assert 0).

- [ ] **Step 3: Implement**

In `client/packages/shared_ui/lib/src/components/select/tp_select.dart`, replace the fallback in `_buildItemChild` (currently the trailing `return Text(...)`):

```dart
    final key = widget.listItemKey?.call(item);
    return TpEllipsisText(
      widget.itemLabel!(item),
      key: key,
      maxLines: maxLines,
      style: style,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/packages/shared_ui`):

```bash
flutter test test/components/select/tp_select_test.dart
```

Expected: PASS — all existing + new tests green.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/select/tp_select.dart \
        client/packages/shared_ui/test/components/select/tp_select_test.dart
git commit -m "feat(shared_ui): ellipsize + tooltip TpSelect itemLabel rows via TpEllipsisText"
```

---

### Task 3: Preset manage-list row — truncated name + summary with full-text Tooltip

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart` (`_PresetRow.build`)
- Test: `client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`

**Interfaces:**
- Consumes: `_PresetRow(preset)` — unchanged; `TpEllipsisText` from Task 1.
- Produces: manage-list rows that render name and summary on one line each, revealing full text via Tooltip.

- [ ] **Step 1: Write the failing flow test**

Append to `client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`—a new test that seeds a preset with a long name and checks the manage list shows it truncated with a full-text Tooltip. Reuse the existing `fs`, `repo`, `cubit`, `appProviderCubit`, `seedPreset()`, `seedProviderCatalog()`, `pumpManageDialog()` helpers from that file. Add:

```dart
  testWidgets('manage list ellipsizes long preset name and reveals full text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longName = 'deepseek-v4-pro[1m]-very-long-preset-name-overflow';
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([
        CliPreset(
          id: 'preset-long',
          name: longName,
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet-4-5',
          createdAt: 1,
          updatedAt: 1,
        ).toJson(),
      ]),
    );
    await seedProviderCatalog();
    await cubit.load();

    final l10n = AppLocalizations.of(contextForManageDialog(tester));
    await tester.pumpWidget(manageDialogApp(tester));

    expect(find.text(longName), findsOneWidget);
    final tooltip = find.byType(Tooltip);
    expect(tooltip, findsWidgets);
    final messages = tester
        .widgetList<Tooltip>(tooltip)
        .map((t) => t.message)
        .toList();
    expect(messages, contains(longName));
    expect(messages, anyElement(contains('claude-sonnet-4-5')));
  });

  testWidgets('edit dialog model dropdown ellipsizes a long model id with '
      'full-text Tooltip', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longModel = 'deepseek-v4-pro[1m]-a-very-long-model-id-overflow';
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([
        CliPreset(
          id: 'preset-long-model',
          name: 'long-model preset',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: longModel,
          createdAt: 1,
          updatedAt: 1,
        ).toJson(),
      ]),
    );
    await seedProviderCatalog();
    await cubit.load();
    await appProviderCubit.load(reconcileCredentials: false);
    await tester.pumpWidget(manageDialogApp(tester));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // The model picker header must truncate the long id…
    final picker = modelSelectFinder();
    expect(picker, findsOneWidget);
    // …and its Tooltip must carry the full model id.
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    expect(
      tooltips.map((t) => t.message).toList(),
      anyElement(contains(longModel)),
    );
  });
```

Refactor the helper block in that file so both the existing tests and the new one share the dialog host. Move the widget-construction part of `pumpManageDialog` into two helpers (keep the existing tests compiling):

```dart
  BuildContext contextForManageDialog(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first);

  Widget manageDialogApp(WidgetTester tester) => CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: appProviderCubit),
            BlocProvider.value(value: cubit),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: CliPresetsManageDialog()),
          ),
        ),
      );
```

and `pumpManageDialog` becomes:

```dart
  Future<void> pumpManageDialog(WidgetTester tester) async {
    await seedPreset();
    await seedProviderCatalog();
    await cubit.load();
    await appProviderCubit.load(reconcileCredentials: false);
    await tester.pumpWidget(manageDialogApp(tester));
    await tester.pump();
  }
```

(`jsonEncode` for a single preset requires wrapping the map in a list — the code above already does `[ ... ]`.)

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`):

```bash
flutter test test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart
```

Expected: the new test FAILS — the long name Text currently wraps to two lines and no `Tooltip` exists in the manage-list rows.

- [ ] **Step 3: Implement**

In `client/lib/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart`, inside `_PresetRow.build`, replace:

```dart
                Text(
                  preset.name,
                  style: styles.lgColored(cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cliName · $subtitle',
                  style: styles.smColored(cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
```

with:

```dart
                TpEllipsisText(
                  preset.name,
                  style: styles.lgColored(cs.onSurface),
                ),
                const SizedBox(height: 2),
                TpEllipsisText(
                  '$cliName · $subtitle',
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
```

`TpEllipsisText` is already visible via the file's existing `package:shared_ui/shared_ui.dart` import.

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`):

```bash
flutter test test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart
```

Expected: PASS — all tests (rename, model, short-window, new long-name) green.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart \
        client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart
git commit -m "feat(ui): ellipsize preset manage rows and reveal full text via TpEllipsisText"
```

---

### Task 4: Compose preset chip — capped width labels with full-text Tooltip

**Files:**
- Modify: `client/lib/widgets/compose/compose_menu_chip.dart` (`ComposeToolbarChip`)
- Test: `client/test/widgets/compose/compose_model_preset_chip_test.dart`

**Interfaces:**
- Consumes: `TpEllipsisText` from Task 1.
- Produces: `ComposeToolbarChip({String label, double? labelMaxWidth, ...})` — new optional `labelMaxWidth` (defaults to 200) capping the label; used by both landing and session-chat compose chips.

- [ ] **Step 1: Write the failing flow test**

Append to `client/test/widgets/compose/compose_model_preset_chip_test.dart`:

```dart
  group('ComposeToolbarChip long label', () {
    testWidgets('caps label width and reveals full text via Tooltip', (
      tester,
    ) async {
      const label = 'deepseek-v4-pro[1m]-very-long-preset-name';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ComposeToolbarChip(
                label: label,
                labelMaxWidth: 120,
              ),
            ),
          ),
        ),
      );

      // Chip did not grow to full label width.
      final chipSize = tester.getSize(find.byType(ComposeToolbarChip));
      expect(chipSize.width, lessThan(200));

      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);
      expect(tester.widget<Tooltip>(tooltip).message, label);
    });

    testWidgets('short label shows no Tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComposeToolbarChip(
              label: 'sonnet',
              labelMaxWidth: 120,
            ),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
    });
  });
```

Add the import for `ComposeToolbarChip` (same source file as `ComposeModelPresetChip`, so the existing `compose_model_preset_chip.dart` import already covers it).

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`):

```bash
flutter test test/widgets/compose/compose_model_preset_chip_test.dart
```

Expected: the new tests FAIL — `ComposeToolbarChip` has no `labelMaxWidth` param (compile error) and the raw `Text` emits no `Tooltip`.

- [ ] **Step 3: Implement**

In `client/lib/widgets/compose/compose_menu_chip.dart`:

1. Add the constructor field:

```dart
  const ComposeToolbarChip({
    required this.palette,
    required this.icon,
    required this.label,
    this.leading,
    this.onTap,
    this.labelMaxWidth = 200,
    super.key,
  });
  ...
  final double labelMaxWidth;
```

2. In `build`, replace the label `Text`:

```dart
              Text(label, style: labelStyle),
```

with:

```dart
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: TpEllipsisText(label, style: labelStyle),
              ),
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`):

```bash
flutter test test/widgets/compose/compose_model_preset_chip_test.dart
```

Expected: PASS — existing + new tests green.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_menu_chip.dart \
        client/test/widgets/compose/compose_model_preset_chip_test.dart
git commit -m "feat(ui): cap compose preset chip label width with full-text Tooltip"
```

---

### Task 5: Regression sweep and lint

**Files:**
- Test: none new — run existing suites.

**Interfaces:**
- Consumes: all prior tasks.

- [ ] **Step 1: Run the full affected suites**

Run (from `client/`):

```bash
flutter test test/cubits/cli_presets_cubit_test.dart \
  test/pages/onboarding/default_preset_step_test.dart \
  test/pages/config/ai_features_config_section_test.dart \
  test/pages/home_workspace/workspace/ \
  test/pages/team_config/team_launch_defaults_configured_test.dart \
  test/pages/team_config/team_member_config_form_test.dart \
  test/widgets/compose/
```

Expected: all PASS.

Run (from `client/packages/shared_ui`):

```bash
flutter test
```

Expected: all PASS.

- [ ] **Step 2: Analyze the changed files**

Run (from `client/`):

```bash
flutter analyze lib/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart \
  lib/widgets/compose/compose_menu_chip.dart \
  test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart \
  test/widgets/compose/compose_model_preset_chip_test.dart
```

Run (from `client/packages/shared_ui`):

```bash
flutter analyze lib/src/components/text/tp_ellipsis_text.dart \
  lib/src/components/select/tp_select.dart \
  test/components/text/tp_ellipsis_text_test.dart \
  test/components/select/tp_select_test.dart
```

Expected: `No issues found!` in both.

- [ ] **Step 3: Manual smoke (optional)**

Build/run the app, open 管理预设 → 编辑, confirm a long model like `deepseek-v4-pro[1m]` shows `…` in the picker header and the full id on hover (desktop) / long-press (mobile); confirm the landing compose chip caps its width.