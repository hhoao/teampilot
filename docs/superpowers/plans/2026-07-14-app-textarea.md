# AppTextarea Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `AppTextareaShell` / `AppTextarea` / `AppTextareaFormField` adapted from Shad Textarea (height + resize, no `shadcn_ui`), migrate form multiline fields and compose onto the shell.

**Architecture:** Shell owns min/max height, drag-resize, and line-count derivation; `AppTextarea` wraps shell + Material `TextField` with multiline decoration overrides; compose keeps `ComposeFocusShell` + tokens and only adopts the shell for viewport height.

**Tech Stack:** Flutter, `flutter_test`, existing `AppForm` / `AppControlTheme` / `AppTextStyles`.

**Spec:** `docs/superpowers/specs/2026-07-14-app-textarea-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/widgets/textarea/app_textarea_resize_grip.dart` | Diagonal grip painter + default grip widget |
| `client/lib/widgets/textarea/app_textarea_shell.dart` | Height state, resize handle, `lineCount` via builder |
| `client/lib/widgets/textarea/app_textarea.dart` | Shell + `TextField` + multiline `InputDecoration` merge |
| `client/lib/widgets/textarea/app_textarea_form_field.dart` | `AppFormField<String>` + `AppTextarea` |
| `client/test/widgets/textarea/*.dart` | Widget tests |
| Call sites listed in spec + fresh grep | Replace multiline `TextField` / `TextFormField` |

---

### Task 1: Fresh multiline inventory grep

**Files:** none (discovery only)

- [ ] **Step 1: Grep editable multiline inputs**

Run from `client/`:

```bash
rg -n "minLines:|maxLines:" lib --glob '*.dart' -g '!**/packages/**'
```

Treat hits on `TextField` / `TextFormField` / `TextFormField`-like with `maxLines`/`minLines` > 1 as in-scope. Ignore display-only `Text(..., maxLines: …)`.

Compare to the spec table. Any extra editable multiline fields become migration targets in Task 7.

- [ ] **Step 2: Note extras in the PR / commit message body if any**

Do not skip extras.

---

### Task 2: Resize grip + shell (TDD)

**Files:**
- Create: `client/lib/widgets/textarea/app_textarea_resize_grip.dart`
- Create: `client/lib/widgets/textarea/app_textarea_shell.dart`
- Create: `client/test/widgets/textarea/app_textarea_shell_test.dart`

- [ ] **Step 1: Write failing shell tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/textarea/app_textarea_shell.dart';

void main() {
  testWidgets('clamps height when min/max props change', (tester) async {
    late double height;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 200,
            initialHeight: 150,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) =>
                SizedBox(height: 150, child: Text('lines:$lineCount')),
          ),
        ),
      ),
    );
    expect(find.textContaining('lines:'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 120,
            initialHeight: 150,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) =>
                SizedBox(height: 120, child: Text('lines:$lineCount')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(height, 120);
  });

  testWidgets('drag resize updates height and fires callback', (tester) async {
    var height = 100.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 300,
            initialHeight: 100,
            resizable: true,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) => const SizedBox(
              width: 200,
              height: 100,
              child: Text('body'),
            ),
          ),
        ),
      ),
    );

    final grip = find.byKey(const Key('app-textarea-resize-grip'));
    expect(grip, findsOneWidget);
    await tester.drag(grip, const Offset(0, 40));
    await tester.pump();
    expect(height, greaterThan(100));
    expect(height, lessThanOrEqualTo(300));
  });

  testWidgets('lineCount is at least 1 and tracks height', (tester) async {
    final counts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 500,
            initialHeight: 80,
            textStyle: const TextStyle(fontSize: 14, height: 1.25),
            builder: (context, lineCount) {
              counts.add(lineCount);
              return Text('c:$lineCount');
            },
          ),
        ),
      ),
    );
    expect(counts.last, greaterThanOrEqualTo(1));
    expect(counts.last, lessThanOrEqualTo(100));
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL (missing types)**

```bash
cd client && flutter test test/widgets/textarea/app_textarea_shell_test.dart
```

Expected: compile/import failure for `app_textarea_shell.dart`.

- [ ] **Step 3: Implement grip**

`app_textarea_resize_grip.dart` — port `ShadResizeGripPainter` / default grip from `client/packages/flutter-shadcn-ui/lib/src/components/textarea.dart` (~708–782). Rename to `AppResizeGripPainter` / `AppDefaultResizeGrip`. Color from `Theme.of(context).colorScheme.outline`. Give the default grip `Key('app-textarea-resize-grip')`.

Header comment: adapted from flutter-shadcn-ui Textarea grip; `App*` naming.

- [ ] **Step 4: Implement shell**

`AppTextareaShell` API:

```dart
class AppTextareaShell extends StatefulWidget {
  const AppTextareaShell({
    super.key,
    required this.builder,
    this.minHeight = 80,
    this.maxHeight = 500,
    this.initialHeight,
    this.resizable = true,
    this.onHeightChanged,
    this.resizeHandleBuilder,
    this.textStyle,
  });

  final Widget Function(BuildContext context, int lineCount) builder;
  final double minHeight;
  final double maxHeight;
  final double? initialHeight;
  final bool resizable;
  final ValueChanged<double>? onHeightChanged;
  final WidgetBuilder? resizeHandleBuilder;
  final TextStyle? textStyle;
  // ...
}
```

Behavior (match Shad):
- State holds `_height`, init to `initialHeight ?? minHeight`, clamp to `[minHeight, maxHeight]`.
- On `didUpdateWidget`, re-clamp and notify `onHeightChanged` if changed.
- `_calculateLineCount(TextStyle)`: `fontSize * (height ?? 20/14)` → `(_height / lineHeight).floor().clamp(1, 100)`. Prefer explicit `textStyle`, else `Theme.of(context).textTheme.bodyMedium`.
- Build: `Stack` with `SizedBox(height: _height, width: double.infinity, child: builder(...))` and optional bottom-trailing grip (`Positioned` + `GestureDetector.onPanUpdate`).
- **No** outline decoration here (compose stays borderless).

- [ ] **Step 5: Re-run shell tests — PASS**

```bash
cd client && flutter test test/widgets/textarea/app_textarea_shell_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/textarea/app_textarea_resize_grip.dart \
  client/lib/widgets/textarea/app_textarea_shell.dart \
  client/test/widgets/textarea/app_textarea_shell_test.dart
git commit -m "$(cat <<'EOF'
feat(textarea): add AppTextareaShell with resize grip

EOF
)"
```

---

### Task 3: AppTextarea (TDD)

**Files:**
- Create: `client/lib/widgets/textarea/app_textarea.dart`
- Create: `client/test/widgets/textarea/app_textarea_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/textarea/app_textarea.dart';

void main() {
  ThemeData themeWithTightInput() {
    final base = ThemeData.light();
    final control = AppControlTheme.fromScale(AppTypographyScale.standard);
    return base.copyWith(
      extensions: [control],
      inputDecorationTheme: buildAppOutlineInputDecorationTheme(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
        control: control,
      ),
    );
  }

  testWidgets('accepts typed text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('respects enabled: false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea(enabled: false)),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('decoration clears single-line tight height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(
          body: AppTextarea(minHeight: 120, maxHeight: 300),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    final c = field.decoration?.constraints;
    expect(c, isNotNull);
    expect(c!.maxHeight, isNot(equals(c.minHeight))); // not tightFor single track
    // Or: expect(c.maxHeight, greaterThan(AppControlTheme input height));
  });
}
```

Adjust `AppControlTheme.standard()` / theme helpers to match actual API in `app_control_theme.dart` (read file before coding).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/widgets/textarea/app_textarea_test.dart
```

- [ ] **Step 3: Implement `AppTextarea`**

- Assert `initialValue == null || controller == null`.
- Wrap `AppTextareaShell` with `textStyle` from `style ?? Theme.textTheme.bodyMedium`.
- In shell `builder`, set `TextField(minLines: lineCount, maxLines: lineCount, keyboardType: TextInputType.multiline, ...)`.
- Merge decoration:
  - Start from `decoration ?? const InputDecoration()`.
  - Apply `copyWith(constraints: const BoxConstraints())` or explicit min/max that allow shell height (clear theme `tightFor(height: control.height)`).
  - Prefer content padding: horizontal from `AppControlTheme` input metrics (+2 inset if outline theme does), vertical ~8–10 for multiline (not single-line track-only).
- Forward shell params: `minHeight`, `maxHeight`, `resizable`, `onHeightChanged`, `resizeHandleBuilder`.
- Common `TextField` knobs: `controller`, `focusNode`, `onChanged`, `enabled`, `readOnly`, `maxLength`, `style`, `autofocus`, etc. Do **not** port Shad-only APIs (clipboard paste files, keyboard toolbar, etc.).

Helper (same file or small private function):

```dart
InputDecoration appMultilineInputDecoration(
  BuildContext context, {
  InputDecoration? decoration,
}) { /* clear tight height; set multiline padding */ }
```

- [ ] **Step 4: Tests PASS + commit**

```bash
cd client && flutter test test/widgets/textarea/app_textarea_test.dart
git add client/lib/widgets/textarea/app_textarea.dart \
  client/test/widgets/textarea/app_textarea_test.dart
git commit -m "$(cat <<'EOF'
feat(textarea): add AppTextarea with multiline decoration override

EOF
)"
```

---

### Task 4: AppTextareaFormField (TDD)

**Files:**
- Create: `client/lib/widgets/textarea/app_textarea_form_field.dart`
- Create: `client/test/widgets/textarea/app_textarea_form_field_test.dart`

- [ ] **Step 1: Failing test — validate + form value**

Pattern like `client/test/widgets/form/app_form_test.dart`: wrap `AppForm` + `AppTextareaFormField(id: 'bio', validator: …)` + submit that calls `saveAndValidate()`. Expect error text when short; after valid input, `formKey.currentState!.value['bio']` equals text.

- [ ] **Step 2: Implement form field**

Constructor mirrors `AppFormField` + textarea knobs. Internally:

```dart
AppFormField<String>(
  id: id,
  label: label,
  // ...
  builder: (state) => AppTextarea(
    focusNode: state.focusNode,
    enabled: state.enabled,
    readOnly: readOnly,
    controller: controller,
    // initialValue only if no controller; sync via state
    onChanged: (v) => state.didChange(v),
    decoration: InputDecoration(
      // hint only — label/error from AppFormFieldLayout
      errorText: '',
      errorStyle: const TextStyle(height: 0, fontSize: 0),
      // ...
    ),
    minHeight: minHeight,
    maxHeight: maxHeight,
    resizable: resizable,
  ),
);
```

If controller is provided, keep it in sync with `state.value` the same way other form fields do (see SSH dialog / AppFormField consumers). Prefer reading `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart` for the pattern.

- [ ] **Step 3: PASS + commit**

```bash
cd client && flutter test test/widgets/textarea/app_textarea_form_field_test.dart
git add client/lib/widgets/textarea/app_textarea_form_field.dart \
  client/test/widgets/textarea/app_textarea_form_field_test.dart
git commit -m "$(cat <<'EOF'
feat(textarea): add AppTextareaFormField for AppForm

EOF
)"
```

---

### Task 5: Compose shell integration

**Files:**
- Modify: `client/lib/widgets/compose/compose_trigger_field.dart`
- Modify: `client/lib/widgets/inline_token/inline_token_text_field.dart` (only if needed for defaults / docs)
- Modify / extend: `client/test/widgets/compose/compose_trigger_field_test.dart` (or nearest existing compose test)

- [ ] **Step 1: Wrap editor in `AppTextareaShell` inside `ComposeTriggerField.build`**

Do **not** move `ComposeFocusShell` (stays in parent cards).

Approx compose heights from text style:

```dart
final lineHeight = (textStyle.fontSize ?? 14) * (textStyle.height ?? 1.35);
final minH = lineHeight * 3;
final maxH = lineHeight * 6;
```

```dart
return ShortcutFocus(
  kind: ShortcutFocusKind.compose,
  child: LayoutBuilder(
    builder: (context, constraints) {
      _fieldConstraints = constraints;
      return AppTextareaShell(
        minHeight: minH,
        maxHeight: maxH,
        initialHeight: minH,
        resizable: true,
        textStyle: textStyle,
        builder: (context, lineCount) {
          return InlineTokenTextField(
            // existing props...
            minLines: lineCount,
            maxLines: lineCount,
          );
        },
      );
    },
  ),
);
```

Keep `InlineTokenTextField` decoration borderless (no outline from shell).

- [ ] **Step 2: Update compose tests**

- Typing still works.
- Token / slash behavior still works if covered.
- Optional: find resize grip and drag; field still accepts input.

- [ ] **Step 3: Run compose tests + commit**

```bash
cd client && flutter test test/widgets/compose/
git add client/lib/widgets/compose/compose_trigger_field.dart \
  client/lib/widgets/inline_token/inline_token_text_field.dart \
  client/test/widgets/compose/
git commit -m "$(cat <<'EOF'
feat(compose): drive editor height via AppTextareaShell

EOF
)"
```

---

### Task 6: Migrate form / dialog multiline fields

**Files (known set — plus Task 1 extras):**
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Modify: `client/lib/pages/expert_hub/expert_editor_dialog.dart`
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Modify: `client/lib/pages/hub_publish/hub_publish_wizard_steps.dart`
- Modify: `client/lib/pages/mcp/mcp_oauth_connect_dialog.dart`
- Modify: `client/lib/pages/mcp/mcp_form_page.dart`
- Modify: `client/lib/pages/team_config/team_config_info_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_team_generate_section.dart`
- Modify: `client/lib/widgets/run/launch_config_schema_form.dart`
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Modify: `client/lib/pages/ssh_profile_setup_page.dart`

- [ ] **Step 1: Replace each multiline `TextField`/`TextFormField` with `AppTextarea`**

Mapping guidance:
- Former `minLines`/`maxLines` → approximate `minHeight`/`maxHeight` via `lineHeight * n` (use field `style` or theme bodyMedium). Tall JSON: e.g. ~16–28 lines for provider JSON, ~12 for MCP JSON.
- Keep existing controllers, keys, `onChanged`, `enabled`, monospace `style` where present.
- For fields that used `InputDecoration(labelText: …)` **outside** `AppForm`: either keep label on decoration **or** switch to stacked label widgets already used nearby — prefer minimal churn: `AppTextarea(decoration: InputDecoration(labelText: …))` is OK when not inside `AppFormFieldLayout`.
- `ssh_profile_setup_page` private key: `AppTextarea` + keep validator on surrounding `Form` / migrate validation carefully (page may still use `Form` + `TextFormField`; if so, wrap with `FormField`/`AppTextarea` that calls validator, or keep a thin `TextFormField` only if blocking — prefer `AppTextarea` inside `FormField<String>` builder without nesting another form field).
- `launch_config_schema_form`: multiline branches → `AppTextarea`; single-line stays `TextField`.
- Default `resizable: true` unless the layout is too cramped (git commit row: still OK with modest maxHeight).

- [ ] **Step 2: Use `AppTextareaFormField` only where parent already is `AppForm`**

Do not convert whole forms to `AppForm` in this task.

- [ ] **Step 3: Analyze touched files**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/widgets/textarea \
  lib/widgets/app_provider/app_provider_form_sheet.dart \
  lib/pages/expert_hub/expert_editor_dialog.dart \
  lib/pages/automations/automation_editor_dialog.dart \
  lib/pages/hub_publish/hub_publish_wizard_steps.dart \
  lib/pages/mcp/mcp_oauth_connect_dialog.dart \
  lib/pages/mcp/mcp_form_page.dart \
  lib/pages/team_config/team_config_info_section.dart \
  lib/pages/home_workspace/home_workspace_team_generate_section.dart \
  lib/widgets/run/launch_config_schema_form.dart \
  lib/widgets/git/git_source_control_panel.dart \
  lib/pages/ssh_profile_setup_page.dart
```

- [ ] **Step 4: Commit**

```bash
git add <touched files>
git commit -m "$(cat <<'EOF'
refactor: migrate multiline fields to AppTextarea

EOF
)"
```

---

### Task 7: Verification

- [ ] **Step 1: Re-grep — no stray editable multiline TextFields left** (except intentional single-line / display `Text`)

```bash
cd client && rg -n "TextField\(|TextFormField\(" lib -g '!**/packages/**' -A6 | rg -n "minLines:|maxLines:\s*[2-9]|maxLines:\s*1[0-9]"
```

Remaining hits should be inside `AppTextarea` / `InlineTokenTextField` only, or justified exceptions documented in the commit.

- [ ] **Step 2: Full widget test slice**

```bash
cd client && flutter test \
  test/widgets/textarea/ \
  test/widgets/compose/ \
  test/widgets/form/app_form_test.dart
```

- [ ] **Step 3: Broader verify (repo gate)**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

- [ ] **Step 4: Final commit if fixes needed**

```bash
git commit -m "$(cat <<'EOF'
fix(textarea): address migration leftover and test gaps

EOF
)"
```

---

## Notes for implementers

- **UX:** Fixed viewport + drag resize replaces content auto-grow — do not reintroduce auto-grow.
- **Theme:** Global outline `tightFor(height:)` stays for single-line; only `AppTextarea` clears it.
- **No** `shadcn_ui` import in `client/lib/` (read package source for ideas only).
- Prefer `@` skills: `superpowers:test-driven-development`, `superpowers:verification-before-completion`.
