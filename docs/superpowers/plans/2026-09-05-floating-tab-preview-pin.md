# Floating Tab Preview / Pin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VSCode-style preview slot + pin (three-state) tabs on the floating workspace strip, unified with the center strip.

**Architecture:** `TabStrip` (already the single owner of per-strip tab state) gains a `pinnedIds` set next to `previewIds`; the reducer gains `promote`/`pin`/`unpin`; `WorkbenchCubit` routes preview adds and pin/unpin through strip-presence (`_owningStrip`) so both center and floating strips get identical semantics. `WorkbenchEditorOpener` gates preview adds on a new `LayoutPreferences.floatingPreviewTabs` flag and guards dirty tabs (dirty promotes, never replaced). UI changes flow through the existing `WorkbenchStripTabChip` / `TpTabChip` / `BuiltinCloseTabMenuSource` pipeline.

**Tech Stack:** Flutter / Dart, flutter_bloc, `client/packages/shared_ui` (Tp design system), l10n via `.arb` files.

**Spec:** `docs/specs/2026-09-05-floating-tab-preview-pin-design.md`

## Global Constraints

- State is **flutter_bloc cubits only**; `TabStripReducer` stays pure (no IO).
- All user-visible strings go through l10n — edit `client/lib/l10n/app_en.arb` and `app_zh.arb` **only** (generated `app_localizations*.dart` files are produced by `flutter gen-l10n`, which runs as part of the test tooling).
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Pin only protects against **user** close actions (closeOthers/closeRight/closeAll); programmatic removal via `WorkbenchCubit.close(ws, id)` ignores pinned.
- Preview scope: `filePreview` and `diffPreview` surfaces only, gated by `floatingPreviewTabs` (default `true`). `terminal`/`run`/`htmlPreview`/`gitGraph`/`gitCompare` are always normal tabs.
- Test command for a single file: `cd client && dart run tool/run_tests.dart test/<path>.dart`.

---

### Task 1: `TabStrip.pinnedIds` + reducer `promote` / `pin` / `unpin`

**Files:**
- Modify: `client/lib/cubits/workbench/tab_strip.dart`
- Test: `client/test/cubits/workbench/tab_strip_test.dart`

**Interfaces:**
- Consumes: existing `TabStrip`, `TabStripReducer`.
- Produces:
  - `TabStrip.pinnedIds` — `Set<WorkbenchTabId>`, `copyWith` param, in `props`.
  - `TabStripReducer.promote(TabStrip strip, WorkbenchTabId id) → TabStrip` — moves id out of `previewIds` (preview → normal).
  - `TabStripReducer.pin(TabStrip strip, WorkbenchTabId id) → TabStrip` — adds id to `pinnedIds` (normal → pinned; no-op on preview ids).
  - `TabStripReducer.unpin(TabStrip strip, WorkbenchTabId id) → TabStrip` — removes id from `pinnedIds` (pinned → normal).
  - The **existing** reducer `pin` method is **replaced** by the new `pin` signature above (old one only cleared `previewIds`; new one toggles `pinnedIds`).

- [ ] **Step 1: Write the failing tests**

Add to `client/test/cubits/workbench/tab_strip_test.dart` (file already has fixtures `_s1`, `_s2`, `_f`, `_d`, reducer `r`, `empty`):

```dart
group('pinnedIds', () {
  test('pin adds a normal tab to pinnedIds; unpin removes it', () {
    final (s1, _) = r.add(empty, _s1, preview: false);
    final s2 = r.pin(s1, _s1);
    expect(s2.pinnedIds, {_s1});
    expect(s2.previewIds, isEmpty);
    final s3 = r.unpin(s2, _s1);
    expect(s3.pinnedIds, isEmpty);
  });

  test('pin is a no-op on a preview tab', () {
    final (s1, _) = r.add(empty, _f, preview: true);
    final s2 = r.pin(s1, _f);
    expect(s2.pinnedIds, isEmpty);
    expect(s2.previewIds, {_f});
  });

  test('promote moves a preview tab to normal', () {
    final (s1, _) = r.add(empty, _f, preview: true);
    final s2 = r.promote(s1, _f);
    expect(s2.previewIds, isEmpty);
    expect(s2.pinnedIds, isEmpty);
    expect(s2.order, [_f]);
  });

  test('promote is a no-op on absent or pinned ids', () {
    final (s1, _) = r.add(empty, _s1, preview: false);
    final s2 = r.pin(s1, _s1);
    expect(r.promote(s2, _s1), same(s2));
    expect(r.promote(s2, _d), same(s2));
  });

  test('remove cleans pinnedIds', () {
    final (s1, _) = r.add(empty, _s1, preview: false);
    final (s2, _) = r.add(s1, _s2, preview: false);
    final s3 = r.pin(s2, _s1);
    final s4 = r.remove(s3, _s1);
    expect(s4!.pinnedIds, isEmpty);
  });

  test('add(preview) never replaces a pinned tab', () {
    final (s1, _) = r.add(empty, _s1, preview: false);
    final s2 = r.pin(s1, _s1);
    final (s3, replaced) = r.add(s2, _s2, preview: true);
    expect(replaced, isNull);
    expect(s3.order, [_s1, _s2]);
    expect(s3.previewIds, {_s2});
  });

  test('preview slot replacement skips pinned tabs when choosing a victim', () {
    // normal preview + pinned tab: the preview is replaced, not the pinned.
    final (s1, _) = r.add(empty, _f, preview: true);
    final (s2, _) = r.add(s1, _s1, preview: false);
    final s3 = r.pin(s2, _s1);
    final (s4, replaced) = r.add(s3, WorkbenchTabId.file('/b.dart'), preview: true);
    expect(replaced, _f);
    expect(s4.order, [WorkbenchTabId.file('/b.dart'), _s1]);
    expect(s4.pinnedIds, {_s1});
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/tab_strip_test.dart`
Expected: FAIL — `pinnedIds` / `promote` / `unpin` undefined.

- [ ] **Step 3: Implement**

In `client/lib/cubits/workbench/tab_strip.dart`:

1. Add to `TabStrip` constructor/fields/copyWith/props (mirror `previewIds` everywhere):

```dart
/// Tabs pinned by the user — protected from user close actions
/// (closeOthers / closeRight / closeAll) until unpinned.
final Set<WorkbenchTabId> pinnedIds;
```

`copyWith` gains `Set<WorkbenchTabId>? pinnedIds`; `props` gains `pinnedIds`.

2. In `add`, exclude pinned tabs from the preview-victim scan:

```dart
if (preview) {
  for (final candidate in order) {
    if (previews.contains(candidate) && !pinneds.contains(candidate)) {
      replaced = candidate;
      break;
    }
  }
}
```

where `pinneds` is `Set<WorkbenchTabId>.of(strip.pinnedIds)` taken at the top of `add` alongside `previews`; every `copyWith` in `add` also passes `pinnedIds: pinneds`.

Also in `add`'s existing-tab branch (`existing >= 0`): keep current behavior, but note the demote guard `if (!preview || !previews.contains(tab))` already prevents a pinned tab being demoted (pinned tabs are never in `previewIds`).

3. In `remove`, clean `pinnedIds` alongside `previewIds`:

```dart
final pinneds = Set<WorkbenchTabId>.of(strip.pinnedIds)..remove(id);
```

and pass `pinnedIds: pinneds` to `copyWith`.

4. Replace the old `pin` method and add `promote` / `unpin`:

```dart
/// Pins [id] (normal → pinned). No-op when [id] is absent, already
/// pinned, or still a preview.
TabStrip pin(TabStrip strip, WorkbenchTabId id) {
  if (!strip.order.contains(id) ||
      strip.pinnedIds.contains(id) ||
      strip.previewIds.contains(id)) {
    return strip;
  }
  final pinneds = Set<WorkbenchTabId>.of(strip.pinnedIds)..add(id);
  return strip.copyWith(
    order: strip.order,
    activeId: strip.activeId,
    previewIds: strip.previewIds,
    pinnedIds: pinneds,
  );
}

/// Unpins [id] (pinned → normal). No-op when not pinned.
TabStrip unpin(TabStrip strip, WorkbenchTabId id) {
  if (!strip.pinnedIds.contains(id)) return strip;
  final pinneds = Set<WorkbenchTabId>.of(strip.pinnedIds)..remove(id);
  return strip.copyWith(
    order: strip.order,
    activeId: strip.activeId,
    previewIds: strip.previewIds,
    pinnedIds: pinneds,
  );
}

/// Promotes [id] out of the preview set (preview → normal). No-op when
/// absent or not a preview.
TabStrip promote(TabStrip strip, WorkbenchTabId id) {
  if (!strip.previewIds.contains(id)) return strip;
  final previews = Set<WorkbenchTabId>.of(strip.previewIds)..remove(id);
  return strip.copyWith(
    order: strip.order,
    activeId: strip.activeId,
    previewIds: previews,
    pinnedIds: strip.pinnedIds,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/tab_strip_test.dart`
Expected: PASS (all groups, including the pre-existing ones — the old `pin` semantics change is covered next task).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/workbench/tab_strip.dart client/test/cubits/workbench/tab_strip_test.dart
git commit -m "feat(workbench): pinnedIds + promote/pin/unpin in TabStrip reducer"
```

---

### Task 2: `WorkbenchCubit` — `openFloating(preview:)`, strip-routed pin/unpin, close-protection

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`
- Test: `client/test/cubits/workbench/workbench_cubit_test.dart`

**Interfaces:**
- Consumes: Task 1 reducer methods (`promote`, `pin`, `unpin`, `add`).
- Produces:
  - `WorkbenchTabId? openFloating(String workspaceId, WorkbenchTabId tab, {bool preview = false, bool activate = true})` — returns the replaced tab id (or null).
  - `void promote(String workspaceId, WorkbenchTabId id)` — presence-routed.
  - `void pin(String workspaceId, WorkbenchTabId id)` — presence-routed (replaces center-only version).
  - `void unpin(String workspaceId, WorkbenchTabId id)` — presence-routed.
  - `closeOthers` / `closeRight` / `closeAll` skip `center.pinnedIds`.

- [ ] **Step 1: Write the failing tests**

Add to `client/test/cubits/workbench/workbench_cubit_test.dart`:

```dart
group('floating preview/pin', () {
  test('openFloating(preview: true) replaces the previous preview slot', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    final replaced1 = cubit.openFloating('ws', WorkbenchTabId.file('/a.dart'),
        preview: true);
    expect(replaced1, isNull);
    final replaced2 = cubit.openFloating('ws', WorkbenchTabId.file('/b.dart'),
        preview: true);
    expect(replaced2, WorkbenchTabId.file('/a.dart'));
    expect(cubit.floatingOrder('ws'), [WorkbenchTabId.file('/b.dart')]);
    expect(
      cubit.state.bar('ws').floating.previewIds,
      {WorkbenchTabId.file('/b.dart')},
    );
  });

  test('openFloating(preview: false) keeps both tabs (normal)', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    cubit.openFloating('ws', WorkbenchTabId.file('/a.dart'));
    cubit.openFloating('ws', WorkbenchTabId.file('/b.dart'));
    expect(cubit.floatingOrder('ws').length, 2);
    expect(cubit.state.bar('ws').floating.previewIds, isEmpty);
  });

  test('pin/unpin route by strip presence (floating)', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    cubit.openFloating('ws', WorkbenchTabId.shell('e1'));
    final id = WorkbenchTabId.shell('e1');
    cubit.pin('ws', id);
    expect(cubit.state.bar('ws').floating.pinnedIds, {id});
    cubit.unpin('ws', id);
    expect(cubit.state.bar('ws').floating.pinnedIds, isEmpty);
  });

  test('promote routes by strip presence (floating)', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    cubit.openFloating('ws', WorkbenchTabId.file('/a.dart'), preview: true);
    cubit.promote('ws', WorkbenchTabId.file('/a.dart'));
    expect(cubit.state.bar('ws').floating.previewIds, isEmpty);
  });

  test('closeAll skips pinned center tabs', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    cubit.openSession('ws', 's1');
    cubit.openSession('ws', 's2');
    cubit.pin('ws', WorkbenchTabId.session('s1'));
    final removed = cubit.closeAll('ws');
    expect(removed, [WorkbenchTabId.session('s2')]);
    expect(cubit.centerOrder('ws'), [WorkbenchTabId.session('s1')]);
  });

  test('closeOthers and closeRight skip pinned center tabs', () {
    final cubit = WorkbenchCubit();
    addTearDown(cubit.close);
    cubit.openSession('ws', 's1');
    cubit.openSession('ws', 's2');
    cubit.openSession('ws', 's3');
    cubit.pin('ws', WorkbenchTabId.session('s3'));
    final removed = cubit.closeOthers('ws', WorkbenchTabId.session('s1'));
    expect(removed, [WorkbenchTabId.session('s2')]);
    expect(cubit.centerOrder('ws'),
        [WorkbenchTabId.session('s1'), WorkbenchTabId.session('s3')]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart`
Expected: FAIL — `openFloating` has no `preview` param / no `unpin`, `promote`.

- [ ] **Step 3: Implement**

In `client/lib/cubits/workbench/workbench_cubit.dart`:

1. Change `openFloating` to return the replaced id and forward `preview`:

```dart
/// Adds [tab] to the floating strip (shell / run / floating file or diff
/// preview). Presence, order, active, and the preview slot are owned here.
/// Returns the replaced preview tab id, or null when nothing was replaced.
WorkbenchTabId? openFloating(
  String workspaceId,
  WorkbenchTabId tab, {
  bool preview = false,
  bool activate = true,
}) {
  final bar = state.bar(workspaceId);
  final (next, replaced) = _r.add(
    bar.floating,
    tab,
    preview: preview,
    activate: activate,
  );
  emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  return replaced;
}
```

2. Add `_mutateOwningStrip` helper and route `promote` / `pin` / `unpin` through it (replace the old center-only `pin`):

```dart
TabStrip? _applyToOwningStrip(
  String workspaceId,
  WorkbenchTabId id,
  TabStrip Function(TabStrip strip) mutate,
) {
  final bar = state.bar(workspaceId);
  final (strip, isCenter) = _owningStrip(bar, id);
  final next = mutate(strip);
  if (identical(next, strip)) return null;
  emit(
    state.withBar(
      workspaceId,
      isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
    ),
  );
  return next;
}

/// Promotes [id] out of preview (preview → normal) on whichever strip owns it.
void promote(String workspaceId, WorkbenchTabId id) {
  _applyToOwningStrip(workspaceId, id, (strip) => _r.promote(strip, id));
}

void pin(String workspaceId, WorkbenchTabId id) {
  _applyToOwningStrip(workspaceId, id, (strip) => _r.pin(strip, id));
}

void unpin(String workspaceId, WorkbenchTabId id) {
  _applyToOwningStrip(workspaceId, id, (strip) => _r.unpin(strip, id));
}
```

3. In `closeOthers`, filter the removal list: `final removed = center.order.where((t) => t != keep && !center.pinnedIds.contains(t)).toList(growable: false);`
4. In `closeRight`, after `sublist(index + 1)`, filter: `.where((t) => !center.pinnedIds.contains(t)).toList(growable: false)`.
5. In `closeAll`, same filter on `removed`. Keep the `removed` return value semantics (list of actually-removed ids).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart`
Expected: PASS.

Also run the reducer suite (regression): `cd client && dart run tool/run_tests.dart test/cubits/workbench/` — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/workbench/workbench_cubit.dart client/test/cubits/workbench/workbench_cubit_test.dart
git commit -m "feat(workbench): openFloating preview slot + strip-routed pin/unpin + pinned close protection"
```

---

### Task 3: `LayoutPreferences.floatingPreviewTabs` + config UI

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart` (setter)
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart` (toggle row)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/models/layout_preferences_test.dart` (create if absent)

**Interfaces:**
- Consumes: existing `LayoutPreferences` JSON round-trip pattern.
- Produces: `bool get floatingPreviewTabs` (default `true`); `LayoutCubit.setFloatingPreviewTabs(bool)`; l10n getters `floatingPreviewTabsTitle` / `floatingPreviewTabsDescription`.

- [ ] **Step 1: Write the failing test**

Create/extend `client/test/models/layout_preferences_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('floatingPreviewTabs defaults to true and round-trips', () {
    const prefs = LayoutPreferences();
    expect(prefs.floatingPreviewTabs, isTrue);

    final off = prefs.copyWith(floatingPreviewTabs: false);
    final json = off.toJson();
    expect(json['floatingPreviewTabs'], false);
    expect(LayoutPreferences.fromJson(json).floatingPreviewTabs, isFalse);
  });

  test('fromJson tolerates missing floatingPreviewTabs', () {
    expect(
      LayoutPreferences.fromJson(const {}).floatingPreviewTabs,
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/layout_preferences_test.dart`
Expected: FAIL — no such getter.

- [ ] **Step 3: Implement**

1. `layout_preferences.dart` — follow the `autoOpenSubagentPreview` pattern exactly:
   - constructor: `this.floatingPreviewTabs = true,`
   - `fromJson`: `json['floatingPreviewTabs'] as bool? ?? true,`
   - field: `final bool floatingPreviewTabs;`
   - `copyWith`: `bool? floatingPreviewTabs,` → `floatingPreviewTabs ?? this.floatingPreviewTabs,`
   - `toJson`: `'floatingPreviewTabs': floatingPreviewTabs,`
   - `props`/equality: add alongside existing bool fields (if the class uses manual `==`).
2. `layout_cubit.dart` — next to `setFilePreviewHost`:

```dart
Future<void> setFloatingPreviewTabs(bool value) =>
    _save(state.preferences.copyWith(floatingPreviewTabs: value));
```

3. l10n — add to `app_en.arb`:

```json
"floatingPreviewTabsTitle": "Single preview tab",
"floatingPreviewTabsDescription": "File and diff previews share one replaceable tab in the floating panel until pinned."
```

and to `app_zh.arb`:

```json
"floatingPreviewTabsTitle": "单个预览标签页",
"floatingPreviewTabsDescription": "文件与 diff 预览在浮动面板中共享一个可替换的标签页,固定后保留。"
```

4. `layout_appearance_in_layout_section.dart` — immediately **after** the `filePreviewHost` `TpPreferenceRow` (after its `showDividerBelow: true,` closing), insert:

```dart
TpPreferenceRow(
  title: l10n.floatingPreviewTabsTitle,
  subtitle: l10n.floatingPreviewTabsDescription,
  trailing: Switch(
    value: context.select<LayoutCubit, bool>(
      (c) => c.state.preferences.floatingPreviewTabs,
    ),
    onChanged: controller.setFloatingPreviewTabs,
  ),
  showDividerBelow: true,
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/layout_preferences_test.dart`
Expected: PASS. (l10n getters are regenerated by the test tooling; if `flutter analyze` later reports missing getters, run `cd client && flutter gen-l10n`.)

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart \
  client/lib/pages/config/layout_appearance_in_layout_section.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/models/layout_preferences_test.dart
git commit -m "feat(config): floatingPreviewTabs preference + settings toggle"
```

---

### Task 4: `WorkbenchEditorOpener` — preview-gated floating opens, dirty guard, replaced teardown

**Files:**
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`
- Modify: `client/lib/app/app_shell.dart` (opener wiring — inject `readFloatingPreviewTabs`)
- Test: `client/test/services/workbench/workbench_editor_opener_test.dart`

**Interfaces:**
- Consumes: Task 2 `openFloating(preview:)`, `promote`; Task 3 pref (read via injected closure).
- Produces:
  - `WorkbenchEditorOpener` new optional ctor param: `bool Function()? readFloatingPreviewTabs` (defaults to `() => true`).
  - Behavior: floating file/diff opens pass `preview:` when the pref is on; a dirty preview-slot tab is promoted instead of replaced.

- [ ] **Step 1: Write the failing tests**

Add to `client/test/services/workbench/workbench_editor_opener_test.dart` (reuse the file's existing `_GatedFilesystem` / `EditorCubit` / `WorkbenchCubit` / `FloatingWorkspaceCubit` setup pattern; `InMemoryFilesystem` is available from `../../support/in_memory_filesystem.dart`):

```dart
test('openFile reuses the floating preview slot (pref on)', () async {
  final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
  fs.files['/repo/b.txt'] = 'world';
  final editor = EditorCubit(fs: fs);
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  addTearDown(editor.close);
  addTearDown(workbench.close);
  addTearDown(floating.close);

  final opener = WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    floating: floating,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  await opener.openFile('ws', '/repo/a.txt');
  await opener.openFile('ws', '/repo/b.txt');

  final floatingFiles = workbench.state.bar('ws').floating.order
      .where((t) => t.kind == WorkbenchTabKind.file)
      .toList();
  expect(floatingFiles, [WorkbenchTabId.file('/repo/b.txt')]);
  // The replaced file is closed in the editor bucket.
  expect(editor.state.bucket('ws').openFilePaths, isNot(contains('/repo/a.txt')));
  expect(editor.state.bucket('ws').openFilePaths, contains('/repo/b.txt'));
});

test('openFile opens normal tabs when pref off', () async {
  // same setup as above, plus:
  //   readFloatingPreviewTabs: () => false,
  await opener.openFile('ws', '/repo/a.txt');
  await opener.openFile('ws', '/repo/b.txt');
  expect(
    workbench.state.bar('ws').floating.order
        .where((t) => t.kind == WorkbenchTabKind.file)
        .length,
    2,
  );
});

test('openFile does not replace a dirty preview tab', () async {
  final fs = InMemoryFilesystem()
    ..files['/repo/a.txt'] = 'hello'
    ..files['/repo/b.txt'] = 'world';
  final editor = EditorCubit(fs: fs);
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  addTearDown(editor.close);
  addTearDown(workbench.close);
  addTearDown(floating.close);

  final opener = WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    floating: floating,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  await opener.openFile('ws', '/repo/a.txt');
  // Simulate the user editing /repo/a.txt.
  editor.updateContent('ws', '/repo/a.txt', 'hello!');
  expect(editor.state.bucket('ws').isDirty('/repo/a.txt'), isTrue);

  await opener.openFile('ws', '/repo/b.txt');

  // Dirty tab was promoted (not replaced, not closed); new file appended.
  expect(workbench.state.bar('ws').floating.previewIds, isEmpty);
  final floatingFiles = workbench.state.bar('ws').floating.order
      .where((t) => t.kind == WorkbenchTabKind.file)
      .toList();
  expect(floatingFiles, [
    WorkbenchTabId.file('/repo/a.txt'),
    WorkbenchTabId.file('/repo/b.txt'),
  ]);
  expect(editor.state.bucket('ws').openFilePaths, contains('/repo/a.txt'));
});
```

Note: check `InMemoryFilesystem`'s actual API (`files` map write pattern is shown in the existing tests). If `EditorCubit` has no `updateContent(ws, path, text)` method, use the actual dirty-making API (search `editor_cubit.dart` for the content setter used by the editor surface, e.g. `setEditorContent` / `onContentChanged`) — the test's intent is "make the file dirty", the exact call may need adjusting to the real API before running.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/workbench_editor_opener_test.dart`
Expected: FAIL — both files present as separate tabs (no preview slot behavior).

- [ ] **Step 3: Implement**

In `client/lib/services/workbench/workbench_editor_opener.dart`:

1. Constructor gains (next to `readFilePreviewInFloating`):

```dart
bool Function()? readFloatingPreviewTabs,
```

stored as `_readFloatingPreviewTabs = readFloatingPreviewTabs ?? (() => true)`.

2. Extract a helper used by both `openFile` and `openDiff` floating branches:

```dart
/// Opens [tab] on the floating strip through the preview slot when enabled.
/// A dirty preview-slot tab is promoted (kept) instead of replaced.
void _openFloatingPreviewTab(String workspaceId, WorkbenchTabId tab) {
  _floating.ensureOpen();
  _floating.setActiveWorkspace(workspaceId);
  if (!_readFloatingPreviewTabs()) {
    _workbench.openFloating(workspaceId, tab, activate: true);
    return;
  }
  _promoteDirtyFloatingPreview(workspaceId);
  final replaced = _workbench.openFloating(
    workspaceId,
    tab,
    preview: true,
    activate: true,
  );
  _closeReplaced(workspaceId, replaced);
}

/// Promotes the current floating preview tab when its file is dirty, so the
/// reducer never replaces a tab with unsaved content.
void _promoteDirtyFloatingPreview(String workspaceId) {
  final strip = _workbench.state.bar(workspaceId).floating;
  for (final id in strip.previewIds) {
    final path = id.filePath;
    if (path != null && _editor.state.bucket(workspaceId).isDirty(path)) {
      _workbench.promote(workspaceId, id);
    }
  }
}
```

3. In `openFile`'s floating branch, replace the `_workbench.openFloating(...)` block with `_openFloatingPreviewTab(workspaceId, WorkbenchTabId.file(normalized));` (keep the `await _editor.openFile(...)` line).
4. In `openDiff`'s floating branch, replace with `_openFloatingPreviewTab(workspaceId, tab);`.
5. In `client/lib/app/app_shell.dart`, where `WorkbenchEditorOpener(...)` is constructed (the `readFilePreviewInFloating:` argument), add:

```dart
readFloatingPreviewTabs: () =>
    layoutCubit.state.preferences.floatingPreviewTabs,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/workbench_editor_opener_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workbench/workbench_editor_opener.dart \
  client/lib/app/app_shell.dart \
  client/test/services/workbench/workbench_editor_opener_test.dart
git commit -m "feat(workbench): floating preview slot with dirty guard in editor opener"
```

---

### Task 5: Dirty-edit promotes (both strips) in `file_editor_surface`

**Files:**
- Modify: `client/lib/pages/workbench/file_editor_surface.dart:165-180`
- Test: covered by Task 4's opener tests + existing editor surface tests; add a cubit-level test in `client/test/cubits/workbench/workbench_cubit_test.dart` only if a direct one does not already exist from Task 2.

**Interfaces:**
- Consumes: Task 2 `WorkbenchCubit.promote`.
- Produces: no new API — behavioral change only.

- [ ] **Step 1: Update the dirty listener**

In `file_editor_surface.dart`, the existing `BlocListener<EditorCubit, EditorState>` (the one with the comment `// Center preview tabs pin on first edit; floating tabs are not in the workbench preview set so [pin] is a no-op there.`) calls `context.read<WorkbenchCubit>().pin(workspaceId, WorkbenchTabId.file(path))`.

Change the listener body to call `promote` instead (dirty means "make permanent", not "user pinned"):

```dart
listener: (context, state) {
  context.read<WorkbenchCubit>().promote(
    workspaceId,
    WorkbenchTabId.file(path),
  );
},
```

and replace the stale comment with:

```dart
// Dirty preview tabs promote (preview → normal) on first edit, on whichever
// strip hosts the tab — replacement would drop unsaved content.
```

`promote` routes by presence, so the same call promotes a center-strip preview tab and a floating-strip preview tab.

- [ ] **Step 2: Run the workbench + editor test suites**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/ test/services/workbench/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/workbench/file_editor_surface.dart
git commit -m "feat(workbench): dirty edit promotes preview tab on both strips"
```

---

### Task 6: Floating close pipeline skips pinned tabs

**Files:**
- Modify: `client/lib/services/floating_workspace/close_floating_tab.dart`
- Test: `client/test/services/floating_workspace/close_pinned_test.dart` (create)

**Interfaces:**
- Consumes: Task 2 pinned state on `bar.floating.pinnedIds`.
- Produces: `closeOtherFloatingTabs` / `closeFloatingTabsToTheRight` / `closeAllFloatingTabs` skip pinned ids.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/floating_workspace/close_pinned_test.dart`. Model the setup on `client/test/services/floating_workspace/floating_workspace_commands_test.dart` (registry construction — see `floating_surface_registry_test.dart` for `FloatingSurfaceRegistry` construction with real surfaces; reuse whichever pattern that test uses):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/floating_workspace/close_floating_tab.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';

void main() {
  test('closeAllFloatingTabs keeps pinned tabs', () {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry(); // adjust to actual ctor
    workbench.openFloating('ws', WorkbenchTabId.shell('e1'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e2'));
    workbench.pin('ws', WorkbenchTabId.shell('e2'));

    closeAllFloatingTabs(
      workbench: workbench,
      workspaceId: 'ws',
      registry: registry,
    );

    expect(
      workbench.floatingOrder('ws'),
      [WorkbenchTabId.shell('e2')],
    );
  });

  test('closeOtherFloatingTabs and closeFloatingTabsToTheRight keep pinned',
      () async {
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry(); // adjust to actual ctor
    workbench.openFloating('ws', WorkbenchTabId.shell('e1'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e2'));
    workbench.openFloating('ws', WorkbenchTabId.shell('e3'));
    workbench.pin('ws', WorkbenchTabId.shell('e3'));

    await closeOtherFloatingTabs(
      workbench: workbench,
      workspaceId: 'ws',
      registry: registry,
      keepId: WorkbenchTabId.shell('e1'),
    );
    expect(
      workbench.floatingOrder('ws'),
      [WorkbenchTabId.shell('e1'), WorkbenchTabId.shell('e3')],
    );

    await closeFloatingTabsToTheRight(
      workbench: workbench,
      workspaceId: 'ws',
      registry: registry,
      fromId: WorkbenchTabId.shell('e1'),
    );
    expect(
      workbench.floatingOrder('ws'),
      [WorkbenchTabId.shell('e1'), WorkbenchTabId.shell('e3')],
    );
  });
}
```

Before writing, read `client/test/services/floating_workspace/floating_surface_registry_test.dart` and adjust the `FloatingSurfaceRegistry()` construction line to the actual constructor (it may need surfaces registered). The assertion intent is what matters; construction details follow the existing test.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/floating_workspace/close_pinned_test.dart`
Expected: FAIL — pinned tab is closed.

- [ ] **Step 3: Implement**

In `close_floating_tab.dart`, add a private guard and use it in all three bulk helpers:

```dart
bool _isPinned(WorkbenchCubit workbench, String workspaceId, WorkbenchTabId id) {
  return workbench.state.bar(workspaceId).floating.pinnedIds.contains(id);
}
```

- In `closeOtherFloatingTabs`: skip when `id == keepId || _isPinned(...)`.
- In `closeFloatingTabsToTheRight`: filter `toClose` with `.where((id) => !_isPinned(workbench, workspaceId, id))`.
- In `closeAllFloatingTabs`: skip pinned ids in the loop.

Single-tab `closeFloatingTab` / `closeFloatingTabByBarId` stays **unprotected** — per spec, pin protects bulk user actions; the single-tab close affordance is removed in the UI while pinned (Task 7), and programmatic closes ignore pin.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/floating_workspace/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/floating_workspace/close_floating_tab.dart \
  client/test/services/floating_workspace/close_pinned_test.dart
git commit -m "feat(floating): pinned tabs survive closeOthers/closeRight/closeAll"
```

---

### Task 7: UI — pin icon, unpin, double-tap, floating strip projection

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/tab/tp_tab_chip.dart` (optional `onDoubleTap`, optional `pinned`)
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (`WorkbenchStripTabChip` pinned trailing + double-tap + onUnpin)
- Modify: `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart` (preview/pinned projection + pin callbacks)
- Modify: `client/lib/pages/floating_workspace/floating_workspace_panel.dart` (pass projection + callbacks)
- Modify: `client/lib/services/workbench/tab_menu/sources/builtin_close_tab_menu_source.dart` (pin entry shows for non-session tabs too)
- Modify: `client/lib/services/workbench/tab_menu/workbench_tab_menu_context.dart` (add `onUnpin`)
- Test: `client/test/widgets/workbench_strip_chip_pin_test.dart` (create), extend `client/test/pages/floating_workspace/` if a tab bar widget test file exists (check first; otherwise create `client/test/pages/floating_workspace/floating_workspace_tab_bar_test.dart`).

**Interfaces:**
- Consumes: Task 2 `WorkbenchCubit.pin/unpin/promote`; `bar.floating.previewIds/pinnedIds`.
- Produces:
  - `TpTabChip` new optional params: `VoidCallback? onDoubleTap`, `bool pinned = false` (pinned renders pin icon in place of close X; tap = unpin).
  - `WorkbenchStripTabChip` new params: `bool pinned` (exists), `VoidCallback? onUnpin`, `VoidCallback? onDoubleTap`.
  - `FloatingWorkspaceTabBar` new params: `Set<String> previewTabIds`, `Set<String> pinnedTabIds` (keyed by `FloatingTab.id` — the panel maps bar ids to tab ids via `barIdByTabId`), `ValueChanged<String>? onPin`, `ValueChanged<String>? onUnpin`.
  - `WorkbenchTabMenuContext` new field: `VoidCallback? onUnpin`.

- [ ] **Step 1: Write the failing widget tests**

Create `client/test/pages/floating_workspace/floating_workspace_tab_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_tab_bar.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('pinned tab shows pin icon instead of close', (tester) async {
    var unpinned = false;
    await tester.pumpWidget(_host(FloatingWorkspaceTabBar(
      tabs: [
        const FloatingTab(
          id: 'terminal:e1',
          surfaceId: 'terminal',
          title: 'Shell 1',
        ),
      ],
      activeTabId: 'terminal:e1',
      onSelect: (_) {},
      onClose: (_) {},
      onCloseOthers: (_) {},
      onCloseRight: (_) {},
      pinnedTabIds: {'terminal:e1'},
      onUnpin: (_) => unpinned = true,
    )));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byIcon(Icons.push_pin));
    await tester.pump();
    expect(unpinned, isTrue);
  });

  testWidgets('preview tab double-tap promotes; normal tab double-tap pins',
      (tester) async {
    // Tap-twice on the chip triggers onDoubleTap for that tab id.
    ...
  });
}
```

(The second test body follows the first's setup with `previewTabIds: {'terminal:e1'}` and assertions on the captured promote/pin callbacks — fill with the same pumpWidget shape, tapping the chip center twice with `warnIfMissed: false`.)

Before finalizing, check whether an existing `client/test/pages/floating_workspace/` directory has tab-bar tests to extend rather than duplicate.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/floating_workspace/floating_workspace_tab_bar_test.dart`
Expected: FAIL — `pinnedTabIds` / `onUnpin` params don't exist.

- [ ] **Step 3: Implement**

1. **`TpTabChip`** (`tp_tab_chip.dart`):
   - Add `this.onDoubleTap` (`VoidCallback?`) and `this.pinned = false` to the constructor/fields.
   - Pass `onDoubleTap` into the `TpHover(...)` call (check `TpHover`'s API; if it has no double-tap hook, wrap the chip's `Tooltip`/`TpHover` subtree in a `GestureDetector` with `onDoubleTap` alongside the existing tap handling — `behavior: HitTestBehavior.opaque` on the outer detector only if TpHover can't take it).
   - In the trailing chrome slot: when `widget.pinned` is true, render a pin icon button **instead of** `_TpTabCloseButton`:

```dart
_TpTabChromeSlot(
  visible: _showChrome,
  child: widget.pinned
      ? _TpTabPinButton(
          active: active,
          onTap: widget.onUnpin ?? widget.onClose,
        )
      : _TpTabCloseButton(active: active, onTap: widget.onClose),
),
```

   with a new private widget mirroring `_TpTabCloseButton` but showing `Icons.push_pin` (size `context.tpIconSizes.md`) and no hover rotation (keep it minimal):

```dart
class _TpTabPinButton extends StatelessWidget {
  const _TpTabPinButton({required this.onTap, required this.active});

  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = active ? cs.onSurface : cs.onSurfaceVariant;
    return TpHover(
      borderRadius: BorderRadius.circular(5),
      padding: const EdgeInsets.all(2),
      hoverColor: cs.onSurface.withValues(
        alpha: active ? 0.14 : 0.08,
      ),
      onTap: onTap,
      child: Icon(
        Icons.push_pin,
        size: context.tpIconSizes.md,
        color: tint,
      ),
    );
  }
}
```

   Add `final VoidCallback? onUnpin;` param, passed from hosts.

2. **`WorkbenchStripTabChip`** (`workspace_shell_tabs.dart`):
   - Add params: `this.onUnpin`, `this.onDoubleTap`.
   - Forward `pinned: widget.pinned`, `onUnpin: widget.onUnpin`, `onDoubleTap: widget.onDoubleTap` to `TpTabChip`.
   - Double-tap semantics live in the host callbacks (the chip stays presentation-only).

3. **Menu** — `workbench_tab_menu_context.dart` gains `this.onUnpin` / `final VoidCallback? onUnpin;`. `builtin_close_tab_menu_source.dart` pin entry: change the guard from `ctx.pinnable && ctx.onPin != null` to also show when `ctx.onUnpin != null` (pinned state uses onUnpin), label already switches on `ctx.pinned` (`l10n.unpinConversation` / `l10n.pinConversation`). Action: `ctx.pinned ? ctx.onUnpin! : ctx.onPin!`.

4. **`FloatingWorkspaceTabBar`** (`floating_workspace_tab_bar.dart`):
   - New params: `Set<String> previewTabIds = const {}`, `Set<String> pinnedTabIds = const {}`, `ValueChanged<String>? onPin`, `ValueChanged<String>? onUnpin` (String = `FloatingTab.id`).
   - In `itemBuilder`, compute `preview` / `pinned` from the sets and pass to `WorkbenchStripTabChip` along with:

```dart
onPin: preview || pinned ? (onPin != null || onUnpin != null ? () {
  if (pinned) {
      onUnpin?.call(tab.id);
  } else if (preview) {
      onPin?.call(tab.id); // promote handled by host mapping
  }
} : null) : null,
```

   (The host maps `FloatingTab.id` → `WorkbenchTabId` and decides promote vs pin — see step 5.)
   - `onDoubleTap`: pass a callback that the host resolves (`widget.onDoubleTap` new param `void Function(String tabId)?`).

5. **`floating_workspace_panel.dart`** — in `_PanelChromeFrame` build, where `FloatingWorkspaceTabBar(...)` is constructed, add:

```dart
previewTabIds: {
  for (final id in strip.order)
    if (strip.previewIds.contains(id)) barIdToTabId[id]!,
},
pinnedTabIds: {
  for (final id in strip.order)
    if (strip.pinnedIds.contains(id)) barIdToTabId[id]!,
},
```

(`barIdToTabId` is the inverse of the existing `barIdByTabId` map — build it alongside: `final tabIdByBarId = {for (final e in barIdByTabId.entries) e.value: e.key};`.) The panel already has `strip` from the projection. Then:

```dart
onPin: (tabId) {
  final barId = widget.barIdByTabId[tabId];
  if (barId == null) return;
  final strip = context.read<WorkbenchCubit>()
      .state.bar(widget.workspaceId).floating;
  if (strip.previewIds.contains(barId)) {
    context.read<WorkbenchCubit>()
        .promote(widget.workspaceId, barId);
  } else {
    context.read<WorkbenchCubit>()
        .pin(widget.workspaceId, barId);
  }
},
onUnpin: (tabId) {
  final barId = widget.barIdByTabId[tabId];
  if (barId == null) return;
  context.read<WorkbenchCubit>().unpin(widget.workspaceId, barId);
},
onDoubleTap: (tabId) {
  final barId = widget.barIdByTabId[tabId];
  if (barId == null) return;
  final strip = context.read<WorkbenchCubit>()
      .state.bar(widget.workspaceId).floating;
  if (strip.previewIds.contains(barId)) {
    context.read<WorkbenchCubit>()
        .promote(widget.workspaceId, barId);
  } else if (strip.pinnedIds.contains(barId)) {
    context.read<WorkbenchCubit>().unpin(widget.workspaceId, barId);
  } else {
    context.read<WorkbenchCubit>().pin(widget.workspaceId, barId);
  }
},
```

Also pass `onClose: null` (omit the param) for pinned tabs so the single-close affordance is the pin icon (unpin) — practical approach: in `FloatingWorkspaceTabBar.itemBuilder`, when `pinned`, pass `onClose: () {}` no-op? No — cleaner: the `TpTabChip` pinned trailing already swaps X for the pin icon, so `onClose` is simply never reachable while pinned. No change needed to `onClose` wiring.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/floating_workspace/ test/widgets/`
Expected: PASS.

Run full static check: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/tab/tp_tab_chip.dart \
  client/lib/pages/workspace_shell/workspace_shell_tabs.dart \
  client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart \
  client/lib/pages/floating_workspace/floating_workspace_panel.dart \
  client/lib/services/workbench/tab_menu/ \
  client/test/
git commit -m "feat(ui): pin icon / unpin / double-tap on floating strip tabs"
```

---

### Task 8: Center-strip session pinned migration + full verification

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (drop `sessionPinned` projection, pin handler routes to WorkbenchCubit)
- Modify: `client/lib/services/workbench/workbench_tab_projection.dart` (drop `sessionPinned` param, read from `previewTabIds`'s sibling)
- Modify: `client/lib/pages/chat/chat_page_structural_signal.dart` (drop `pinnedBySessionId`)
- Test: `client/test/services/workbench/workbench_tab_projection_test.dart`

**Interfaces:**
- Consumes: Task 2 `WorkbenchCubit.pin/unpin`; Task 1 `TabStrip.pinnedIds`.
- Produces: single source of truth for pinned state = `TabStrip.pinnedIds`; `projectWorkbenchTabs` signature without `sessionPinned`.

⚠️ This is the riskiest task (touches session persistence semantics: `AppSession.pinned` in the session repo is the durable store; the strip is runtime state). **Scope decision: keep `AppSession.pinned` as the persisted source; the chat-page pin handler writes BOTH the repo (`toggleSessionPin`) and the strip (`WorkbenchCubit.pin/unpin`).** The projection reads the strip. `chat_page_structural_signal.pinnedBySessionId` is deleted; the structural signal no longer carries pinned.

- [ ] **Step 1: Write the failing test**

Extend `client/test/services/workbench/workbench_tab_projection_test.dart` (read it first; adapt to its existing fixtures): the `pinned` field on session `TabInfo` comes from the new `pinnedTabIds` param instead of `sessionPinned`:

```dart
test('session pinned reads pinnedTabIds', () {
  final tabs = projectWorkbenchTabs(
    tabOrder: [WorkbenchTabId.session('s1')],
    sessionTitles: {'s1': 'Session'},
    sessionWorking: const {},
    sessionCli: const {},
    editorBucket: WorkspaceEditorBucket(),
    previewTabIds: const {},
    pinnedTabIds: {WorkbenchTabId.session('s1')},
  );
  expect(tabs.single.pinned, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/workbench_tab_projection_test.dart`
Expected: FAIL — no `pinnedTabIds` param.

- [ ] **Step 3: Implement**

1. `workbench_tab_projection.dart`: replace the `sessionPinned` parameter with `Set<WorkbenchTabId> pinnedTabIds = const {}`; session `TabInfo.pinned` becomes `pinnedTabIds.contains(tab)`. File/diff `TabInfo` also gain `pinned: pinnedTabIds.contains(tab)` for consistency.
2. `chat_page_shell.dart`:
   - Remove the `sessionPinned` signal usage; pass `pinnedTabIds: bar.center.pinnedIds` to `projectWorkbenchTabs`.
   - `onTabPin` handler: keep calling `cubit.toggleSessionPin(sessionId)` (persists), and add the strip write:

```dart
onTabPin: routeActive
    ? (index) {
        if (index < 0 || index >= order.length) return;
        final sessionId = order[index].sessionId;
        if (sessionId == null) return;
        unawaited(cubit.toggleSessionPin(sessionId));
        final tabId = WorkbenchTabId.session(sessionId);
        final strip = workbenchCubit.state.bar(workspaceId).center;
        if (strip.pinnedIds.contains(tabId)) {
          workbenchCubit.unpin(workspaceId, tabId);
        } else {
          workbenchCubit.pin(workspaceId, tabId);
        }
      }
    : null,
```

   (use the actual `WorkbenchCubit` handle available in that build scope — it is `context.read<WorkbenchCubit>()` or an existing local, follow the file's pattern).
3. `chat_page_structural_signal.dart`: delete `pinnedBySessionId` field, constructor param, equality/hash usage, and `_pinnedForTabIds`.

Note: on session re-open after restart the strip starts empty, so `bar.center.pinnedIds` seeds empty even for persisted-pinned sessions. To keep the sidebar "pinned" indicator honest, **`chat_page_shell`'s projection passes `pinnedTabIds: bar.center.pinnedIds` UNION persisted-pinned session ids that have open tabs**:

```dart
final persistedPinned = {
  for (final t in order)
    if (t.kind == WorkbenchTabKind.session && (state.sessions
            .firstWhereOrNull((s) => s.sessionId == t.id)
            ?.pinned ??
        false))
      t,
};
final pinnedTabIds = bar.center.pinnedIds.union(persistedPinned);
```

(`state` is the `ChatState` already in scope in that builder; `firstWhereOrNull` needs `package:collection` — already imported in most of these files; verify.) The strip write in `onTabPin` keeps both stores in sync while the app runs.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/workbench/ test/pages/chat/`
Expected: PASS.

- [ ] **Step 5: Full verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```
Expected: analyze clean, full suite PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat/chat_page_shell.dart \
  client/lib/pages/chat/chat_page_structural_signal.dart \
  client/lib/services/workbench/workbench_tab_projection.dart \
  client/test/services/workbench/workbench_tab_projection_test.dart
git commit -m "refactor(workbench): session pinned state unified on TabStrip.pinnedIds"
```

---

## Self-Review Notes (already applied)

- Spec coverage: three-state model (T1), openFloating preview + dirty guard (T2/T4), dirty-edit promotes (T5), close protection both strips (T2/T6), pin icon/unpin/double-tap/menu (T7), config pref (T3), session pinned migration (T8), persistence-by-design none (strip state is runtime-only — matches spec).
- Type consistency: `promote/pin/unpin` signatures identical across T1/T2/T5/T7; `openFloating` return type `WorkbenchTabId?` consistent T2/T4; `pinnedTabIds` set-of-`WorkbenchTabId` in projection vs set-of-`String` (`FloatingTab.id`) in the floating bar — different types on purpose (bar ids vs panel tab ids), documented at interface sites.
- Task 4 and Task 6 tests contain "adjust to actual API" notes where the plan author could not fully verify constructor shapes — the implementing agent must read the neighboring test file first; this is called out inside the tasks.
