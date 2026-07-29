# Run Config Default Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After Run configs load, default-select last-used (persisted per workspace), else first configuration, else first compound; rename empty toolbar label to「启动」/「Launch」without changing the config editor empty-draft copy.

**Architecture:** Pure `resolveRunDefaultSelection` + `RunUiPrefsStore` at `ui/run-ui-prefs.json` (mirror `WorktreeUiPrefsStore`). `RunCubit.load()` always resolves from prefs + fresh lists then `select`s (or clears). `select` persists. `WorkspaceRunRegistry` passes `workspaceId` + store into the cubit.

**Tech Stack:** Flutter, `flutter_bloc`, `AppStorage` / `Filesystem`, existing `RunCubit` / `WorkspaceRunRegistry`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-30-run-config-default-selection-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/run/run_default_selection.dart` | Pure default-key resolver |
| `client/test/services/run/run_default_selection_test.dart` | Resolver unit tests |
| `client/lib/services/run/run_ui_prefs_store.dart` | Persist `{ workspaceId: { selectedKey } }` |
| `client/test/services/run/run_ui_prefs_store_test.dart` | Prefs round-trip tests |
| `client/lib/services/storage/app_storage.dart` | Add `runUiPrefsJson` path getter |
| `client/lib/cubits/run_cubit.dart` | `workspaceId` + prefs; apply default on `load`; persist on `select`; remove post-delete clear |
| `client/lib/services/workspace/workspace_run_registry.dart` | Construct cubit with `workspaceId` + `RunUiPrefsStore` |
| `client/test/cubits/run_cubit_test.dart` | Expect auto-select after `load` |
| `client/test/cubits/run_cubit_config_crud_test.dart` | Delete/reload fallback expectations |
| `client/lib/l10n/app_zh.arb` / `app_en.arb` | Toolbar + editor l10n keys |
| `client/lib/widgets/run/run_config_editor_dialog.dart` | Use `runEditorSelectConfiguration` |
| Generated `app_localizations*.dart` | Via `flutter gen-l10n` |

**Do not change:** `runAction` / Run button labels; `.teampilot/launch.json` schema; recommendation auto-pick; `refreshDiscover` restore of recommendation keys (v1 out of scope).

---

### Task 1: Pure default selection resolver (TDD)

**Files:**
- Create: `client/lib/services/run/run_default_selection.dart`
- Test: `client/test/services/run/run_default_selection_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/run_default_selection.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration _config(String id) => OwnedLaunchConfiguration(
  owner: _folder,
  configuration: LaunchConfiguration(id: id, name: id, type: 'shellScript'),
);

OwnedLaunchCompound _compound(String id) => OwnedLaunchCompound(
  owner: _folder,
  compound: LaunchCompound(id: id, name: id, configurationIds: const []),
);

void main() {
  test('restores persisted key when it matches a config', () {
    final a = _config('a');
    final b = _config('b');
    expect(
      resolveRunDefaultSelection(
        persistedKey: b.selectionKey,
        configurations: [a, b],
        compounds: const [],
      ),
      b.selectionKey,
    );
  });

  test('restores persisted key when it matches a compound', () {
    final c = _compound('c');
    expect(
      resolveRunDefaultSelection(
        persistedKey: c.selectionKey,
        configurations: const [],
        compounds: [c],
      ),
      c.selectionKey,
    );
  });

  test('stale persisted key falls back to first config', () {
    final a = _config('a');
    expect(
      resolveRunDefaultSelection(
        persistedKey: 'missing',
        configurations: [a],
        compounds: const [],
      ),
      a.selectionKey,
    );
  });

  test('no configs uses first compound', () {
    final c = _compound('c');
    expect(
      resolveRunDefaultSelection(
        persistedKey: null,
        configurations: const [],
        compounds: [c],
      ),
      c.selectionKey,
    );
  });

  test('empty lists yield null', () {
    expect(
      resolveRunDefaultSelection(
        persistedKey: 'x',
        configurations: const [],
        compounds: const [],
      ),
      isNull,
    );
  });

  test('recommendations are ignored (not passed in)', () {
    // Document: helper has no recommendations parameter.
    final a = _config('a');
    expect(
      resolveRunDefaultSelection(
        persistedKey: null,
        configurations: [a],
        compounds: const [],
      ),
      a.selectionKey,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/run/run_default_selection_test.dart`

Expected: FAIL — target library / symbol missing.

- [ ] **Step 3: Write minimal implementation**

```dart
import '../../models/run/launch_configuration.dart';
import 'launch_config_store.dart';

/// Picks the Run toolbar default selection key.
///
/// Order: persisted config/compound hit → first configuration → first compound.
/// Recommendations are intentionally not considered.
String? resolveRunDefaultSelection({
  required String? persistedKey,
  required List<OwnedLaunchConfiguration> configurations,
  required List<OwnedLaunchCompound> compounds,
}) {
  final key = persistedKey?.trim();
  if (key != null && key.isNotEmpty) {
    for (final config in configurations) {
      if (config.selectionKey == key) return key;
    }
    for (final compound in compounds) {
      if (compound.selectionKey == key) return key;
    }
  }
  if (configurations.isNotEmpty) return configurations.first.selectionKey;
  if (compounds.isNotEmpty) return compounds.first.selectionKey;
  return null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/run/run_default_selection_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/run_default_selection.dart \
  client/test/services/run/run_default_selection_test.dart
git commit -m "$(cat <<'EOF'
feat(run): add default launch selection resolver

EOF
)"
```

---

### Task 2: `RunUiPrefsStore` + AppStorage path (TDD)

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart` (near `worktreeUiPrefsJson`)
- Create: `client/lib/services/run/run_ui_prefs_store.dart`
- Test: `client/test/services/run/run_ui_prefs_store_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/run_ui_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('missing file returns null selectedKey', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });

  test('round-trips selectedKey per workspaceId', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    await store.saveSelectedKey('ws-1', 'key-a');
    await store.saveSelectedKey('ws-2', 'key-b');
    expect(await store.selectedKeyFor('ws-1'), 'key-a');
    expect(await store.selectedKeyFor('ws-2'), 'key-b');
  });

  test('clearSelectedKey removes workspace entry', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    await store.saveSelectedKey('ws-1', 'key-a');
    await store.clearSelectedKey('ws-1');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });

  test('corrupt JSON is treated as empty', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/ui/run-ui-prefs.json', '{not-json');
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });
}
```

Use the real `InMemoryFilesystem` write/read APIs from `client/test/support/in_memory_filesystem.dart` (adjust if `writeString` needs `ensureDir` first — follow how other prefs/store tests do it).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/run/run_ui_prefs_store_test.dart`

Expected: FAIL — missing library.

- [ ] **Step 3: Add AppStorage path + implement store**

In `AppPaths` (same file as other `ui/*.json` getters):

```dart
static String runUiPrefsJsonForTeampilotRoot(String teampilotRoot) =>
    _pathUnderTeampilotRoot(teampilotRoot, 'ui/run-ui-prefs.json');

String get runUiPrefsJson => runUiPrefsJsonForTeampilotRoot(basePath);
```

Store (mirror `WorktreeUiPrefsStore`):

```dart
class RunUiPrefsStore {
  RunUiPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path => _pathOverride ?? AppStorage.paths.runUiPrefsJson;

  Future<String?> selectedKeyFor(String workspaceId) async { /* load map */ }

  Future<void> saveSelectedKey(String workspaceId, String selectedKey) async {
    // merge into all[workspaceId] = { 'selectedKey': selectedKey }
  }

  Future<void> clearSelectedKey(String workspaceId) async {
    // remove workspaceId entry and rewrite file
  }
}
```

JSON shape: `{ "<workspaceId>": { "selectedKey": "<key>" } }`.

IO errors on read → treat as empty. Do not throw into UI.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/run/run_ui_prefs_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/run_ui_prefs_store.dart \
  client/test/services/run/run_ui_prefs_store_test.dart \
  client/lib/services/storage/app_storage.dart
git commit -m "$(cat <<'EOF'
feat(run): persist last Run selection in ui prefs

EOF
)"
```

---

### Task 3: Wire `RunCubit` default selection + persistence (TDD)

**Files:**
- Modify: `client/lib/cubits/run_cubit.dart`
- Modify: `client/test/cubits/run_cubit_test.dart`
- Modify: `client/test/cubits/run_cubit_config_crud_test.dart`
- Optionally add: `client/test/cubits/run_cubit_default_selection_test.dart` if keeping CRUD file smaller

- [ ] **Step 1: Write / update failing cubit tests**

Add tests (new file or extend existing) covering:

1. `load()` with no prefs → selects first configuration.
2. Prefs hit → restores that key.
3. Stale prefs + configs → first config; prefs rewritten on `select`.
4. No configs, only compounds → first compound.
5. Empty → `selectedKey` null and prefs cleared.
6. `select(key)` writes prefs for `workspaceId`.
7. `deleteConfiguration` of selected when another remains → falls back to remaining (not stuck null).
8. Existing tests that assumed `selectedKey == null` after `load()` must expect the auto-selected key instead.

Example skeleton:

```dart
test('load selects first config when prefs empty', () async {
  final prefs = RunUiPrefsStore(
    fs: InMemoryFilesystem(),
    pathOverride: '/ui/run-ui-prefs.json',
  );
  final platform = FakeRunPlatform(configurations: [_shellScriptConfig()]);
  final cubit = RunCubit(
    platform: platform,
    folders: const [_folder],
    workspaceId: 'ws-1',
    prefsStore: prefs,
  );
  await cubit.load();
  expect(cubit.state.selectedKey, platform.configurations.first.selectionKey);
  expect(await prefs.selectedKeyFor('ws-1'), cubit.state.selectedKey);
  await cubit.close();
});
```

For delete fallback, seed two configs, select second, delete second → expect first selected.

- [ ] **Step 2: Run targeted tests to verify failures**

Run: `cd client && flutter test test/cubits/run_cubit_test.dart test/cubits/run_cubit_config_crud_test.dart`

Expected: FAIL on new assertions / constructor args / post-load null assumptions.

- [ ] **Step 3: Implement cubit wiring**

Constructor:

```dart
RunCubit({
  required RunPlatformApi platform,
  required List<WorkspaceFolder> folders,
  this.workspaceId = '',
  RunUiPrefsStore? prefsStore,
}) : _platform = platform,
     _folders = List<WorkspaceFolder>.unmodifiable(folders),
     _prefsStore = prefsStore,
     super(const RunState());

final String workspaceId;
final RunUiPrefsStore? _prefsStore;
```

`load()` after emitting configurations/compounds:

```dart
await _applyDefaultSelection();
```

```dart
Future<void> _applyDefaultSelection() async {
  String? persisted;
  try {
    persisted = await _prefsStore?.selectedKeyFor(workspaceId);
  } catch (_) {
    persisted = null;
  }
  final resolved = resolveRunDefaultSelection(
    persistedKey: persisted,
    configurations: state.configurations,
    compounds: state.compounds,
  );
  if (resolved == null) {
    await _optionsSub?.cancel();
    _optionsSub = null;
    emit(state.copyWith(
      clearSelectedKey: true,
      options: const [],
      optionValues: const {},
      clearError: true,
    ));
    try {
      await _prefsStore?.clearSelectedKey(workspaceId);
    } catch (_) {}
    return;
  }
  await select(resolved);
}
```

In `select`, persist after **both** successful paths (compound early-return branch **and** config/recommendation branch):

```dart
try {
  await _prefsStore?.saveSelectedKey(workspaceId, selectionKey);
} catch (_) {}
```

When clearing (owned == null and not a compound), call `clearSelectedKey`.

**Critical:** In `deleteConfiguration`, remove the post-`load()` `wasSelected` / `clearSelectedKey` block. `load()` already re-applies defaults. Keep stop-running-session behavior.

**Ordering:** Apply default after configs/compounds emit, before or without waiting on `refreshDiscover` (current `load` already calls `refreshDiscover` after — keep default apply before `refreshDiscover` so the toolbar shows a selection immediately).

- [ ] **Step 4: Run cubit tests**

Run: `cd client && flutter test test/cubits/run_cubit_test.dart test/cubits/run_cubit_config_crud_test.dart test/cubits/run_cubit_default_selection_test.dart`

Expected: PASS (skip missing path if tests live only in the first two files).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/run_cubit.dart \
  client/test/cubits/run_cubit_test.dart \
  client/test/cubits/run_cubit_config_crud_test.dart \
  client/test/cubits/run_cubit_default_selection_test.dart
git commit -m "$(cat <<'EOF'
feat(run): default-select last or first launch config on load

EOF
)"
```

---

### Task 4: Pass `workspaceId` + prefs from `WorkspaceRunRegistry`

**Files:**
- Modify: `client/lib/services/workspace/workspace_run_registry.dart`
- Test: extend or add a small registry test only if one already exists; otherwise rely on cubit tests + manual wiring review

- [ ] **Step 1: Update registry construction**

In `cubitFor`:

```dart
final cubit = RunCubit(
  platform: proxy,
  folders: folders,
  workspaceId: workspaceId,
  prefsStore: _prefsStore,
);
```

Add constructor field:

```dart
WorkspaceRunRegistry({
  required WorkspaceRunPlatformFactory platformFactory,
  RunUiPrefsStore? prefsStore,
}) : _platformFactory = platformFactory,
     _prefsStore = prefsStore ?? RunUiPrefsStore();

final RunUiPrefsStore _prefsStore;
```

Find production construction of `WorkspaceRunRegistry` and ensure it still compiles (default store is fine).

- [ ] **Step 2: Compile / analyze touchpoints**

Run: `cd client && dart analyze lib/services/workspace/workspace_run_registry.dart lib/cubits/run_cubit.dart`

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/workspace/workspace_run_registry.dart
git commit -m "$(cat <<'EOF'
feat(run): wire workspace Run prefs into RunCubit

EOF
)"
```

---

### Task 5: l10n — toolbar「启动」/「Launch」, editor keeps「选择配置」

**Files:**
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/widgets/run/run_config_editor_dialog.dart`
- Generated: `client/lib/l10n/app_localizations*.dart` (via gen-l10n)

- [ ] **Step 1: Update ARB**

`app_zh.arb`:

```json
"runSelectConfiguration": "启动",
"runEditorSelectConfiguration": "选择配置",
```

`app_en.arb`:

```json
"runSelectConfiguration": "Launch",
"runEditorSelectConfiguration": "Select configuration",
```

Place `runEditorSelectConfiguration` next to `runSelectConfiguration`.

- [ ] **Step 2: Regenerate l10n**

Run: `cd client && flutter gen-l10n`

Expected: generated getters updated / added.

If the project relies on build-time generation only, run a compile that triggers it and commit the generated files the repo already tracks.

- [ ] **Step 3: Point editor at the new key**

In `run_config_editor_dialog.dart` `_buildBody` when `draft == null`:

```dart
return Text(l10n.runEditorSelectConfiguration, style: styles.sm);
```

Toolbar keeps `l10n.runSelectConfiguration` (now「启动」/「Launch」).

- [ ] **Step 4: Smoke-check usages**

Run: `cd client && rg 'runSelectConfiguration|runEditorSelectConfiguration' lib/`

Expected: toolbar dropdown uses `runSelectConfiguration`; editor uses `runEditorSelectConfiguration`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_zh.arb client/lib/l10n/app_en.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/widgets/run/run_config_editor_dialog.dart
git commit -m "$(cat <<'EOF'
feat(run): rename empty Run trigger to Launch

EOF
)"
```

---

### Task 6: Optional toolbar widget assertion + full verification

**Files:**
- Optionally modify: `client/test/widgets/run/run_toolbar_test.dart`

- [ ] **Step 1 (optional): Assert trigger shows config name after load**

If the existing harness can seed a config and pump the toolbar, expect the dropdown text to be the config name, not「Launch」/「启动」.

Skip if the harness cannot easily await `ensureLoaded` — cubit coverage is sufficient per spec.

- [ ] **Step 2: Full verification**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test test/services/run/run_default_selection_test.dart \
                 test/services/run/run_ui_prefs_store_test.dart \
                 test/cubits/ \
                 test/widgets/run/
```

Expected: analyze clean enough (no errors); all listed tests PASS. `load()` auto-select can break older assertions across cubit/widget run tests — fix them in this task.

- [ ] **Step 3: Commit any leftover test fixes**

```bash
git add -u client/test client/lib
git commit -m "$(cat <<'EOF'
test(run): cover default launch selection and label

EOF
)"
```

(Only if there are remaining uncommitted changes.)

---

## Manual check (human)

1. Open a workspace with ≥1 launch config → toolbar shows that name (or last-used), not「启动」.
2. Switch config → restart app → same workspace restores selection.
3. Delete all configs → trigger shows「启动」; editor empty draft still「选择配置」.
4. Empty workspace with only compounds → first compound selected.

---

## Execution handoff notes

- Existing `RunCubit(...); await load();` tests **will** start auto-selecting — budget time in Task 3 to fix assertions.
- Do not restore recommendation keys on `load` (spec v1).
- Prefs keyed by **workspaceId**, not `tabScopeId`.
