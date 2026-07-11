# Run Config UI Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create, edit, and delete workspace Run configurations entirely through UI—config dropdown with row Edit/Delete + Add, schema-driven Edit Configurations dialog, toolbar without More/open-launch.json, and Build/Debug only when type `kinds` allow.

**Architecture:** Persist via existing `.teampilot/launch.json` through `LaunchConfigStore` + `RunCubit` CRUD. Dropdown uses `SidebarActionMenu` with custom trailing actions. Editor is a dual-pane `AppDialog` whose right form renders `configurationSchema` generically (`LaunchConfigSchemaForm`). Runtime adapter choice options stay as compact toolbar selectors between config dropdown and Run.

**Tech Stack:** Flutter, `flutter_bloc`, existing Run platform (`RunCubit` / `RunPlatform` / `LaunchConfigStore`), `SidebarActionMenu`, `AppDialog`, `AppIconButton`, l10n ARBs.

**Spec:** [docs/superpowers/specs/2026-07-11-run-config-ui-editor-design.md](../specs/2026-07-11-run-config-ui-editor-design.md)

**Locked choices (from spec):**

| Topic | Choice |
|-------|--------|
| Toolbar | Config dropdown + Run/Stop; no More; Build/Debug kinds-gated |
| Edit surface | Schema-driven dual-pane dialog (not open launch.json) |
| Dropdown rows | Select on body; Edit + Delete trailing; footer Add |
| Runtime options | Compact choice dropdown(s) between config and Run |
| Compounds | Run from dropdown only; no compound CRUD UI |
| Delete while running | Confirm stop-then-delete |
| Accept recommendation | Open editor prefilled; Save persists |
| Duplicate | Deferred |

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/services/run/launch_config_store.dart` | Add `deleteConfiguration` |
| `client/lib/services/run/run_platform.dart` | Add `deleteConfiguration`; keep `persistConfiguration` |
| `client/lib/cubits/run_cubit.dart` | `saveConfiguration`, `deleteConfiguration`, `createConfiguration` draft helper; change `acceptRecommendation` to editor handoff or deprecate silent persist from toolbar |
| `client/lib/services/run/launch_config_schema_fields.dart` | Pure helpers: schema properties → field descriptors; parse args/env text |
| `client/lib/widgets/run/launch_config_schema_form.dart` | Schema → form widgets; validation display |
| `client/lib/widgets/run/run_config_editor_dialog.dart` | Dual-pane dialog + dirty prompt + Apply/OK/Cancel |
| `client/lib/widgets/run/run_toolbar.dart` | Remove More/Build/Debug stubs; row Edit/Delete; Add; compact options; open editor |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | New `run*` strings |
| `client/test/services/run/launch_config_store_test.dart` | Delete round-trip |
| `client/test/cubits/run_cubit_test.dart` (or new file) | save/delete/selection |
| `client/test/widgets/run/launch_config_schema_form_test.dart` | Field mapping + validation |
| `client/test/widgets/run/run_config_editor_dialog_test.dart` | Apply/OK/Cancel / dirty |
| `client/test/widgets/run/run_toolbar_test.dart` | Toolbar chrome + trailing actions |

Do **not** put editor logic in `ChatCubit` or open `launch.json` in the workbench from this feature. Keep `run_toolbar.dart` under soft line limits by extracting menu builders if needed.

---

### Task 1: Store `deleteConfiguration`

**Files:**
- Modify: `client/lib/services/run/launch_config_store.dart`
- Modify: `client/test/services/run/launch_config_store_test.dart`

- [ ] **Step 1: Write failing delete test**

```dart
test('deleteConfiguration removes id and writes document', () async {
  final io = MemoryLaunchConfigIo();
  final store = LaunchConfigStore(io: io);
  const folder = WorkspaceFolder(path: '/proj');
  await store.upsertConfiguration(
    folder: folder,
    configuration: const LaunchConfiguration(
      id: 'api',
      name: 'API',
      type: 'process',
      command: 'echo',
    ),
  );
  await store.deleteConfiguration(folder: folder, id: 'api');
  final remaining = await store.listConfigurations(folders: [folder]);
  expect(remaining, isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/run/launch_config_store_test.dart --name deleteConfiguration`

Expected: FAIL (method missing)

- [ ] **Step 3: Implement `deleteConfiguration`**

```dart
Future<void> deleteConfiguration({
  required WorkspaceFolder folder,
  required String id,
}) async {
  final existing = await _readDocument(folder);
  if (existing == null) return;
  final configs =
      existing.configurations.where((c) => c.id != id).toList();
  if (configs.length == existing.configurations.length) return;
  await writeDocument(
    folder: folder,
    document: existing.copyWith(configurations: configs),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/run/launch_config_store_test.dart --name deleteConfiguration`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/launch_config_store.dart \
  client/test/services/run/launch_config_store_test.dart
git commit -m "feat(run): deleteConfiguration on launch config store"
```

---

### Task 2: Platform + Cubit CRUD APIs

**Files:**
- Modify: `client/lib/services/run/run_platform.dart` (`RunPlatformApi` + `RunPlatform`)
- Modify: `client/lib/cubits/run_cubit.dart`
- Modify: `client/test/cubits/run_cubit_test.dart` (or create `run_cubit_config_crud_test.dart`)
- Modify: any `_RecordingPlatform` / fakes in widget tests that implement `RunPlatformApi`

- [ ] **Step 1: Write failing cubit tests**

```dart
test('saveConfiguration persists and selects', () async {
  // platform with memory store; cubit.saveConfiguration(owned);
  // expect list contains config; selectedKey matches
});

test('deleteConfiguration removes and clears selection', () async {
  // select then delete; expect gone; selectedKey null or other
});
```

Cover: save validates via platform; delete when not running; after delete of selected, selection is cleared or moved.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/cubits/run_cubit_config_crud_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement platform `deleteConfiguration` + cubit methods**

```dart
// RunPlatformApi
Future<void> deleteConfiguration({
  required WorkspaceFolder folder,
  required String id,
});

// RunCubit
Future<void> saveConfiguration(OwnedLaunchConfiguration owned);
Future<void> deleteConfiguration(OwnedLaunchConfiguration owned);
OwnedLaunchConfiguration createConfiguration({
  required WorkspaceFolder folder,
  required String type,
});
```

`saveConfiguration`: `persistConfiguration` → `load()` → `select(selectionKey)`.  
`deleteConfiguration` (cubit): **does not** show UI; assumes caller already confirmed. Stops running session if still present, then platform delete → `load()` → fix `selectedKey`. Confirm dialogs live only in toolbar/editor UI (Tasks 4/6).  
`createConfiguration`: return draft with empty `id`/`name`, `type`, empty command; id assigned on save via `normalized()`.

Update fakes implementing `RunPlatformApi`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/cubits/run_cubit_config_crud_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/run_platform.dart \
  client/lib/cubits/run_cubit.dart \
  client/test/cubits/run_cubit_config_crud_test.dart \
  client/test/widgets/run/run_toolbar_test.dart
git commit -m "feat(run): cubit save/delete/create configuration APIs"
```

---

### Task 3: Schema field helpers + form widget

**Files:**
- Create: `client/lib/services/run/launch_config_schema_fields.dart`
- Create: `client/lib/widgets/run/launch_config_schema_form.dart`
- Create: `client/test/services/run/launch_config_schema_fields_test.dart`
- Create: `client/test/widgets/run/launch_config_schema_form_test.dart`

- [ ] **Step 1: Write failing helper tests**

```dart
test('process schema yields command args cwd env shell fields', () {
  final fields = launchConfigSchemaFields(
    ProcessLaunchSchema.configurationSchema,
  );
  expect(fields.map((f) => f.key), containsAll(['command', 'args', 'env', 'cwd', 'shell']));
});

test('parseArgsText splits on whitespace', () {
  expect(parseLaunchArgsText('a b  c'), ['a', 'b', 'c']);
});

test('parseEnvText accepts KEY=VALUE lines', () {
  expect(parseLaunchEnvText('A=1\nB=2'), {'A': '1', 'B': '2'});
});
```

- [ ] **Step 2: Run helper tests — expect FAIL**

Run: `cd client && flutter test test/services/run/launch_config_schema_fields_test.dart`

- [ ] **Step 3: Implement helpers + minimal form**

`LaunchConfigSchemaForm` inputs: `LaunchConfiguration value`, `onChanged`, `schema`, optional `name` field above schema props, `errors: List<String>`.

Map types per spec (string / array&lt;string&gt; / string-map / boolean). Name is always edited as common field outside schema props.

- [ ] **Step 4: Widget test — process form shows Command field; toggling shell updates value**

Run: `cd client && flutter test test/widgets/run/launch_config_schema_form_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/launch_config_schema_fields.dart \
  client/lib/widgets/run/launch_config_schema_form.dart \
  client/test/services/run/launch_config_schema_fields_test.dart \
  client/test/widgets/run/launch_config_schema_form_test.dart
git commit -m "feat(run): schema-driven launch config form"
```

---

### Task 4: Edit Configurations dialog

**Files:**
- Create: `client/lib/widgets/run/run_config_editor_dialog.dart`
- Create: `client/test/widgets/run/run_config_editor_dialog_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (dialog strings)
- Run: `flutter gen-l10n` + `dart run tool/gen_warmup_glyphs.dart` after ARB changes

- [ ] **Step 1: Add l10n keys**

Keys (en): `runEditConfigurations`, `runAddConfiguration`, `runDeleteConfiguration`, `runDeleteConfigurationConfirm`, `runStopAndDelete`, `runApply`, `runDiscardChangesTitle`, `runDiscardChangesMessage`, `runSelectFolder`, `runConfigurationName`, `runConfigurationType`, …

- [ ] **Step 2: Write failing dialog tests**

```dart
testWidgets('OK saves via cubit and closes', (tester) async { ... });
testWidgets('Cancel discards without save', (tester) async { ... });
testWidgets('switching left item with dirty draft prompts', (tester) async { ... });
```

Host: `MaterialApp` + `BlocProvider<RunCubit>` + `showDialog` / pump `RunConfigEditorDialog`.

- [ ] **Step 3: Implement dialog**

API sketch:

```dart
Future<void> showRunConfigEditorDialog(
  BuildContext context, {
  required String workspaceId,
  OwnedLaunchConfiguration? initial,
  bool createNew = false,
  String? initialType,
  WorkspaceFolder? folder,
});
```

Layout: `AppDialog` large (`maxWidth` ~840, `maxHeight` ~560, `contentPadding: EdgeInsets.zero`).
- Left: list of `state.configurations` (folder subtitle if multi-root); Add button; Delete on selection.
- Right: `LaunchConfigSchemaForm` for selected draft; resolve schema from `RunPlatform` / registry via cubit helper `schemaForType(String type)`.
- Footer: Cancel / Apply / OK.
- Dirty navigation: Apply / Discard / Cancel prompt per spec.
- Multi-folder create: if `folders.length > 1` and creating, require folder before editing fields.
- Types: for create, default `process`; if multiple registered types, simple type dropdown (registry list).

Wire Delete in dialog to confirm dialog then `cubit.deleteConfiguration`.

Expose `schemaForType` on cubit or read registry through platform (add `Map<String, Object?>? configurationSchema(String type)` on `RunPlatformApi` if missing).

- [ ] **Step 4: Run dialog tests**

Run: `cd client && flutter test test/widgets/run/run_config_editor_dialog_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/run/run_config_editor_dialog.dart \
  client/test/widgets/run/run_config_editor_dialog_test.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/widgets/warmup_glyphs.g.dart
git commit -m "feat(run): Edit Configurations dialog"
```

---

### Task 5: Toolbar — remove More/Build stubs; kinds-gated Debug/Build; compact options

**Files:**
- Modify: `client/lib/widgets/run/run_toolbar.dart`
- Modify: `client/test/widgets/run/run_toolbar_test.dart`
- Modify: l10n (remove unused open-launch.json menu usage from toolbar; keys may remain unused until cleaned)

- [ ] **Step 1: Update toolbar tests for new chrome**

```dart
testWidgets('does not show build debug or more by default', (tester) async {
  // process config selected
  expect(find.byKey(Key('run-toolbar-build')), findsNothing);
  expect(find.byKey(Key('run-toolbar-debug')), findsNothing);
  expect(find.byKey(Key('run-toolbar-more')), findsNothing);
});

testWidgets('choice option appears as compact selector', (tester) async {
  // options with choice type → find key run-toolbar-option-<id>
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- Remove `_MoreMenu`, `_BuildGlyph` always-on, disabled `_DebugGlyph`.
- Add `_kindsForSelection(RunCubit, RunState)` → show Debug/Build `AppIconButton` only if kinds contain `debug` / `build` (v1 process: none). Debug/Build handlers can be no-op or tooltip-only until execution exists — **prefer hide over disabled stub** per spec.
- Between dropdown and Run: for each `LaunchOptionType.choice` in `state.options`, a compact `SidebarActionMenuButton` or small dropdown calling `cubit.setOption`.
- Keep Run/Stop behavior.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/run/run_toolbar.dart \
  client/test/widgets/run/run_toolbar_test.dart
git commit -m "feat(run): slim toolbar chrome and compact run options"
```

---

### Task 6: Toolbar dropdown — Edit / Delete / Add + open editor

**Files:**
- Modify: `client/lib/widgets/run/run_toolbar.dart`
- Modify: `client/lib/widgets/menu/sidebar_action_menu.dart` only if trailing custom actions need a small extension (prefer compose `buildMenuChildren` with custom `SidebarActionMenuItem` + `trailing: Row(Edit, Delete)` without changing menu core)
- Modify: `client/test/widgets/run/run_toolbar_test.dart`

- [ ] **Step 1: Failing tests**

```dart
testWidgets('config specs include add footer', (tester) async {
  final button = tester.widget<SidebarActionMenuButton>(...);
  expect(button.specs.any((s) => s.value == 'add-configuration'), isTrue);
});

testWidgets('delete confirms and calls cubit.deleteConfiguration', ...);
```

For Edit/Delete hit targets: pump menu open, tap keys `run-config-edit-<selectionKey>` / `run-config-delete-<selectionKey>`.

- [ ] **Step 2: Implement dropdown**

- Build menu via `SidebarActionMenuIconAnchor` + `buildSidebarActionMenuChildren` **or** custom children:
  - Each config/recommendation/compound/action as today for select.
  - Config rows: `trailing: Row(mainAxisSize: min, children: [AppIconButton edit, AppIconButton delete])` with `onTap` that closes menu and opens editor / delete confirm.
  - Recommendations: Edit opens editor prefilled (**no Delete**).
  - Compounds: select only (no Edit/Delete).
  - Footer divider + Add → `showRunConfigEditorDialog(..., createNew: true)`.
- Delete confirm: `AppDialog` with Stop-and-delete if `hasRunning`.
- Recommendation adopt: Edit opens editor with recommendation values (do **not** call silent `acceptRecommendation` persist from toolbar). Optionally change `acceptRecommendation` to unused by toolbar or repurpose as save helper.
- **Gesture:** ensure Edit/Delete `AppIconButton` taps do not also select the row (stop propagation / separate hit targets); assert in widget test.

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/run/run_toolbar.dart \
  client/test/widgets/run/run_toolbar_test.dart
git commit -m "feat(run): dropdown edit/delete/add for launch configs"
```

---

### Task 7: Wire acceptRecommendation + kinds helper + analyze/tests

**Files:**
- Modify: `client/lib/cubits/run_cubit.dart` — document that UI should open editor; keep `persist` path for editor Save of recommendations
- Modify: `client/lib/services/run/launch_type_registry.dart` / platform — `kindsFor(type)`, `configurationSchema(type)`
- Modify: any leftover open-launch.json call sites in Run toolbar/shell
- Test: expand coverage; full analyze

- [ ] **Step 1: Add `kindsFor` / `configurationSchema` on platform if missing; unit test**

- [ ] **Step 2: Grep and remove Run UI “open launch.json” entry points** from toolbar/shell (workbench opener may remain for other features)

- [ ] **Step 3: Run focused suite**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/widgets/run lib/cubits/run_cubit.dart lib/services/run/launch_config_store.dart \
  lib/services/run/run_platform.dart lib/services/run/launch_config_schema_fields.dart

cd client && flutter test \
  test/services/run/launch_config_store_test.dart \
  test/services/run/launch_config_schema_fields_test.dart \
  test/cubits/run_cubit_config_crud_test.dart \
  test/widgets/run/
```

Expected: no issues / all PASS

- [ ] **Step 4: Update spec status to Implemented** in `docs/superpowers/specs/2026-07-11-run-config-ui-editor-design.md`

- [ ] **Step 5: Commit**

```bash
git add -u client/lib client/test docs/superpowers/specs/2026-07-11-run-config-ui-editor-design.md
git commit -m "feat(run): finish UI config editor wiring and verification"
```

---

## Execution notes

- Prefer TDD order in each task; do not skip failing-test steps.
- After ARB edits always: `flutter gen-l10n` and `dart run tool/gen_warmup_glyphs.dart`.
- `@docs/CODE_QUALITY.md` soft line limits: split toolbar if it exceeds ~400–500 lines.
- Do not reintroduce More menu or open-launch.json affordances in Run chrome.
