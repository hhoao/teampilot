# Form Validation Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every broken form shows why saving failed — inline red borders + error text under invalid fields, validated on click — via a full sweep migrating forms onto the existing `TpForm` infrastructure plus a new `TpSelectFormField`.

**Architecture:** Fill one shared_ui gap (`TpSelect` error state + `TpSelectFormField`), add shared l10n messages, then migrate 10 forms from silent-return/disabled-button patterns to `TpForm.validate()` on click. Spec: `docs/superpowers/specs/2026-08-26-form-validation-feedback-design.md`.

**Tech Stack:** Flutter (client/), flutter_bloc, shared_ui package (`client/packages/shared_ui`), flutter_gen_l10n (`client/lib/l10n/app_en.arb` + `app_zh.arb`).

## Global Constraints

- All app paths relative to `client/`; shared_ui paths relative to `client/packages/shared_ui/`.
- Never add comments to code unless the surrounding code already has them (repo convention: comments only where they explain non-obvious decisions; match file style).
- User-facing strings ONLY via l10n arb files (`client/lib/l10n/app_en.arb`, `app_zh.arb`) accessed with `context.l10n.<key>`; regenerate with `cd client && flutter gen-l10n`.
- Design primitives belong in `packages/shared_ui` as `Tp*`; do NOT add controls under `client/lib/widgets/`.
- No `print`; diagnostics go through `AppLogger` (not needed in this plan).
- Async/save failures surface via `AppToast.show(context, message:, variant: TpToastVariant.error)` (existing pattern) — never raw `SnackBar`.
- Structural disable (async `_saving`, empty choice lists) is allowed; **input-driven** disabling of save buttons must be removed.
- Verify commands: single file `cd client && flutter test <path>`; shared_ui `cd client/packages/shared_ui && flutter test <path>`; full gate `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Commit after every task; never commit unrelated files.

---

### Task 1: shared_ui — `TpSelect` error state

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/select/tp_select_decoration.dart`
- Modify: `client/packages/shared_ui/lib/src/components/select/tp_select.dart`
- Test: `client/packages/shared_ui/test/components/select/tp_select_test.dart`

**Interfaces:**
- Consumes: existing `TpSelectDecoration.buttonDecoration({required bool menuOpen, bool isHovering})`.
- Produces: `TpSelect.hasError` (`final bool hasError`, default `false`); `TpSelectDecoration.errorBorderColor` (`final Color?`); `buttonDecoration({required bool menuOpen, bool isHovering = false, bool hasError = false})`; `TpSelectDecorations.themed(..., bool hasError = false)` setting `errorBorderColor: cs.error`. Task 2 relies on all three.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `client/packages/shared_ui/test/components/select/tp_select_test.dart` (after the last closing group brace, before `main()`'s closing brace):

```dart
  group('TpSelect error state', () {
    Color triggerBorderColor(WidgetTester tester, ColorScheme scheme) {
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GestureDetector),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      return (decoration.border! as Border).top.color;
    }

    testWidgets('hasError draws the error-colored trigger border', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
            child: Scaffold(
              body: TpSelect<String>(
                items: const ['alpha', 'beta'],
                itemLabel: (item) => item,
                hasError: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(triggerBorderColor(tester, scheme), scheme.error);
    });

    testWidgets('default trigger border is not the error color', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme, useMaterial3: true),
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
            child: Scaffold(
              body: TpSelect<String>(
                items: const ['alpha', 'beta'],
                itemLabel: (item) => item,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(triggerBorderColor(tester, scheme), isNot(scheme.error));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/shared_ui && flutter test test/components/select/tp_select_test.dart`
Expected: FAIL — compile error "hasError" isn't defined for `TpSelect`.

- [ ] **Step 3: Implement**

In `client/packages/shared_ui/lib/src/components/select/tp_select_decoration.dart`:

3a. Add the field to `TpSelectDecoration` (after `this.listItemBorderRadius,` in the constructor and after `final BorderRadius? listItemBorderRadius;` in the fields):

```dart
    this.errorBorderColor,
```

```dart
  /// Border color applied to the closed trigger while the select is in an
  /// error state. When null the regular [closedBorder] is kept.
  final Color? errorBorderColor;
```

3b. Change `buttonDecoration` to accept and honor `hasError`:

```dart
  BoxDecoration buttonDecoration({
    required bool menuOpen,
    bool isHovering = false,
    bool hasError = false,
  }) {
    Color fill = menuOpen ? expandedFillColor : closedFillColor;
    if (!menuOpen && isHovering && buttonHoverColor != null) {
      fill = buttonHoverColor!;
    }
    BoxBorder border = menuOpen ? expandedBorder : closedBorder;
    if (hasError && !menuOpen && errorBorderColor != null) {
      border = Border.all(color: errorBorderColor!);
    }
    return BoxDecoration(
      color: fill,
      border: border,
      borderRadius: menuOpen ? expandedBorderRadius : closedBorderRadius,
    );
  }
```

3c. In `TpSelectDecorations.themed`, add the parameter to the signature (anywhere among the named params, e.g. after `bool? listItemBorderRadius,` is wrong — it's a double; add after `double? listItemBorderRadius,` the line `bool hasError = false,`):

```dart
    bool hasError = false,
```

and change the returned `closedBorder` default plus pass `errorBorderColor`:

```dart
      closedBorder: closedBorder ??
          Border.all(
            color: hasError ? cs.error : outlineVariant,
            width: 1,
          ),
```

and add to the `return TpSelectDecoration(` argument list (e.g. after `listItemSelectedColor: selectedBg,`):

```dart
      errorBorderColor: cs.error,
```

In `client/packages/shared_ui/lib/src/components/select/tp_select.dart`:

3d. Add the constructor param (after `this.enabled = true,`) and field (after `final bool enabled;`):

```dart
    this.hasError = false,
```

```dart
  /// Draws the trigger border in the error color (validation feedback).
  final bool hasError;
```

3e. In `build()` change the decoration resolution to pass `hasError`:

```dart
    final deco =
        widget.decoration ??
        TpSelectDecorations.themed(
          context,
          suffixIconSize: context.tpIconSizes.md,
          hasError: widget.hasError,
        );
```

3f. In `_buildPopover` change the `buttonDecoration` call:

```dart
            decoration: deco.buttonDecoration(
              menuOpen: isOpen,
              isHovering: _isHovering,
              hasError: widget.hasError,
            ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client/packages/shared_ui && flutter test test/components/select/tp_select_test.dart`
Expected: PASS (all tests, including pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/select/tp_select_decoration.dart client/packages/shared_ui/lib/src/components/select/tp_select.dart client/packages/shared_ui/test/components/select/tp_select_test.dart
git commit -m "feat(shared_ui): add error state to TpSelect"
```

---

### Task 2: shared_ui — `TpSelectFormField<T>`

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/select/tp_select_form_field.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (add one export line after `export 'src/components/select/tp_select_decoration.dart';`)
- Test: Create `client/packages/shared_ui/test/components/select/tp_select_form_field_test.dart`

**Interfaces:**
- Consumes: `TpFormField` / `TpFormFieldState` (builder receives `TpFormFieldState<TpFormField<T>, T>` exposing `value`, `hasError`, `enabled`, `didChange`, `focusNode`); `TpSelect` incl. `hasError` from Task 1.
- Produces: `TpSelectFormField<T extends Object>` constructor params `key, id, initialValue, focusNode, label, error, description, validator, onSaved, onChanged, enabled, autovalidateMode, restorationId, layoutStyle, labelWidth, required items, itemLabel, itemBuilder, listItemBuilder, hintText, decoration, overlayHeight, searchable = true, searchMinItems = 8, onEmptyTap`. Tasks 4, 5, 8, 9 instantiate it with `id:`, `items:`, `initialValue:`, `hintText:`, `validator:`, `onChanged:`, `itemLabel:` / `itemBuilder:`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/select/tp_select_form_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

Widget _wrap(Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
  return MaterialApp(
    theme: ThemeData(colorScheme: scheme, useMaterial3: true),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders the initial value and reports selections', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        TpSelectFormField<String>(
          id: 'pick',
          initialValue: 'alpha',
          items: const ['alpha', 'beta'],
          itemLabel: (item) => item,
          onChanged: (value) => selected = value,
        ),
      ),
    );

    expect(find.text('alpha'), findsOneWidget);

    await tester.tap(find.byType(TpSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta').last);
    await tester.pumpAndSettle();

    expect(selected, 'beta');
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('validates on form validate and clears after fixing', (
    tester,
  ) async {
    final formKey = GlobalKey<TpFormState>();
    Object? submitted;
    await tester.pumpWidget(
      _wrap(
        TpForm(
          key: formKey,
          child: Column(
            children: [
              TpSelectFormField<String>(
                id: 'pick',
                items: const ['alpha', 'beta'],
                hintText: 'pick one',
                itemLabel: (item) => item,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),
              TextButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    submitted = formKey.currentState!.value['pick'];
                  }
                },
                child: const Text('submit'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('submit'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    expect(submitted, isNull);

    await tester.tap(find.byType(TpSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta').last);
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNothing);

    await tester.tap(find.text('submit'));
    await tester.pumpAndSettle();

    expect(submitted, 'beta');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/shared_ui && flutter test test/components/select/tp_select_form_field_test.dart`
Expected: FAIL — `TpSelectFormField` is not exported / undefined.

- [ ] **Step 3: Implement**

Create `client/packages/shared_ui/lib/src/components/select/tp_select_form_field.dart`:

```dart
import 'package:flutter/material.dart';

import '../form/tp_form_field.dart';
import 'tp_select.dart';
import 'tp_select_decoration.dart';

/// [TpFormField] wrapping [TpSelect]; label / error / description come from
/// [TpFormFieldLayout], not from the trigger itself. While the field is in an
/// error state the trigger border turns red and the message renders below it.
class TpSelectFormField<T extends Object> extends TpFormField<T> {
  TpSelectFormField({
    super.key,
    super.id,
    super.initialValue,
    super.focusNode,
    super.label,
    super.error,
    super.description,
    super.validator,
    super.onSaved,
    super.onChanged,
    super.enabled,
    super.autovalidateMode,
    super.restorationId,
    super.layoutStyle,
    super.labelWidth,
    required this.items,
    this.itemLabel,
    this.itemBuilder,
    this.listItemBuilder,
    this.hintText,
    this.decoration,
    this.overlayHeight,
    this.searchable = true,
    this.searchMinItems = 8,
    this.onEmptyTap,
  }) : super(
          builder: (state) {
            return Focus(
              focusNode: state.focusNode,
              child: TpSelect<T>(
                items: items,
                initialItem: state.value,
                itemLabel: itemLabel,
                itemBuilder: itemBuilder,
                listItemBuilder: listItemBuilder,
                hintText: hintText,
                decoration: decoration,
                overlayHeight: overlayHeight,
                enabled: state.enabled,
                searchable: searchable,
                searchMinItems: searchMinItems,
                onEmptyTap: onEmptyTap,
                hasError: state.hasError,
                onChanged: state.didChange,
              ),
            );
          },
        );

  final List<T> items;
  final String Function(T item)? itemLabel;
  final Widget Function(BuildContext context, T item)? itemBuilder;
  final Widget Function(BuildContext context, T item)? listItemBuilder;
  final String? hintText;
  final TpSelectDecoration? decoration;
  final double? overlayHeight;
  final bool searchable;
  final int searchMinItems;
  final VoidCallback? onEmptyTap;

  @override
  TpFormFieldState<TpSelectFormField<T>, T> createState() =>
      TpFormFieldState<TpSelectFormField<T>, T>();
}
```

In `client/packages/shared_ui/lib/shared_ui.dart`, insert after the `tp_select_decoration.dart` export line:

```dart
export 'src/components/select/tp_select_form_field.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client/packages/shared_ui && flutter test test/components/select/tp_select_form_field_test.dart test/components/select/tp_select_test.dart test/components/form/tp_form_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/select/tp_select_form_field.dart client/packages/shared_ui/lib/shared_ui.dart client/packages/shared_ui/test/components/select/tp_select_form_field_test.dart
git commit -m "feat(shared_ui): add TpSelectFormField with validation support"
```

---

### Task 3: l10n — shared validation messages

**Files:**
- Modify: `client/lib/l10n/app_en.arb` (insert immediately after the `"automationsValidationRequired"` entry, around line 3059)
- Modify: `client/lib/l10n/app_zh.arb` (insert immediately after the `"automationsValidationRequired"` entry, around line 2623)

**Interfaces:**
- Produces: `context.l10n.formFieldRequired`, `context.l10n.teamModeRequired`, `context.l10n.hookSaveFailed`. Used by Tasks 4–8, 10, 11, 13.

- [ ] **Step 1: Add the entries**

`app_en.arb`:

```json
  "automationsValidationRequired": "Name and message are required",
  "formFieldRequired": "This field is required.",
  "teamModeRequired": "Choose a team mode first.",
  "hookSaveFailed": "Failed to save hook.",
```

(Only the three new lines are added; the `automationsValidationRequired` line is shown for placement.)

`app_zh.arb`:

```json
  "automationsValidationRequired": "名称和消息为必填项",
  "formFieldRequired": "此项为必填。",
  "teamModeRequired": "请先选择团队模式。",
  "hookSaveFailed": "保存 Hook 失败。",
```

- [ ] **Step 2: Regenerate and verify**

Run: `cd client && flutter gen-l10n && grep -rl "formFieldRequired" --include="*.dart" lib | head -3`
Expected: at least one generated `app_localizations*.dart` file lists `formFieldRequired` (the getter must exist for `context.l10n.formFieldRequired` to compile).

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "feat(l10n): add shared form validation messages"
```

(Include any regenerated localization files under `client/lib/l10n/` that `git status` reports as modified — some repos vendor them.)

---

### Task 4: Model preset dialog (`cli_preset_edit_dialog.dart`)

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart`
- Test: `client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`

**Interfaces:**
- Consumes: `TpForm`/`TpFormState` (`GlobalKey<TpFormState>()`, `.validate()`), `TpInputFormField`, `TpSelectFormField` (Task 2), `context.l10n.formFieldRequired` / `selectProvider` (Task 3 / existing).
- Produces: reference implementation of the migrate pattern used by Tasks 5–11.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`, first parameterize the seeders. Replace the existing `seedPreset` and `pumpManageDialog` helpers with:

```dart
  Future<void> seedPreset({
    String name = 'Old Name',
    String provider = 'anthropic',
    String model = 'claude-sonnet-4-5',
  }) async {
    final preset = CliPreset(
      id: 'preset-1',
      name: name,
      cli: CliTool.claude,
      provider: provider,
      model: model,
      effort: 'high',
      createdAt: 1,
      updatedAt: 1,
    );
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([preset.toJson()]),
    );
  }
```

```dart
  Future<void> pumpManageDialog(
    WidgetTester tester, {
    String presetName = 'Old Name',
    String presetProvider = 'anthropic',
  }) async {
    await seedPreset(name: presetName, provider: presetProvider);
    await seedProviderCatalog();
    await cubit.load();
    await appProviderCubit.load(reconcileCredentials: false);
    await tester.pumpWidget(
      CliToolRegistryScope(
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
      ),
    );
    await tester.pump();
  }
```

Then add this test inside `main()` (after the last existing `testWidgets`):

```dart
  testWidgets('saving with empty name shows inline error and keeps dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.formFieldRequired), findsOneWidget);
    expect(cubit.state.presets.single.name, 'Old Name');

    await tester.enterText(find.byType(TextField), 'Fixed Name');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(cubit.state.presets.single.name, 'Fixed Name');
  });

  testWidgets('saving without provider shows inline error and keeps dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester, presetName: 'No Provider', presetProvider: '');

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), 'Named Preset');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.selectProvider), findsOneWidget);
    expect(
      cubit.state.presets.map((p) => p.name),
      isNot(contains('Named Preset')),
    );
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart`
Expected: the two new tests FAIL (dialog closes silently on empty name / no error text appears); the three existing tests PASS.

- [ ] **Step 3: Implement the migration**

In `client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart`:

3a. Add the form key field to `_CliPresetEditDialogState` (above `late final TextEditingController _nameCtl;`):

```dart
  final _formKey = GlobalKey<TpFormState>();
```

3b. Replace `_save`'s silent gates with a validate gate:

```dart
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameCtl.text.trim();
    final providerId = _providerId.trim();
```

and use `providerId` in both cubit calls (replace `provider: _providerId,` with `provider: providerId,`). Everything below (update/add branches, pop) stays unchanged.

3c. Wrap the body Column in `TpForm` and swap the two editable controls. Change:

```dart
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
```

to:

```dart
        body: TpForm(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
```

(and close the extra paren where the Column ends — the `],\n        ),` before `footer:` becomes `],\n          ),\n        ),`).

Replace the name `TpPreferenceStack` body:

```dart
            TpPreferenceStack(
              title: l10n.workspaceCliPresetNameLabel,
              body: TpInputFormField(
                key: const Key('preset-name-field'),
                controller: _nameCtl,
                autofocus: !widget.isEditing,
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? l10n.formFieldRequired
                        : null,
              ),
              showDividerBelow: true,
            ),
```

Replace the provider `TpPreferenceRow` trailing `TpSelect<String>` (the one keyed `ValueKey('preset-provider-$_cli-$_providerId')`) with:

```dart
            TpPreferenceRow(
              title: l10n.provider,
              trailing: TpSelectFormField<String>(
                key: ValueKey('preset-provider-form-$_cli'),
                id: 'provider',
                items: providers.map((p) => p.id).toList()..sort(),
                initialValue: _providerId.isEmpty ? null : _providerId,
                hintText: l10n.selectProvider,
                onEmptyTap: () => _openProviderConfig(context),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? l10n.selectProvider
                        : null,
                onChanged: (value) {
                  setState(() {
                    _providerId = value ?? '';
                    _modelId = '';
                    _effortId = '';
                  });
                },
                itemLabel: (value) {
                  for (final p in providers) {
                    if (p.id == value) return p.name;
                  }
                  return value;
                },
                itemBuilder: providerDropdownItemBuilder(
                  providers: providers,
                  labelFor: (value) {
                    for (final p in providers) {
                      if (p.id == value) return p.name;
                    }
                    return value;
                  },
                ),
              ),
              showDividerBelow: hideModelPicker || showEffortPicker,
            ),
```

Keep the CLI select row exactly as-is (always has a value, sometimes locked).

3d. Enable the save button unconditionally:

```dart
            FilledButton(
              onPressed: _save,
              child: Text(l10n.save),
            ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/home_workspace/workspace/config/`
Expected: PASS (all preset-dialog tests including the three pre-existing ones). If another suite in that directory asserts a disabled save button for missing provider, update that expectation to the enabled-button + inline-error behavior following the new tests above.

- [ ] **Step 5: Manual smoke note**

`flutter analyze` cannot judge visuals: run the app once, open 工作区配置 → 模型预设 → 新建，click 保存 with empty fields, confirm red border + “此项为必填。” under 名称 and “请选择服务商” under 服务商， focus jumps to 名称.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart client/test/pages/home_workspace/workspace/config/cli_preset_edit_dialog_test.dart
git commit -m "feat(presets): validate model preset dialog inline on save"
```

---

### Task 5: LLM model edit dialog

**Files:**
- Modify: `client/lib/pages/llm_config/llm_model_edit_dialog.dart`

**Interfaces:**
- Consumes: same primitives as Task 4. Keeps public keys `AppKeys.modelNameDialogField` / `modelProviderField` / `modelModelIdField` working (moved onto the form-field wrappers; `tester.enterText` descends into descendant `EditableText`).

- [ ] **Step 1: Check key usages**

Run: `cd client && grep -rn "modelNameDialogField\|modelProviderField\|modelModelIdField" lib test --include="*.dart" | grep -v app_keys.dart`
If any usage types the finder as `TextField` (e.g. `tester.widget<TextField>(find.byKey(...))`), relax it to `find.byKey(...)` + `tester.widget<TextFormField>`-free access or `enterText` only — record each site you touch.

- [ ] **Step 2: Implement**

In `_LlmModelEditDialogState` (the state class is public `LlmModelEditDialogState`; add the field near the controllers):

```dart
  final _formKey = GlobalKey<TpFormState>();
```

Rewrite `build()`'s returned subtree (lines 66–142 region) as:

```dart
    return TpDialog(
      maxWidth: 400,
      child: TpForm(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: widget.title),
            const SizedBox(height: 16),
            TpInputFormField(
              key: AppKeys.modelNameDialogField,
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.modelName),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? l10n.formFieldRequired
                      : null,
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.provider,
                  style: TpTextStyles.of(context).mdSemibold,
                ),
                const SizedBox(height: 8),
                TpSelectFormField<String>(
                  key: AppKeys.modelProviderField,
                  id: 'provider',
                  items: providerNames,
                  initialValue: initialProvider,
                  hintText: l10n.provider,
                  decoration: deco,
                  validator: (value) =>
                      (value == null || value.isEmpty)
                          ? l10n.formFieldRequired
                          : null,
                  onChanged: (value) => setState(() => _provider = value ?? ''),
                  itemLabel: (value) => value,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TpInputFormField(
              key: AppKeys.modelModelIdField,
              controller: _modelController,
              decoration: InputDecoration(labelText: l10n.modelId),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: AppKeys.modelEnabledToggle,
              title: Text(l10n.enabled),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    final name = _nameController.text.trim();
                    Navigator.pop(
                      context,
                      LlmModelConfig(
                        id: isEditing ? widget.model!.id : name,
                        name: name,
                        provider: _provider,
                        model: _modelController.text.trim(),
                        enabled: _enabled,
                      ),
                    );
                  },
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
```

(`initialProvider` variable and `deco` stay as-is above the return.)

- [ ] **Step 3: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/`
Expected: analyze clean; every page suite passes, including any that reference the `AppKeys.model*` keys (fix per Step 1 notes if not).

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/llm_config/llm_model_edit_dialog.dart
git commit -m "feat(llm-config): validate model edit dialog inline on save"
```

---

### Task 6: New workspace dialog

**Files:**
- Modify: `client/lib/pages/home_workspace/home_new_workspace_dialog.dart`

**Interfaces:**
- Consumes: `TpForm`, `TpFormField<bool>` shrink-pattern (builder returns `SizedBox.shrink()`, validator reads state), existing l10n `workspacePrimaryPathRequired`.
- Produces: none downstream.

- [ ] **Step 1: Implement**

In `_HomeNewWorkspaceDialogState` add:

```dart
  final _formKey = GlobalKey<TpFormState>();
```

Replace `_submit` (lines 89–96) with:

```dart
  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final valid = _folders.where((f) => f.path.trim().isNotEmpty).toList();
    Navigator.of(context).pop((
      folders: List<WorkspaceFolder>.unmodifiable(valid),
      display: _nameController.text.trim(),
    ));
  }
```

In `build()`, wrap the dialog `Column` children area: change `child: Column(` (line 108) to

```dart
      child: TpForm(
        key: _formKey,
        child: Column(
```

(close the extra paren before the `TpDialog`'s closing `);`), and insert a validation slot between the picker and the name field — after the `WorkspaceCreateDirectoryPicker(...)` widget and its trailing `const SizedBox(height: 16),`, add:

```dart
          TpFormField<bool>(
            id: 'folders',
            builder: (_) => const SizedBox.shrink(),
            validator: (_) =>
                _folders.where((f) => f.path.trim().isNotEmpty).isEmpty
                    ? l10n.workspacePrimaryPathRequired
                    : null,
          ),
```

Enable the footer button (line 144):

```dart
              FilledButton(
                onPressed: _submit,
                child: Text(l10n.homeWorkspaceCreateWorkspace),
              ),
```

- [ ] **Step 2: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/home_workspace/`
Expected: clean; suites pass. Behavior check (manual or quick widget test if a suite exists for this dialog): with no directory chosen, clicking 创建 keeps the dialog open and shows “请先选择主目录。” under the picker; adding a folder clears it.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/home_new_workspace_dialog.dart
git commit -m "feat(workspace): validate new-workspace dialog inline on submit"
```

---

### Task 7: New team dialog

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
- Modify (one param): `_NameField` in the same file (lines 707–775)

**Interfaces:**
- Consumes: `TpForm`, `TpFormField<bool>` shrink-pattern, l10n `teamModeRequired` / `teamNameRequired` (existing) / `formFieldRequired`.
- Produces: none downstream.

- [ ] **Step 1: Implement state changes**

Add the form key; replace `_canCreate` machinery:

```dart
  final _formKey = GlobalKey<TpFormState>();
```

Delete the `bool _canCreate = false;` field. In `initState` keep the listener but rename its target:

```dart
    _nameController = TextEditingController()..addListener(_refreshValidation);
```

Replace `_syncCanCreate` (lines 118–127) with:

```dart
  void _refreshValidation() {
    if (mounted) setState(() {});
  }
```

Update the three `_syncCanCreate()` call sites (segmented picker `onChanged` line 344, native mode card `onTap` line 376, mixed mode card `onTap` line 394) to `_refreshValidation();`.

Replace `_submit` (lines 199–218) opening with:

```dart
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _teamNameForSubmit().trim();
    final mode = _mode;
    List<TeamRosterSlot>? roster;
```

(drop the two old guards `if (name.isEmpty) return;` and `if (mode == null) return;`).

Replace `_generateAndCreate`'s opening guard (line 231) with:

```dart
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (mode == null || _generating) return;
    final description = _aiDescription.trim();
```

(move `final mode = _mode;` above this; delete the old combined `if (mode == null || description.isEmpty || _generating) return;`).

Delete `_canGenerate` (lines 220–221).

- [ ] **Step 2: Implement build changes**

2a. Wrap `body`: change `final body = Column(` to

```dart
    final body = TpForm(
      key: _formKey,
      child: Column(
```

and close the extra paren where `body`'s Column ends (`],\n      );` becomes `],\n      ),\n    );`).

2b. Insert the mode validation slot directly after the `IntrinsicHeight(...)` mode-cards widget:

```dart
          TpFormField<bool>(
            id: 'mode',
            builder: (_) => const SizedBox.shrink(),
            validator: (_) => _mode == null ? l10n.teamModeRequired : null,
          ),
```

2c. Wrap the name field (inside the `if (_creationMethod == _TeamCreationMethod.custom) ...[` branch, replacing the bare `_NameField(controller: _nameController, onSubmitted: (_) => _submit(),)`):

```dart
            TpFormField<bool>(
              id: 'team-name',
              builder: (state) => _NameField(
                controller: _nameController,
                onSubmitted: (_) => _submit(),
                hasError: state.hasError,
              ),
              validator: (_) =>
                  (_creationMethod == _TeamCreationMethod.custom &&
                          _mode != null &&
                          _nameController.text.trim().isEmpty)
                      ? l10n.teamNameRequired
                      : null,
            ),
```

(The `<bool>` value is unused — only the validator matters. `state.hasError` paints the inner field red.)

2d. Insert the AI-description validation slot as the first child of the `else ...[` branch, above `HomeTeamGenerateSection(`:

```dart
            TpFormField<bool>(
              id: 'ai-description',
              builder: (_) => const SizedBox.shrink(),
              validator: (_) =>
                  _creationMethod == _TeamCreationMethod.ai &&
                          _aiDescription.trim().isEmpty
                      ? l10n.formFieldRequired
                      : null,
            ),
```

2e. Footer button — replace the `Builder(...)` enabled computation (lines 440–462) with:

```dart
              Builder(
                builder: (context) {
                  final isAi = _creationMethod == _TeamCreationMethod.ai;
                  return FilledButton(
                    onPressed: _generating
                        ? null
                        : (isAi ? _generateAndCreate : _submit),
                    child: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isAi
                                ? l10n.teamGenButton
                                : l10n.homeWorkspaceCreateTeam,
                          ),
                  );
                },
              ),
```

2f. Extend `_NameField` with the error flag. Constructor gains `required this.hasError` + `final bool hasError;`; its inner `TextField` decoration becomes:

```dart
                  decoration: InputDecoration(
                    hintText: l10n.homeWorkspaceNewTeamNameHint,
                    isDense: true,
                    errorText: hasError ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
```

- [ ] **Step 3: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/home_workspace/`
Expected: clean; suites pass. Manual check: 新建团队 with no mode chosen → clicking 创建 shows “请先选择团队模式。”; custom tab with empty name → “团队名称不能为空。” under the name card; AI tab with empty description → error under the textarea area.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart
git commit -m "feat(team): validate new-team dialog inline on submit"
```

---

### Task 8: Shared launch-fields widget + member launch config dialog

**Files:**
- Modify: `client/lib/widgets/cli_launch_config/cli_launch_custom_fields.dart`
- Modify: `client/lib/pages/team_config/team_member_launch_config_section.dart` (state `_MemberLaunchConfigureDialogState`, lines 278–581)

**Interfaces:**
- Produces: `CliLaunchCustomFields.providerHasError` (`final bool providerHasError`, default `false`) — consumed by Task 9.

- [ ] **Step 1: Add `providerHasError` to `CliLaunchCustomFields`**

Constructor gains (next to the other optional flags):

```dart
    this.providerHasError = false,
```

Field:

```dart
  /// Paints the provider select trigger red (validation feedback from the
  /// enclosing TpFormField).
  final bool providerHasError;
```

In the provider `TpSelect<String>` (lines ~125–142), add after `decoration: dropdownDeco,`:

```dart
                hasError: providerHasError,
```

- [ ] **Step 2: Migrate the member launch dialog**

2a. In `_MemberLaunchConfigureDialogState` add:

```dart
  final _formKey = GlobalKey<TpFormState>();
```

2b. `_save` — insert the validate gate after the `_saving` guard and replace the preset silent gate:

```dart
  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
```

Inside `case MemberLaunchConfigKind.preset:` replace

```dart
          _ensurePresetTokenSelected(allPresets);
          if (_presetToken.isEmpty) return;
```

with

```dart
          _ensurePresetTokenSelected(allPresets);
          if (_presetToken.isEmpty) {
            _formKey.currentState?.setFieldError(
              'preset-token',
              context.l10n.formFieldRequired,
            );
            return;
          }
```

(Removes the silent return; reachable only when the field is mounted because the button stays structurally disabled when the preset list is empty — see 2d.)

2c. Build tree — wrap the card content in `TpForm`: inside `TpCard.outlined(`'s `child: Column(children: [` region, wrap the children list by changing the Column to

```dart
                  child: TpForm(
                    key: _formKey,
                    child: Column(
                      children: [
```

(close the extra paren before `TpDialogActions`).

Replace the preset field block (lines 494–505) with:

```dart
                if (_configKind == MemberLaunchConfigKind.preset &&
                    presetDropdownItems.isNotEmpty)
                  TpFormField<String>(
                    id: 'preset-token',
                    initialValue: effectivePresetToken,
                    builder: (state) => MemberLaunchPresetField(
                      items: presetDropdownItems,
                      currentToken: state.value ?? effectivePresetToken,
                      eligiblePresets: eligiblePresetList,
                      registry: registry,
                      providerState: providerState,
                      decoration: dropdownDeco,
                      onChanged: (token) {
                        state.didChange(token);
                        _applyPresetChoice(token, allPresets);
                      },
                    ),
                    validator: (value) =>
                        (value == null || value.isEmpty)
                            ? context.l10n.formFieldRequired
                            : null,
                  ),
```

Wrap the custom fields block (lines 506–546) — keep every existing argument, add the outer `TpFormField<String>` and chain the provider callback:

```dart
                if (isCustom)
                  TpFormField<String>(
                    id: 'custom-provider',
                    initialValue: _providerId,
                    builder: (state) => CliLaunchCustomFields(
                      // ...all existing arguments unchanged EXCEPT:
                      providerHasError:
                          state.hasError && _providerId.trim().isEmpty,
                      onProviderChanged: (value) {
                        state.didChange(value);
                        setState(() {
                          _providerId = value;
                          _modelId = '';
                          _effortId = '';
                        });
                      },
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? context.l10n.selectProvider
                            : null,
                  ),
```

(Write out the full argument list verbatim from the current file — `catalogCli`, `providers`, `providerId`, `modelId`, `effortId`, `registry`, `cliFieldKind`, `mixedMemberCliItems`, `cliToken`, `onMixedCliTokenChanged`, `team`, `member`, `effortContext`, `effortSubtitle`, `effortAllowInherit`, `effortTitle`, `dropdownKeyPrefix`, `decoration`, plus the two callbacks shown here.)

2d. Footer save button (lines 556–574) — drop the input-driven disable, keep the structural ones:

```dart
              FilledButton(
                onPressed: _saving
                    ? null
                    : (_configKind == MemberLaunchConfigKind.preset &&
                              presetDropdownItems.isEmpty
                          ? null
                          : () => unawaited(_save())),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
```

Rationale (matches spec): empty preset list = nothing selectable (structural); missing provider/user choices = validation errors on click.

Delete `_canSaveCustom` (lines 424–428).

- [ ] **Step 3: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/team_config/`
Expected: analyze clean; related suites pass.

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/cli_launch_config/cli_launch_custom_fields.dart client/lib/pages/team_config/team_member_launch_config_section.dart
git commit -m "feat(team-config): inline validation for member launch config dialog"
```

---

### Task 9: Team default preset configure dialog

**Files:**
- Modify: `client/lib/pages/team_config/team_default_preset_configure_dialog.dart`

**Interfaces:**
- Consumes: `CliLaunchCustomFields.providerHasError` (Task 8); everything else mirrors Task 8.

- [ ] **Step 1: Implement**

Identical pattern to Task 8, adjusted names:

1a. Add to `_TeamDefaultPresetConfigureDialogState`:

```dart
  final _formKey = GlobalKey<TpFormState>();
```

1b. `_save` (lines 134–169): after `if (_saving) return;` insert `if (!(_formKey.currentState?.validate() ?? false)) return;`. Replace lines 150–151:

```dart
        _ensurePresetTokenSelected();
        if (_presetToken.isEmpty) {
          _formKey.currentState?.setFieldError(
            'preset-token',
            context.l10n.formFieldRequired,
          );
          return;
        }
```

1c. Wrap the `TpCard.outlined` Column in `TpForm(key: _formKey)` exactly as Task 8 Step 2c.

1d. Replace the preset field block (lines 221–231) with the same `TpFormField<String>(id: 'preset-token', ...)` wrapper as Task 8 (using `MemberLaunchPresetField` with `onChanged: (token) { state.didChange(token); _applyPresetChoice(token); }`).

1e. Wrap the custom fields block (lines 232–271) with `TpFormField<String>(id: 'custom-provider', ...)` keeping all existing `CliLaunchCustomFields` arguments, adding `providerHasError: state.hasError && _providerId.trim().isEmpty` and chaining `state.didChange(value)` into `onProviderChanged`.

1f. Save button (lines 297–314) — drop the `_providerId.trim().isEmpty` disable, keep the structural preset-list disable:

```dart
              FilledButton(
                onPressed: _saving
                    ? null
                    : (_configKind == TeamLaunchConfigKind.preset &&
                              presetDropdownItems.isEmpty
                          ? null
                          : () => unawaited(_save())),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
```

- [ ] **Step 2: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/team_config/`
Expected: clean; suites pass.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/team_config/team_default_preset_configure_dialog.dart
git commit -m "feat(team-config): inline validation for default preset dialog"
```

---

### Task 10: Worktree create dialog

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart`
- Test: `client/test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`

**Interfaces:**
- Consumes: `TpForm`, `TpInputFormField` (suffixIcon passthrough via `decoration`), l10n `formFieldRequired`.

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `worktree_create_dialog_test.dart`:

```dart
  testWidgets('create with cleared name shows required error and stays open', (
    tester,
  ) async {
    WorktreeCreateResult? result;
    await tester.pumpWidget(
      _host(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWorktreeCreateDialog(
                  context,
                  repoName: 'repo',
                  repoPath: '/repo',
                  layout: ({required repoName, required branch}) =>
                      '/root/worktrees/$repoName/$branch',
                  branchLoader: _loader,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.formFieldRequired), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
Expected: new test FAILS (Create is disabled with empty name — nothing happens but no error text appears, and `find.byType(AlertDialog)` actually succeeds; the `formFieldRequired` text assertion fails).

- [ ] **Step 3: Implement**

In `_WorktreeCreateDialogState` add:

```dart
  final _formKey = GlobalKey<TpFormState>();
```

Wrap the dialog content Column (line 171 `child: Column(`) with:

```dart
        child: TpForm(
          key: _formKey,
          child: Column(
```

(close the extra paren before the `content:` SizedBox closes).

Replace the branch `TextField` (lines 176–202) with:

```dart
            TpInputFormField(
              key: const Key('worktree-branch-field'),
              controller: _branch,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.worktreeBranchLabel,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingBranches)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    TpIconButton(
                      icon: Icons.casino_outlined,
                      size: TpIconButton.kCompactSize,
                      tooltip: l10n.worktreeRandomNameTooltip,
                      onTap: _applyRandomName,
                    ),
                  ],
                ),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? l10n.formFieldRequired
                      : null,
            ),
```

Replace the Create button (lines 232–237) with:

```dart
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_buildResult());
          },
          child: Text(l10n.worktreeCreateAction),
        ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/home_workspace/workspace/worktree_create_dialog_test.dart`
Expected: PASS — all six tests (the five existing ones populate/auto-fill the name before creating).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/worktree_create_dialog.dart client/test/pages/home_workspace/workspace/worktree_create_dialog_test.dart
git commit -m "feat(worktrees): validate create dialog inline on submit"
```

---

### Task 11: Hook editor — empty-id and save-failure feedback

**Files:**
- Modify: `client/lib/pages/hooks/hook_editor_dialog.dart`
- Modify: import block (add `../../widgets/app_toast/app_toast.dart`)

**Interfaces:**
- Consumes: l10n `hookSaveFailed` (Task 3); existing `TpForm.setFieldError(id, error)`; `AppToast`.

- [ ] **Step 1: Implement**

1a. Give the name field a stable id — in `_textField`'s call site for name (lines 218–225) the underlying `TpFormField<String>` is created inside `_textField` (lines 133+); add an `id` passthrough: change `_textField` signature to accept `String? id` and pass `id: id` into the `TpFormField<String>(...)`. Update the name call site:

```dart
              _textField(
                fieldKey: const Key('hook-name'),
                id: 'name',
                controller: _name,
```

(other call sites unchanged).

1b. In `_save` (lines 155–193): clear any forced error, keep the validate gate, replace the silent empty-id return, and toast on persistence failure:

```dart
  Future<void> _save() async {
    if (_saving) return;
    _formKey.currentState?.setFieldError('name', null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = widget.definition?.id ?? _slugify(_name.text);
    if (id.isEmpty) {
      _formKey.currentState?.setFieldError('name', l10n.hookNameRequired);
      return;
    }
```

and replace the tail:

```dart
    setState(() => _saving = true);
    final ok = await widget.cubit.upsert(definition, scripts: scripts);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      AppToast.show(
        context,
        message: l10n.hookSaveFailed,
        variant: TpToastVariant.error,
      );
    }
```

1c. Add to the import block:

```dart
import '../../widgets/app_toast/app_toast.dart';
```

- [ ] **Step 2: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/hooks/`
Expected: clean; hook suites pass (existing name-required test unaffected; upsert-success flows pop normally).

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/hooks/hook_editor_dialog.dart
git commit -m "feat(hooks): surface empty-id and save-failure feedback in editor"
```

---

### Task 12: Managed provider editor — field-level validation

**Files:**
- Create: `client/lib/pages/managed_providers/managed_provider_editor_validation.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_sections.dart` (basics + query + display sections)
- Test (regression): `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

**Interfaces:**
- Consumes: `TpForm`/`TpInputFormField`, l10n `formFieldRequired`.
- Produces: `Object? decodeJsonObject(String raw)`, `bool mappingContainsCredentialKey(Object? mapping)`, `bool isAllowedManagedProviderEndpoint(String endpoint, {required bool allowHttpLocalhost})` — moved verbatim from the page's private `_decodeObject` (792–802), `_containsCredentialKey` (818–836), `_isAllowedEndpoint` (809–816). Read those functions first and keep their bodies byte-identical, only renaming + adding the flag parameter derived from the page's existing adapter/kind condition (`adapter == 'http-json' || _kind == ManagedProviderKind.customHttp`).

- [ ] **Step 1: Extract validation helpers**

Create `managed_provider_editor_validation.dart` containing the three public functions moved from the page (copy the bodies exactly; delete the privates from the page file and delegate or replace usages with imports). Page keeps `_formError` banner ONLY for async failures.

- [ ] **Step 2: Convert the form shell**

In the page's `build` (line 143): replace bare `Form(child: ListView(` with:

```dart
      child: TpForm(
        key: _editorFormKey,
        child: ListView(
```

add the field to state:

```dart
  final _editorFormKey = GlobalKey<TpFormState>();
```

and import the new validation file + shared_ui is already imported.

- [ ] **Step 3: Basics section — name/adapter required**

In `managed_provider_editor_sections.dart`, convert the name and adapter inputs inside `ManagedProviderBasicsSection` / `ManagedProviderAdvancedSection` from the private `_ManagedProviderTextField` to:

```dart
TpInputFormField(
  controller: <controller>,
  decoration: InputDecoration(hintText: <same hint>),
  validator: (value) =>
      (value == null || value.trim().isEmpty)
          ? context.l10n.formFieldRequired
          : null,
)
```

(name in Basics; adapter in Advanced). Add the `l10n_extensions.dart` import if absent.

- [ ] **Step 4: Query/display sections — format validators**

Convert in `ManagedProviderQuerySection` / `ManagedProviderDisplaySection`:

- endpoint → validator `(v) => isAllowedManagedProviderEndpoint(v ?? '', allowHttpLocalhost: <thread the page's adapter/kind condition in as a new `bool strictEndpoint` section parameter set from the page>) ? null : context.l10n.managedProvidersEndpointError`
- requestMapping → `(v) { final parsed = decodeJsonObject(v ?? ''); if (parsed == null || mappingContainsCredentialKey(parsed)) return context.l10n.managedProvidersRequestMappingError; return null; }` (preserve the page's exact empty/`{}` semantics when copying `_decodeObject`)
- fieldMappings → same shape with `managedProvidersFieldMappingError`
- decimalPlaces → `(v) => ((v ?? '').trim().isNotEmpty && int.tryParse(v!.trim()) == null) ? context.l10n.managedProvidersDecimalError : null`

Thread `strictEndpoint` as `this.strictEndpoint = false` on the query section's constructor, set from the page: `strictEndpoint: _adapter.text.trim() == 'http-json' || _kind == ManagedProviderKind.customHttp`.

- [ ] **Step 5: Rewire `_save`**

Replace the synchronous banner checks (lines 465–504: name/adapter, requestMapping, credential-key, fieldMappings, decimalPlaces, endpoint blocks) with:

```dart
  Future<void> _save() async {
    if (!(_editorFormKey.currentState?.validate() ?? false)) return;
```

Keep everything from `setState(() { _saving = true; _formError = null; });` onward untouched (credential + persistence banner paths remain — they are async/global failures per spec). Leave `_draftProviderForQuery` and `_testQuery` unchanged.

- [ ] **Step 6: Regression-test sweep**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/managed_providers/`
Expected: analyze clean. If `managed_provider_management_page_test.dart` fails asserting the banner key `managed-provider-editor-error` after an empty-name save, transform those assertions mechanically — before:

```dart
expect(find.byKey(const Key('managed-provider-editor-error')), findsOneWidget);
```

after:

```dart
expect(find.text(AppLocalizations.of(tester.element(find.byType(Scaffold).first)).formFieldRequired), findsWidgets);
```

Apply the same transformation wherever the failure came from a synchronous check; leave intact any assertion whose scenario is an async failure (credential/persistence), which still uses the banner. Report every transformed line in the commit message body.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/managed_providers/
git add client/test/pages/managed_providers/managed_provider_management_page_test.dart
git commit -m "feat(managed-providers): push editor validation down to fields"
```

---

### Task 13: Onboarding default preset step

**Files:**
- Modify: `client/lib/pages/onboarding/steps/default_preset_step.dart`

**Interfaces:**
- Consumes: `TpForm` / `TpSelectFormField` (Task 2), l10n `selectProvider` (existing).
- Produces: none downstream. `commitSelection()` stays public with the same signature (called externally by the onboarding flow).

- [ ] **Step 1: Implement**

1a. In `OnboardingDefaultPresetStepState` add the form key next to the other fields (lines 36–41):

```dart
  final _formKey = GlobalKey<TpFormState>();
```

1b. Wrap the fields card: in `build()`, the `TpCard.outlined > Column(children: [cliPicker, ...provider/model/effort rows...])` region (around lines 252–333) becomes

```dart
            TpCard.outlined(
              // ...existing arguments...
              child: TpForm(
                key: _formKey,
                child: Column(
                  children: [
```

(close the extra paren where that Column ends). The rows above/below stay verbatim.

1c. Replace the provider row's `TpCompactSelect<String>` trailing (lines ~258–287) with a validated select, keeping the row's `title`/`showDividerBelow`:

```dart
                TpPreferenceRow(
                  title: l10n.provider,
                  trailing: TpSelectFormField<String>(
                    id: 'provider',
                    items: providers.map((p) => p.id).toList(),
                    initialValue:
                        selectedProvider?.id ?? providers.firstOrNull?.id,
                    hintText: l10n.selectProvider,
                    onEmptyTap: () => _openProviderConfig(context),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? l10n.selectProvider
                            : null,
                    onChanged: (value) {
                      setState(() {
                        _effortId = '';
                        _selectProviderForCli(_cli, preferredProviderId: value);
                      });
                    },
                    itemLabel: (value) {
                      for (final p in providers) {
                        if (p.id == value) return p.name;
                      }
                      return value;
                    },
                  ),
                  showDividerBelow: !hideModelPicker || showEffortPicker,
                ),
```

Preserve whatever `itemBuilder:` closure the current row used if it differs from plain labels (copy it through). If `_openProviderConfig` does not exist in this file, add the minimal navigation helper used by `cli_preset_edit_dialog.dart` (`openCliPresetProviderConfig`) or drop `onEmptyTap` — prefer adding the helper so an empty provider list still guides the user somewhere actionable.

1d. Gate the external commit on validation — replace the opening of `commitSelection` (lines 135–137):

```dart
  Future<void> commitSelection() async {
    if (!mounted) return;
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_providerId.trim().isEmpty) return;

    final name = l10n.onboardingDefaultPresetDefaultName;
```

(The second guard remains as belt-and-braces; after validation it can only trigger when no provider exists at all.)

- [ ] **Step 2: Verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/onboarding/`
Expected: clean; suites pass.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/onboarding/steps/default_preset_step.dart
git commit -m "feat(onboarding): validate default preset step inline before commit"
```

---

### Task 14: Full verification gate

**Files:** none (verification only).

- [ ] **Step 1: Analyze + full test suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze clean, all suites pass. Fix any fallout in the owning task's file and amend that area with a follow-up commit (`fix(<area>): address form-validation sweep fallout`) — never batch unrelated fixes silently.

- [ ] **Step 2: Manual sweep (desktop run)**

Launch the app and verify each migrated form: click the primary action with required fields empty → dialog stays open, red border + localized message under the offending field, focus on first invalid; filling values saves and closes. Forms: 模型预设、LLM 模型、新建工作区、新建团队、Onboarding 默认预设步骤（无 provider 时点下一步）、成员启动配置、团队默认预设、Worktree、Hook、托管服务商。

- [ ] **Step 3: Final commit (only if docs/spec need status notes)**

No code changes expected; skip if clean.
