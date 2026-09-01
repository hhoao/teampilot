# Session Tab Bar Visibility Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted preference (`sessionTabBarVisible`, default `true`) that hides the workspace center tab strip — the whole `WorkspaceShellTabRow` including the "+" new-chat button — with a switch in Settings → Layout → Region Visibility.

**Architecture:** Follows the existing region-visibility pattern exactly: bool field on `LayoutPreferences` (+ fromJson/copyWith/toJson), one-line setter on `LayoutCubit` via `_save`, a `showTabBar` guard in `WorkspaceShell.build` fed by `context.select` from `_ChatWorkspaceShell`, and a `TpPreferenceRow` switch in `LayoutRegionVisibilitySection`. Reference commit for the identical pattern (right-tools toggle): `40465961d`.

**Tech Stack:** Flutter (Material), flutter_bloc (`LayoutCubit`), SharedPreferences via `LayoutRepository`, shared_ui (`TpPreferenceRow`), flutter gen-l10n (l10n.yaml → tracked generated files).

**Spec:** `docs/superpowers/specs/2026-09-01-session-tab-bar-visibility-design.md`

## Global Constraints

- All paths below are relative to the repo root `/home/hhoa/git/hhoa/teampilot`; Flutter commands run from `client/`.
- Default `sessionTabBarVisible` is `true`; `fromJson` fallback for missing/garbage key is `true` (existing configs keep the tab bar).
- Hide the entire strip (session + editor + terminal chips, reorder, trailing actions, and `WorkspaceShellNewChatButton`) — no per-kind filtering, no compensating UI.
- Entry point is the settings-page switch only; no title-bar quick toggle.
- The `WorkspaceShell` parameter defaults to `true` so callers that don't pass it are unaffected.
- l10n: edit only `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`; regenerate the tracked generated files with `flutter gen-l10n` (run from `client/`, with `l10n.yaml` present — do not pass CLI flags, they conflict with the yaml).
- l10n keys: `sessionTabBarTitle` = "Session tab bar" / 「会话标签栏」; `sessionTabBarVisibilityHint` = "Show the tab strip above the workbench center column." / 「在工作台中心列上方显示标签栏。」
- AppKeys style: kebab-case value string, e.g. `Key('session-tab-bar-visibility-switch')`.
- Before declaring done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Run tests through `dart run tool/run_tests.dart` (caps concurrency at 4), not raw `flutter test`.
- Do not touch the unrelated dirty files already in the working tree (chat/session-connect work); only stage files this plan lists.
- Commit messages end with `Co-Authored-By: Claude <noreply@anthropic.com>`.

---

### Task 1: Model — `LayoutPreferences.sessionTabBarVisible`

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Test: `client/test/models/layout_preferences_default_test.dart`

**Interfaces:**
- Consumes: existing `LayoutPreferences` constructor / `fromJson` / `copyWith` / `toJson` / `withAtLeastOneToolVisible` (all in the model file).
- Produces: `bool get sessionTabBarVisible` on `LayoutPreferences` (default `true`), constructor param `bool? sessionTabBarVisible` on `copyWith`, JSON key `'sessionTabBarVisible'`. Task 2's cubit setter, Task 3's shell, and Task 4's settings row consume this field.

- [ ] **Step 1: Write the failing test**

In `client/test/models/layout_preferences_default_test.dart`, add this test beside the `rightToolsVisible` round-trip test (same shape):

```dart
  test('sessionTabBarVisible defaults true and round-trips', () {
    expect(const LayoutPreferences().sessionTabBarVisible, isTrue);
    expect(LayoutPreferences.fromJson(const {}).sessionTabBarVisible, isTrue);
    final parsed = LayoutPreferences.fromJson(const {
      'sessionTabBarVisible': false,
    });
    expect(parsed.sessionTabBarVisible, isFalse);
    expect(parsed.toJson()['sessionTabBarVisible'], isFalse);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(sessionTabBarVisible: false).toJson(),
    );
    expect(restored.sessionTabBarVisible, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`): `dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart`
Expected: FAIL — `sessionTabBarVisible` isn't defined for `LayoutPreferences`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/models/layout_preferences.dart`:

3a. Constructor (after `this.rightToolsVisible = false,` at line 54, before `this.sidebarVisible = true,`):

```dart
    this.sessionTabBarVisible = true,
```

3b. `fromJson` (after the `rightToolsVisible:` entry at line 107):

```dart
      sessionTabBarVisible: json['sessionTabBarVisible'] as bool? ?? true,
```

3c. Field declaration (after `final bool rightToolsVisible;` at line 252, before `final bool sidebarVisible;`):

```dart
  final bool sessionTabBarVisible;
```

3d. `copyWith` — parameter list (after `bool? rightToolsVisible,` at line 307):

```dart
    bool? sessionTabBarVisible,
```

3e. `copyWith` — body (after `rightToolsVisible: rightToolsVisible ?? this.rightToolsVisible,` at line 354):

```dart
      sessionTabBarVisible: sessionTabBarVisible ?? this.sessionTabBarVisible,
```

3f. `withAtLeastOneToolVisible` — constructor param (after `rightToolsVisible: rightToolsVisible,` at line 441) and its `copyWith` call parameter (after `bool? rightToolsVisible,` in the local `LayoutPreferences(` invocation's argument list — the same positional area as 3d; there is a single `copyWith`-style argument list inside this method, add the param once). Both spots need, in the same order used above:

```dart
      sessionTabBarVisible: sessionTabBarVisible,
```

Wait — clarify: `withAtLeastOneToolVisible` constructs a **new `LayoutPreferences(...)` directly** (not via copyWith). Add to that direct constructor invocation, after `rightToolsVisible: rightToolsVisible,` (line 441):

```dart
      sessionTabBarVisible: sessionTabBarVisible,
```

3g. `toJson` (after `'rightToolsVisible': rightToolsVisible,` at line 491):

```dart
      'sessionTabBarVisible': sessionTabBarVisible,
```

Note: `withAtLeastOneToolVisible` names its local variable `rightToolsVisible` when rebuilding; mirror that — the new local/argument is `sessionTabBarVisible: sessionTabBarVisible` because the method re-passes field values unchanged. If the method reads `rightToolsVisible` from `this`, use `this.sessionTabBarVisible` style consistently with neighbors (match what the surrounding lines do — they re-pass the local, which equals the field).

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`): `dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/test/models/layout_preferences_default_test.dart
git commit -m "feat(layout): add sessionTabBarVisible preference

Defaults to true; persists via LayoutRepository JSON like other region
visibility flags.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Cubit — `LayoutCubit.setSessionTabBarVisible`

**Files:**
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/cubits/layout_cubit_preferences_test.dart`

**Interfaces:**
- Consumes: `LayoutPreferences.sessionTabBarVisible` (Task 1) and the existing `LayoutCubit._save` pipeline (`_save` emits + persists via `LayoutRepository`).
- Produces: `Future<void> setSessionTabBarVisible(bool visible)` on `LayoutCubit`. Task 4's settings row wires its Switch `onChanged` to this.

- [ ] **Step 1: Write the failing test**

In `client/test/cubits/layout_cubit_preferences_test.dart`, add inside `main()` after the last test:

```dart
  test('setSessionTabBarVisible toggles and persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();

    await cubit.setSessionTabBarVisible(false);
    expect(cubit.state.preferences.sessionTabBarVisible, isFalse);

    await cubit.setSessionTabBarVisible(true);
    expect(cubit.state.preferences.sessionTabBarVisible, isTrue);

    // Reload from the repository to prove persistence.
    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.sessionTabBarVisible, isTrue);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`): `dart run tool/run_tests.dart test/cubits/layout_cubit_preferences_test.dart`
Expected: FAIL — `setSessionTabBarVisible` isn't defined for `LayoutCubit`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/cubits/layout_cubit.dart`, add beside the other one-line preference setters (after `toggleSidebar` at line 222, before `setLandingRightToolsOverride`):

```dart
  Future<void> setSessionTabBarVisible(bool visible) =>
      _save(state.preferences.copyWith(sessionTabBarVisible: visible));
```

No drawer-mode side effects — the tab strip is desktop-center chrome, unrelated to mobile drawer snapshots.

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`): `dart run tool/run_tests.dart test/cubits/layout_cubit_preferences_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/layout_cubit.dart client/test/cubits/layout_cubit_preferences_test.dart
git commit -m "feat(layout): add LayoutCubit.setSessionTabBarVisible

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Shell — gate the tab row on `showTabBar`

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart:29-36` (params), `:126` (guard)
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (pass the preference)
- Test: `client/test/pages/workspace_shell_test.dart`

**Interfaces:**
- Consumes: `LayoutPreferences.sessionTabBarVisible` (Task 1) read via `context.select<LayoutCubit, bool>`; existing `WorkspaceShell` params (`tabs`, `showNewChatButton`, …).
- Produces: `WorkspaceShell({bool showTabBar = true, ...})`. Task 4 does not consume this directly but Task 4's switch flips the value the shell reads.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/workspace_shell_test.dart`, add after the `shows tab row and new-chat when tabs present` test:

```dart
  testWidgets('showTabBar false hides the strip and new-chat button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          showTabBar: false,
          showNewChatButton: true,
          newChatTooltip: 'New',
          newConversationLabel: 'New Conversation',
          newTerminalLabel: 'New terminal',
          tabs: [TabInfo(id: 's1', title: 'Session')],
          child: Text('Session body'),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellTabRow), findsNothing);
    expect(find.byType(WorkspaceShellNewChatButton), findsNothing);
    expect(find.text('Session body'), findsOneWidget);
  });

  testWidgets('showTabBar defaults to true (strip renders)', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        const WorkspaceShell(
          showHeader: false,
          breadcrumb: 'Team / Chat',
          title: 'Chat',
          subtitle: 'Terminal',
          actions: [],
          showNewChatButton: true,
          newChatTooltip: 'New',
          newConversationLabel: 'New Conversation',
          newTerminalLabel: 'New terminal',
          tabs: [TabInfo(id: 's1', title: 'Session')],
          child: Text('Session body'),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellTabRow), findsOneWidget);
    expect(find.byType(WorkspaceShellNewChatButton), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`): `dart run tool/run_tests.dart test/pages/workspace_shell_test.dart`
Expected: FAIL — `showTabBar` isn't a parameter of `WorkspaceShell`.

- [ ] **Step 3: Write minimal implementation**

3a. In `client/lib/pages/workspace_shell/workspace_shell.dart`, add the param after `showNewChatButton = false,` (line 29) in the constructor and the field after `final bool showNewChatButton;` (line 59):

```dart
    this.showTabBar = true,
```

```dart
  /// Master switch for the center tab strip; false skips the row entirely.
  final bool showTabBar;
```

3b. Change the guard at line 126 from:

```dart
        if (tabs.isNotEmpty || showNewChatButton)
```

to:

```dart
        if (showTabBar && (tabs.isNotEmpty || showNewChatButton))
```

3c. In `client/lib/pages/chat/chat_page_shell.dart`, in `_ChatWorkspaceShell.build` (inside the `BlocBuilder<WorkbenchCubit, WorkbenchState>` where `WorkspaceShell(...)` is constructed), read the preference once before the `return WorkspaceShell(`:

```dart
            final showTabBar = context.select<LayoutCubit, bool>(
              (c) => c.state.preferences.sessionTabBarVisible,
            );
```

and pass it into the shell constructor:

```dart
            return WorkspaceShell(
              showHeader: false,
              showTabBar: showTabBar,
```

Add the import if absent:

```dart
import '../../cubits/layout_cubit.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`): `dart run tool/run_tests.dart test/pages/workspace_shell_test.dart test/pages/chat_page_personal_test.dart`
Expected: PASS (workspace shell tests + the chat page shell integration point).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell.dart client/lib/pages/chat/chat_page_shell.dart client/test/pages/workspace_shell_test.dart
git commit -m "feat(workspace_shell): gate center tab strip behind showTabBar

_ChatWorkspaceShell feeds LayoutCubit's sessionTabBarVisible into the
shell; hidden strip skips session/editor/terminal chips and the + button.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Settings UI — switch row, AppKeys, l10n

**Files:**
- Modify: `client/lib/utils/ui/app_keys.dart:38` (add key after `boardVisibilitySwitch`)
- Modify: `client/lib/l10n/app_en.arb` (~line 35, visibility-hint block)
- Modify: `client/lib/l10n/app_zh.arb` (~line 35)
- Regenerate (tracked): `client/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`
- Modify: `client/lib/pages/config/layout_region_visibility_section.dart`
- Test: `client/test/pages/config/layout_region_visibility_section_test.dart`

**Interfaces:**
- Consumes: `LayoutCubit.setSessionTabBarVisible` (Task 2), `LayoutPreferences.sessionTabBarVisible` (Task 1).
- Produces: `AppKeys.sessionTabBarVisibilitySwitch`; l10n getters `sessionTabBarTitle`, `sessionTabBarVisibilityHint` on `AppLocalizations`.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/config/layout_region_visibility_section_test.dart`, add inside `main()` after the existing test:

```dart
  testWidgets('session tab bar switch defaults on and updates cubit', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider.value(
              value: cubit,
              child: const LayoutRegionVisibilitySection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(AppKeys.sessionTabBarVisibilitySwitch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(cubit.state.preferences.sessionTabBarVisible, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(cubit.state.preferences.sessionTabBarVisible, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`): `dart run tool/run_tests.dart test/pages/config/layout_region_visibility_section_test.dart`
Expected: FAIL — `AppKeys.sessionTabBarVisibilitySwitch` doesn't exist (compile error in the test).

- [ ] **Step 3: Write minimal implementation**

3a. In `client/lib/utils/ui/app_keys.dart`, after line 38 (`boardVisibilitySwitch`):

```dart
  static const sessionTabBarVisibilitySwitch = Key(
    'session-tab-bar-visibility-switch',
  );
```

3b. In `client/lib/l10n/app_en.arb`, in the visibility block after `"visibilityRightToolsHint": ...` (line ~35):

```json
  "sessionTabBarTitle": "Session tab bar",
  "sessionTabBarVisibilityHint": "Show the tab strip above the workbench center column.",
```

3c. In `client/lib/l10n/app_zh.arb`, at the same relative spot:

```json
  "sessionTabBarTitle": "会话标签栏",
  "sessionTabBarVisibilityHint": "在工作台中心列上方显示标签栏。",
```

3d. Regenerate the tracked l10n dart files (from `client/`, plain invocation — `l10n.yaml` drives it):

```bash
flutter gen-l10n
```

Then verify the diff touches only additive getter blocks in the three generated files (`git diff -- lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart` should show only the two new getters per file). If the regen reorders or reformats unrelated getters, restore and hand-add the getters instead: abstract getter in `app_localizations.dart`, en/zh getters in the `_en`/`_zh` files, placed beside `visibilityRightToolsHint`, following the exact shapes in reference commit `40465961d`:

```dart
  /// No description provided for @sessionTabBarVisibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Show the tab strip above the workbench center column.'**
  String get sessionTabBarVisibilityHint;
```

```dart
  @override
  String get sessionTabBarVisibilityHint =>
      'Show the tab strip above the workbench center column.';
```

```dart
  @override
  String get sessionTabBarVisibilityHint => '在工作台中心列上方显示标签栏。';
```

(`sessionTabBarTitle` follows the same shape with its strings.)

3e. In `client/lib/pages/config/layout_region_visibility_section.dart`, widen the `BlocSelector` tuple from 5 to 6 bools and add the row after the Tools panel row (before the Members row):

Selector becomes:

```dart
    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (bool, bool, bool, bool, bool, bool)
    >(
      selector: (state) => (
        state.preferences.rightToolsVisible,
        state.preferences.sessionTabBarVisible,
        state.preferences.membersVisible,
        state.preferences.fileTreeVisible,
        state.preferences.gitVisible,
        state.preferences.boardVisible,
      ),
      builder: (context, visibility) {
        final (
          rightToolsVisible,
          sessionTabBarVisible,
          membersVisible,
          fileTreeVisible,
          gitVisible,
          boardVisible,
        ) = visibility;
```

and the `setVisibility` helper's positional indexes stay untouched (`visibility.$2` → members, `$3` → fileTree, `$4` → git, `$5` → board) — the new value is inserted at position 2, so bump those to `$3`/`$4`/`$5`/`$6`:

```dart
        void setVisibility({
          bool? membersVisible,
          bool? fileTreeVisible,
          bool? gitVisible,
          bool? boardVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            membersVisible: membersVisible ?? visibility.$3,
            fileTreeVisible: fileTreeVisible ?? visibility.$4,
            gitVisible: gitVisible ?? visibility.$5,
            boardVisible: boardVisible ?? visibility.$6,
          );
        }
```

New row (between the right-tools row and the members row):

```dart
            TpPreferenceRow(
              title: l10n.sessionTabBarTitle,
              subtitle: l10n.sessionTabBarVisibilityHint,
              trailing: Switch(
                key: AppKeys.sessionTabBarVisibilitySwitch,
                value: sessionTabBarVisible,
                onChanged: controller.setSessionTabBarVisible,
              ),
              showDividerBelow: true,
            ),
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `client/`): `dart run tool/run_tests.dart test/pages/config/layout_region_visibility_section_test.dart test/models/layout_preferences_default_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/ui/app_keys.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/config/layout_region_visibility_section.dart client/test/pages/config/layout_region_visibility_section_test.dart
git commit -m "feat(config): session tab bar visibility switch in region visibility

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Full gate

**Files:** none (verification only).

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: green analyze + test suite.

- [ ] **Step 1: Format + analyze**

Run (from `client/`):

```bash
bash scripts/check_format.sh
```

Expected: no formatting diffs, no analyzer issues. (If only new files need formatting, `dart format` the listed files and re-run.)

- [ ] **Step 2: Full test suite**

Run (from `client/`):

```bash
dart run tool/run_tests.dart
```

Expected: all tests pass (suite excludes the `integration` tag by default).

- [ ] **Step 3: Final commit if formatting fixed anything**

```bash
git add -u client/lib client/test
git commit -m "style: format session tab bar visibility changes

Co-Authored-By: Claude <noreply@anthropic.com>"
```

(Skip if Step 1 was already clean. `git add -u` stages only tracked modifications — verify with `git status` first that no unrelated dirty files get swept in; if unrelated dirty files exist, stage only the plan's files explicitly.)

---

## Self-Review

- **Spec coverage:** model field + persistence (Task 1), cubit setter (Task 2), shell guard + caller wiring (Task 3), settings row + AppKeys + l10n (Task 4), tests for each, gate (Task 5). Spec's "no title-bar toggle", "no compensating UI", "default true" are encoded in Global Constraints and the tests assert the default. ✅
- **Placeholder scan:** none — every code step carries concrete code; the l10n fallback path includes literal getter shapes. ✅
- **Type consistency:** `sessionTabBarVisible` (bool) named identically across model field, copyWith param, cubit setter param `visible`, selector destructure, switch `onChanged`; `showTabBar` (bool) on `WorkspaceShell`; `sessionTabBarVisibilitySwitch` key constant used in both app_keys and the settings test. ✅
