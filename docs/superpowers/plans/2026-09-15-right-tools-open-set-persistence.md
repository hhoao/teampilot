# Right Tools Open-Set Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the right-tools open/selected/dismissed tab set globally, restore it across session-type switches and app restarts, and auto-open members/mailbox on team entry unless the user already closed them.

**Architecture:** A pure `RightToolOpenSet` in `models/` owns open/close/select/team-seed. `LayoutPreferences` stores the triple. `WorkspaceToolsCubit` holds one global set, hydrates after `LayoutCubit.load()`, and writes through on mutation. `TabbedPanel` still displays `openIds ∩ catalog` and must stop deleting remembered ids when the catalog shrinks.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `LayoutCubit` / `LayoutRepository` JSON prefs, `cd client && dart run tool/run_tests.dart`.

**Spec:** `docs/superpowers/specs/2026-09-15-right-tools-open-set-persistence-design.md`

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart ...`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- No new settings UI. Do not auto-show the right-tools pane (`rightToolsVisible` unchanged).
- Do not remember a different set per workspace or per team. Scope ids on `WorkspaceToolsCubit` APIs stay for call-site compatibility but are ignored for storage.
- Do not auto-seed board or file tree. Team seed ids are only `members` then `mailbox`.
- Preserve unrelated existing worktree changes.
- Inner loop: analyze + one test file. Full suite only once before claiming done.

## File structure

| File | Responsibility |
| --- | --- |
| Create `client/lib/models/right_tool_open_set.dart` | Pure open/selected/dismissed model, sanitization, team seed. Lives in `models/` so layout + cubit do not import `widgets/`. |
| Create `client/test/models/right_tool_open_set_test.dart` | Unit tests for the helper. |
| Modify `client/lib/models/layout_preferences.dart` | Persist `rightToolOpenIds`, `rightToolSelectedId`, `rightToolDismissedIds`. |
| Modify `client/test/models/layout_preferences_default_test.dart` | JSON round-trip and unknown-id stripping. |
| Modify `client/lib/cubits/layout_cubit.dart` | `setRightToolOpenSet`. |
| Modify `client/test/cubits/layout_cubit_preferences_test.dart` | Persist/reload the triple. |
| Modify `client/lib/cubits/workspace_tools_cubit.dart` | One global `RightToolOpenSet`; hydrate; persist callback; `seedTeamDefaults`; prune/removeWorkspace no longer drop remembered tools. |
| Modify `client/test/cubits/workspace_tools_cubit_test.dart` | Replace per-scope and `openDefaultsIfEmpty` tests. |
| Modify `client/lib/widgets/right_tools/right_tool_ids.dart` | Remove `mixedTeamDefaults`; add `teamSeedIds` pointing at the same two ids. |
| Modify `client/lib/widgets/right_tools/right_tools_tool_views.dart` | Native+mixed team seed via `seedTeamDefaults`. |
| Modify `client/lib/app/app_shell.dart` | Persist callback + hydrate after `layoutCubit.load()`. |
| Modify `client/test/widgets/right_tools_tabbed_panel_test.dart` | Catalog shrink must not delete remembered ids. |

---

### Task 1: Pure `RightToolOpenSet`

**Files:**
- Create: `client/lib/models/right_tool_open_set.dart`
- Test: `client/test/models/right_tool_open_set_test.dart`

**Interfaces:**
- Consumes: none.
- Produces:
  - `class RightToolOpenSet` with `List<String> openIds`, `String? selectedId`, `List<String> dismissedIds`
  - `static const Set<String> knownIds`
  - `static const List<String> teamSeedIds` (`members`, `mailbox`)
  - `static List<String> sanitizeIds(Object? raw)`
  - `static String? sanitizeSelected(Object? raw)`
  - `static RightToolOpenSet sanitize({required List<String> openIds, String? selectedId, required List<String> dismissedIds})`
  - `List<String> visibleOpenIds(Iterable<String> catalog)`
  - `String? visibleSelectedId(Iterable<String> catalog)`
  - `RightToolOpenSet opened(String toolId)`
  - `RightToolOpenSet closed(String toolId, {required Iterable<String> catalog})`
  - `RightToolOpenSet selected(String toolId)`
  - `RightToolOpenSet seededForTeam(Iterable<String> catalog)`
  - `RightToolOpenSet copyWith({List<String>? openIds, String? selectedId, bool clearSelectedId = false, List<String>? dismissedIds})`

- [ ] **Step 1: Write the failing tests**

Create `client/test/models/right_tool_open_set_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/right_tool_open_set.dart';

void main() {
  group('RightToolOpenSet', () {
    test('sanitizeIds drops unknown, blanks, and duplicates, keeps order', () {
      expect(
        RightToolOpenSet.sanitizeIds(const [
          'members',
          'nope',
          'members',
          'fileTree',
          1,
          '',
        ]),
        ['members', 'fileTree'],
      );
      expect(RightToolOpenSet.sanitizeIds(null), isEmpty);
      expect(RightToolOpenSet.sanitizeIds('members'), isEmpty);
    });

    test('sanitize drops dismissed ids that are also open', () {
      final set = RightToolOpenSet.sanitize(
        openIds: const ['members', 'mailbox'],
        selectedId: 'bogus',
        dismissedIds: const ['mailbox', 'board', 'nope'],
      );
      expect(set.openIds, ['members', 'mailbox']);
      expect(set.selectedId, isNull);
      expect(set.dismissedIds, ['board']);
    });

    test('visible intersection keeps hidden ids in memory', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree', 'mailbox'],
        selectedId: 'members',
      );
      expect(set.visibleOpenIds(const ['fileTree', 'git']), ['fileTree']);
      expect(set.visibleSelectedId(const ['fileTree', 'git']), 'fileTree');
      expect(set.openIds, ['members', 'fileTree', 'mailbox']);
      expect(set.selectedId, 'members');
    });

    test('opened adds, selects, and clears dismissed', () {
      const set = RightToolOpenSet(
        openIds: ['fileTree'],
        selectedId: 'fileTree',
        dismissedIds: ['mailbox', 'board'],
      );
      final next = set.opened('mailbox');
      expect(next.openIds, ['fileTree', 'mailbox']);
      expect(next.selectedId, 'mailbox');
      expect(next.dismissedIds, ['board']);
    });

    test('closed records dismissed and reselects a visible neighbor', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree', 'mailbox'],
        selectedId: 'fileTree',
      );
      final next = set.closed('fileTree', catalog: const ['members', 'fileTree', 'mailbox']);
      expect(next.openIds, ['members', 'mailbox']);
      expect(next.dismissedIds, ['fileTree']);
      expect(next.selectedId, 'members');
    });

    test('closed keeps unavailable ids and can clear visible selection', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree'],
        selectedId: 'fileTree',
      );
      final next = set.closed(
        'fileTree',
        catalog: const ['fileTree'],
      );
      expect(next.openIds, ['members']);
      expect(next.dismissedIds, ['fileTree']);
      expect(next.selectedId, isNull);
      expect(next.visibleOpenIds(const ['fileTree']), isEmpty);
    });

    test('selected opens if needed', () {
      const set = RightToolOpenSet(openIds: ['fileTree'], selectedId: 'fileTree');
      final next = set.selected('git');
      expect(next.openIds, ['fileTree', 'git']);
      expect(next.selectedId, 'git');
    });

    test('team seed appends members and mailbox when available and not dismissed', () {
      const set = RightToolOpenSet(
        openIds: ['fileTree'],
        selectedId: 'fileTree',
      );
      final next = set.seededForTeam(const ['fileTree', 'members', 'mailbox', 'board']);
      expect(next.openIds, ['fileTree', 'members', 'mailbox']);
      expect(next.selectedId, 'fileTree');
      expect(next.dismissedIds, isEmpty);
    });

    test('team seed skips mailbox when it is not in the catalog', () {
      const set = RightToolOpenSet();
      final next = set.seededForTeam(const ['members', 'fileTree']);
      expect(next.openIds, ['members']);
      expect(next.selectedId, 'members');
    });

    test('team seed does not revive dismissed mailbox', () {
      const set = RightToolOpenSet(
        openIds: ['members'],
        selectedId: 'members',
        dismissedIds: ['mailbox'],
      );
      final next = set.seededForTeam(const ['members', 'mailbox']);
      expect(next.openIds, ['members']);
      expect(next.dismissedIds, ['mailbox']);
    });

    test('empty open set still seeds team tools', () {
      const set = RightToolOpenSet();
      final next = set.seededForTeam(const ['members', 'mailbox', 'board']);
      expect(next.openIds, ['members', 'mailbox']);
      expect(next.selectedId, 'members');
    });

    test('native then mixed seeds mailbox once it is available', () {
      final native = const RightToolOpenSet().seededForTeam(const ['members']);
      expect(native.openIds, ['members']);
      final mixed = native.seededForTeam(const ['members', 'mailbox']);
      expect(mixed.openIds, ['members', 'mailbox']);
    });

    test('team seed does not add board', () {
      final next = const RightToolOpenSet().seededForTeam(
        const ['members', 'mailbox', 'board'],
      );
      expect(next.openIds, isNot(contains('board')));
    });

    test('seed is a no-op when there is nothing to add', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'mailbox'],
        selectedId: 'mailbox',
      );
      expect(set.seededForTeam(const ['members', 'mailbox']), same(set));
    });
  });
}
```

- [ ] **Step 2: Run the new test file and verify it fails to compile / import**

Run: `cd client && dart run tool/run_tests.dart test/models/right_tool_open_set_test.dart`

Expected: FAIL because `package:teampilot/models/right_tool_open_set.dart` does not exist.

- [ ] **Step 3: Implement `RightToolOpenSet`**

Create `client/lib/models/right_tool_open_set.dart`:

```dart
class RightToolOpenSet {
  const RightToolOpenSet({
    this.openIds = const [],
    this.selectedId,
    this.dismissedIds = const [],
  });

  static const knownIds = {
    'members',
    'fileTree',
    'git',
    'mailbox',
    'board',
    'search',
  };

  static const teamSeedIds = ['members', 'mailbox'];

  final List<String> openIds;
  final String? selectedId;
  final List<String> dismissedIds;

  static List<String> sanitizeIds(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      if (value is! String || value.isEmpty) continue;
      if (!knownIds.contains(value)) continue;
      if (!seen.add(value)) continue;
      out.add(value);
    }
    return out;
  }

  static String? sanitizeSelected(Object? raw) {
    if (raw is! String || raw.isEmpty || !knownIds.contains(raw)) return null;
    return raw;
  }

  static RightToolOpenSet sanitize({
    required List<String> openIds,
    String? selectedId,
    required List<String> dismissedIds,
  }) {
    final open = sanitizeIds(openIds);
    final openSet = open.toSet();
    final dismissed = [
      for (final id in sanitizeIds(dismissedIds))
        if (!openSet.contains(id)) id,
    ];
    final selected = sanitizeSelected(selectedId);
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissed,
    );
  }

  List<String> visibleOpenIds(Iterable<String> catalog) {
    final available = catalog.toSet();
    return [for (final id in openIds) if (available.contains(id)) id];
  }

  String? visibleSelectedId(Iterable<String> catalog) {
    final visible = visibleOpenIds(catalog);
    if (selectedId != null && visible.contains(selectedId)) return selectedId;
    return visible.isEmpty ? null : visible.last;
  }

  RightToolOpenSet opened(String toolId) {
    if (!knownIds.contains(toolId)) return this;
    final open = [...openIds];
    if (!open.contains(toolId)) open.add(toolId);
    final dismissed = [for (final id in dismissedIds) if (id != toolId) id];
    if (_listEquals(open, openIds) &&
        selectedId == toolId &&
        _listEquals(dismissed, dismissedIds)) {
      return this;
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: toolId,
      dismissedIds: dismissed,
    );
  }

  RightToolOpenSet selected(String toolId) => opened(toolId);

  RightToolOpenSet closed(String toolId, {required Iterable<String> catalog}) {
    final index = openIds.indexOf(toolId);
    if (index < 0) return this;
    final open = [...openIds]..removeAt(index);
    final dismissed = dismissedIds.contains(toolId)
        ? dismissedIds
        : [...dismissedIds, toolId];
    String? selected = selectedId;
    if (selected == toolId) {
      final before = visibleOpenIds(catalog);
      final visibleIndex = before.indexOf(toolId);
      final after = [for (final id in open) if (catalog.toSet().contains(id)) id];
      if (after.isEmpty) {
        selected = null;
      } else if (visibleIndex > 0) {
        selected = before[visibleIndex - 1];
      } else {
        selected = after.first;
      }
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissed,
    );
  }

  RightToolOpenSet seededForTeam(Iterable<String> catalog) {
    final available = catalog.toSet();
    final open = [...openIds];
    final dismissed = dismissedIds.toSet();
    final added = <String>[];
    for (final id in teamSeedIds) {
      if (!available.contains(id)) continue;
      if (open.contains(id)) continue;
      if (dismissed.contains(id)) continue;
      open.add(id);
      added.add(id);
    }
    if (added.isEmpty) return this;
    final visible = [for (final id in open) if (available.contains(id)) id];
    var selected = selectedId;
    final hasVisibleSelection =
        selected != null && visible.contains(selected);
    if (!hasVisibleSelection && visible.isNotEmpty) {
      if (added.contains('members') && visible.contains('members')) {
        selected = 'members';
      } else {
        selected = added.firstWhere(
          visible.contains,
          orElse: () => visible.last,
        );
      }
    }
    return RightToolOpenSet(
      openIds: open,
      selectedId: selected,
      dismissedIds: dismissedIds,
    );
  }

  RightToolOpenSet copyWith({
    List<String>? openIds,
    String? selectedId,
    bool clearSelectedId = false,
    List<String>? dismissedIds,
  }) => RightToolOpenSet(
    openIds: openIds ?? this.openIds,
    selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
    dismissedIds: dismissedIds ?? this.dismissedIds,
  );

  @override
  bool operator ==(Object other) =>
      other is RightToolOpenSet &&
      _listEquals(openIds, other.openIds) &&
      selectedId == other.selectedId &&
      _listEquals(dismissedIds, other.dismissedIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(openIds),
    selectedId,
    Object.hashAll(dismissedIds),
  );
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

In `closed`, build `catalog.toSet()` once (`final available = catalog.toSet();`) instead of calling `catalog.toSet()` in the loop.

- [ ] **Step 4: Run the tests and verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/right_tool_open_set_test.dart`

Expected: PASS, all `RightToolOpenSet` tests.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/right_tool_open_set.dart client/test/models/right_tool_open_set_test.dart
git commit -m "$(cat <<'EOF'
Add RightToolOpenSet for persisted right-tools tabs.

EOF
)"
```

---

### Task 2: Persist the triple on layout preferences

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/models/layout_preferences_default_test.dart`
- Test: `client/test/cubits/layout_cubit_preferences_test.dart`

**Interfaces:**
- Consumes: `RightToolOpenSet.sanitizeIds`, `RightToolOpenSet.sanitizeSelected`.
- Produces:
  - `LayoutPreferences.rightToolOpenIds` (`List<String>`, default `const []`)
  - `LayoutPreferences.rightToolSelectedId` (`String?`, default `null`)
  - `LayoutPreferences.rightToolDismissedIds` (`List<String>`, default `const []`)
  - `LayoutPreferences.copyWith({..., List<String>? rightToolOpenIds, String? rightToolSelectedId, bool clearRightToolSelectedId = false, List<String>? rightToolDismissedIds})`
  - `Future<void> LayoutCubit.setRightToolOpenSet(RightToolOpenSet set)`

- [ ] **Step 1: Write the failing preference tests**

Append to `client/test/models/layout_preferences_default_test.dart`:

```dart
  test('right-tool open set defaults empty and round-trips', () {
    expect(const LayoutPreferences().rightToolOpenIds, isEmpty);
    expect(const LayoutPreferences().rightToolSelectedId, isNull);
    expect(const LayoutPreferences().rightToolDismissedIds, isEmpty);
    expect(LayoutPreferences.fromJson(const {}).rightToolOpenIds, isEmpty);

    final parsed = LayoutPreferences.fromJson(const {
      'rightToolOpenIds': ['members', 'nope', 'mailbox', 'members'],
      'rightToolSelectedId': 'mailbox',
      'rightToolDismissedIds': ['board', 'bogus'],
    });
    expect(parsed.rightToolOpenIds, ['members', 'mailbox']);
    expect(parsed.rightToolSelectedId, 'mailbox');
    expect(parsed.rightToolDismissedIds, ['board']);

    final restored = LayoutPreferences.fromJson(parsed.toJson());
    expect(restored.rightToolOpenIds, ['members', 'mailbox']);
    expect(restored.rightToolSelectedId, 'mailbox');
    expect(restored.rightToolDismissedIds, ['board']);
  });

  test('rightToolSelectedId unknown values become null', () {
    expect(
      LayoutPreferences.fromJson(const {
        'rightToolSelectedId': 'nope',
      }).rightToolSelectedId,
      isNull,
    );
  });

  test('copyWith can clear rightToolSelectedId', () {
    const prefs = LayoutPreferences(
      rightToolOpenIds: ['members'],
      rightToolSelectedId: 'members',
    );
    final cleared = prefs.copyWith(clearRightToolSelectedId: true);
    expect(cleared.rightToolSelectedId, isNull);
    expect(cleared.rightToolOpenIds, ['members']);
  });
```

Append to `client/test/cubits/layout_cubit_preferences_test.dart`:

```dart
  test('setRightToolOpenSet updates state and persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    await cubit.load();

    await cubit.setRightToolOpenSet(
      const RightToolOpenSet(
        openIds: ['members', 'mailbox'],
        selectedId: 'members',
        dismissedIds: ['board'],
      ),
    );
    expect(cubit.state.preferences.rightToolOpenIds, ['members', 'mailbox']);
    expect(cubit.state.preferences.rightToolSelectedId, 'members');
    expect(cubit.state.preferences.rightToolDismissedIds, ['board']);

    await cubit.setRightToolOpenSet(
      const RightToolOpenSet(openIds: ['fileTree'], dismissedIds: ['members']),
    );
    expect(cubit.state.preferences.rightToolSelectedId, isNull);

    final reloaded = LayoutCubit(repository: LayoutRepository(prefs));
    await reloaded.load();
    expect(reloaded.state.preferences.rightToolOpenIds, ['fileTree']);
    expect(reloaded.state.preferences.rightToolSelectedId, isNull);
    expect(reloaded.state.preferences.rightToolDismissedIds, ['members']);
  });
```

Add `import 'package:teampilot/models/right_tool_open_set.dart';` to the cubit test file.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart --plain-name "right-tool open set"`

Expected: FAIL because `rightToolOpenIds` is not defined on `LayoutPreferences`.

- [ ] **Step 3: Add the three fields to `LayoutPreferences`**

In `client/lib/models/layout_preferences.dart`:

1. Import `right_tool_open_set.dart`.
2. Add constructor args after `floatingPreviewTabs` (defaults `const []` / `null` / `const []`):

```dart
    this.rightToolOpenIds = const [],
    this.rightToolSelectedId,
    this.rightToolDismissedIds = const [],
```

3. In `fromJson`, after the other fields:

```dart
      rightToolOpenIds: RightToolOpenSet.sanitizeIds(json['rightToolOpenIds']),
      rightToolSelectedId: RightToolOpenSet.sanitizeSelected(
        json['rightToolSelectedId'],
      ),
      rightToolDismissedIds: RightToolOpenSet.sanitizeIds(
        json['rightToolDismissedIds'],
      ),
```

Then wrap those three through `RightToolOpenSet.sanitize(...)` so an id cannot be both open and dismissed at load:

```dart
    final openSet = RightToolOpenSet.sanitize(
      openIds: RightToolOpenSet.sanitizeIds(json['rightToolOpenIds']),
      selectedId: RightToolOpenSet.sanitizeSelected(json['rightToolSelectedId']),
      dismissedIds: RightToolOpenSet.sanitizeIds(json['rightToolDismissedIds']),
    );
    return LayoutPreferences(
      // ...existing fields...
      rightToolOpenIds: openSet.openIds,
      rightToolSelectedId: openSet.selectedId,
      rightToolDismissedIds: openSet.dismissedIds,
    );
```

Do **not** duplicate the existing `return LayoutPreferences(` body. Assign `openSet` first, then pass the three fields into the existing factory `return`.

4. Add the three public fields next to `floatingPreviewTabs`.
5. Extend `copyWith` with:

```dart
    List<String>? rightToolOpenIds,
    String? rightToolSelectedId,
    bool clearRightToolSelectedId = false,
    List<String>? rightToolDismissedIds,
```

and in the constructed object:

```dart
      rightToolOpenIds: rightToolOpenIds ?? this.rightToolOpenIds,
      rightToolSelectedId: clearRightToolSelectedId
          ? null
          : (rightToolSelectedId ?? this.rightToolSelectedId),
      rightToolDismissedIds:
          rightToolDismissedIds ?? this.rightToolDismissedIds,
```

6. In `withAtLeastOneToolVisible`'s manual `LayoutPreferences(` constructor, pass:

```dart
      rightToolOpenIds: rightToolOpenIds,
      rightToolSelectedId: rightToolSelectedId,
      rightToolDismissedIds: rightToolDismissedIds,
```

If these are omitted, every `copyWith` will wipe the open set back to empty.

7. In `toJson`:

```dart
      'rightToolOpenIds': rightToolOpenIds,
      'rightToolSelectedId': rightToolSelectedId,
      'rightToolDismissedIds': rightToolDismissedIds,
```

- [ ] **Step 4: Add `LayoutCubit.setRightToolOpenSet`**

In `client/lib/cubits/layout_cubit.dart` import `../models/right_tool_open_set.dart` and add:

```dart
  Future<void> setRightToolOpenSet(RightToolOpenSet set) => _save(
    state.preferences.copyWith(
      rightToolOpenIds: set.openIds,
      rightToolSelectedId: set.selectedId,
      clearRightToolSelectedId: set.selectedId == null,
      rightToolDismissedIds: set.dismissedIds,
    ),
  );
```

- [ ] **Step 5: Run the focused tests and verify they pass**

Run:

```bash
cd client && dart run tool/run_tests.dart test/models/layout_preferences_default_test.dart --plain-name "right-tool"
cd client && dart run tool/run_tests.dart test/cubits/layout_cubit_preferences_test.dart --plain-name "setRightToolOpenSet"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart \
  client/test/models/layout_preferences_default_test.dart \
  client/test/cubits/layout_cubit_preferences_test.dart
git commit -m "$(cat <<'EOF'
Persist right-tools open, selected, and dismissed ids.

EOF
)"
```

---

### Task 3: Global `WorkspaceToolsCubit` with hydrate/persist

**Files:**
- Modify: `client/lib/cubits/workspace_tools_cubit.dart`
- Test: `client/test/cubits/workspace_tools_cubit_test.dart`

**Interfaces:**
- Consumes: `RightToolOpenSet`, `LayoutCubit.setRightToolOpenSet` (via optional persist callback).
- Produces:
  - `WorkspaceToolsState.openSet` (`RightToolOpenSet`) — no per-scope maps
  - `WorkspaceToolsCubit({RightToolOpenSet initial = const RightToolOpenSet(), void Function(RightToolOpenSet set)? persist})`
  - `void hydrate(RightToolOpenSet set)` — emit only; do not call `persist`
  - `List<String> openIdsFor(String scopeId)` — returns `state.openSet.openIds` (scope ignored)
  - `String? selectedIdFor(String scopeId)` — returns `state.openSet.selectedId`
  - `void seedTeamDefaults(String scopeId, Iterable<String> catalogIds)`
  - `void pruneToAvailable(String scopeId, Iterable<String> availableIds)` — no-op (catalog shrink must not drop memory)
  - `void removeWorkspace(String scopeId)` — no-op (closing a workspace tab must not clear the set)
  - Delete `openDefaultsIfEmpty`

Keep `ensureOpenAndSelect`, `selectTool`, and `closeTool` signatures so `TabbedPanel` call sites stay unchanged. `closeTool` must pass the current catalog... **TabbedPanel does not currently pass catalog into close.** Visible-neighbor selection therefore needs the catalog at close time.

Change `closeTool` to:

```dart
void closeTool(String scopeId, String toolId, {Iterable<String> catalog = const []})
```

If `catalog` is empty, treat catalog as `state.openSet.openIds` so existing tests that omit catalog still pick a neighbor from the full open list. `TabbedPanel` in Task 4 will pass `_catalogIds`.

- [ ] **Step 1: Rewrite `client/test/cubits/workspace_tools_cubit_test.dart` as failing tests against the new API**

Replace the file contents with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/models/right_tool_open_set.dart';

void main() {
  group('WorkspaceToolsCubit', () {
    test('defaults to an empty open set for every scope', () {
      final cubit = WorkspaceToolsCubit();
      expect(cubit.openIdsFor('p1'), isEmpty);
      expect(cubit.selectedIdFor('p1'), isNull);
      expect(cubit.openIdsFor('p2'), isEmpty);
      addTearDown(cubit.close);
    });

    test('open and select are global across scopes', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'fileTree');
      cubit.ensureOpenAndSelect('p2', 'git');
      expect(cubit.openIdsFor('p1'), ['fileTree', 'git']);
      expect(cubit.openIdsFor('other'), ['fileTree', 'git']);
      expect(cubit.selectedIdFor('p1'), 'git');
      addTearDown(cubit.close);
    });

    test('closeTool records dismissed and persists', () {
      final persisted = <RightToolOpenSet>[];
      final cubit = WorkspaceToolsCubit(persist: persisted.add)
        ..ensureOpenAndSelect('p1', 'members')
        ..ensureOpenAndSelect('p1', 'mailbox');
      cubit.closeTool(
        'p1',
        'mailbox',
        catalog: const ['members', 'mailbox'],
      );
      expect(cubit.openIdsFor('p1'), ['members']);
      expect(cubit.state.openSet.dismissedIds, ['mailbox']);
      expect(persisted.last.dismissedIds, ['mailbox']);
      addTearDown(cubit.close);
    });

    test('pruneToAvailable does not drop ids missing from this catalog', () {
      final cubit = WorkspaceToolsCubit()
        ..ensureOpenAndSelect('p1', 'members')
        ..ensureOpenAndSelect('p1', 'fileTree');
      cubit.pruneToAvailable('p1', const ['fileTree', 'git']);
      expect(cubit.openIdsFor('p1'), ['members', 'fileTree']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('seedTeamDefaults appends even when file tree is already open', () {
      final cubit = WorkspaceToolsCubit()
        ..ensureOpenAndSelect('p1', 'fileTree');
      cubit.seedTeamDefaults('p1', const ['fileTree', 'members', 'mailbox']);
      expect(cubit.openIdsFor('p1'), ['fileTree', 'members', 'mailbox']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('hydrate replaces state without persisting', () {
      final persisted = <RightToolOpenSet>[];
      final cubit = WorkspaceToolsCubit(persist: persisted.add);
      cubit.hydrate(
        const RightToolOpenSet(
          openIds: ['mailbox'],
          selectedId: 'mailbox',
        ),
      );
      expect(cubit.openIdsFor('p1'), ['mailbox']);
      expect(persisted, isEmpty);
      addTearDown(cubit.close);
    });

    test('removeWorkspace does not clear the open set', () {
      final cubit = WorkspaceToolsCubit()..ensureOpenAndSelect('p1', 'git');
      cubit.removeWorkspace('p1');
      expect(cubit.openIdsFor('p1'), ['git']);
      addTearDown(cubit.close);
    });
  });
}
```

- [ ] **Step 2: Run the cubit tests and verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workspace_tools_cubit_test.dart`

Expected: FAIL (`openSet` / `seedTeamDefaults` / persist constructor missing, or `pruneToAvailable` still drops `members`).

- [ ] **Step 3: Rewrite `WorkspaceToolsCubit`**

Replace `client/lib/cubits/workspace_tools_cubit.dart` with:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/right_tool_open_set.dart';

class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({this.openSet = const RightToolOpenSet()});

  final RightToolOpenSet openSet;

  WorkspaceToolsState copyWith({RightToolOpenSet? openSet}) =>
      WorkspaceToolsState(openSet: openSet ?? this.openSet);

  @override
  List<Object?> get props => [openSet];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit({
    RightToolOpenSet initial = const RightToolOpenSet(),
    void Function(RightToolOpenSet set)? persist,
  }) : _persist = persist,
       super(WorkspaceToolsState(openSet: initial));

  final void Function(RightToolOpenSet set)? _persist;

  List<String> openIdsFor(String scopeId) =>
      List<String>.unmodifiable(state.openSet.openIds);

  String? selectedIdFor(String scopeId) => state.openSet.selectedId;

  void hydrate(RightToolOpenSet set) {
    if (set == state.openSet) return;
    emit(state.copyWith(openSet: set));
  }

  void ensureOpenAndSelect(String scopeId, String toolId) {
    _apply(state.openSet.opened(toolId));
  }

  void seedTeamDefaults(String scopeId, Iterable<String> catalogIds) {
    _apply(state.openSet.seededForTeam(catalogIds));
  }

  void selectTool(String scopeId, String toolId) {
    _apply(state.openSet.selected(toolId));
  }

  void closeTool(
    String scopeId,
    String toolId, {
    Iterable<String> catalog = const [],
  }) {
    final effectiveCatalog = catalog.isEmpty ? state.openSet.openIds : catalog;
    _apply(state.openSet.closed(toolId, catalog: effectiveCatalog));
  }

  void pruneToAvailable(String scopeId, Iterable<String> availableIds) {
    // Catalog membership is a display filter. Remembered ids stay.
  }

  void removeWorkspace(String scopeId) {
    // Global remembered set survives workspace-tab close.
  }

  void _apply(RightToolOpenSet next) {
    if (next == state.openSet) return;
    emit(state.copyWith(openSet: next));
    _persist?.call(next);
  }
}
```

Leave unused `scopeId` / `availableIds` parameters in place (call-site compatibility). If analyzer flags unused params, prefix with `_` **only if you also update every call site**; otherwise keep the names and ignore via using them in a comment is not allowed — keep the names as documented so `TabbedPanel` still compiles. Prefer keeping the names; `flutter analyze` in this repo uses `--no-fatal-infos --no-fatal-warnings`, but unused params may still be lints. Reference them in the existing dartdoc:

```dart
  /// [scopeId] is ignored; the open set is global.
  List<String> openIdsFor(String scopeId) =>
```

Unused parameter lints: add `// ignore: unused_element_parameter` is wrong. Use the parameter in an assert in debug? Simplest: `scopeId;` is invalid. Dart allows `_` prefix if all callers use named? They use positional.

Use `// ignore_for_file: unused_element` is too broad.

Pattern: `void pruneToAvailable(String scopeId, Iterable<String> availableIds) { assert(scopeId.isNotEmpty || scopeId.isEmpty); }` is silly.

Keep signatures and write:

```dart
  void pruneToAvailable(String scopeId, Iterable<String> availableIds) {
    final _ = (scopeId, availableIds);
  }
```

That is enough to silence unused-local if the vars are "used". Actually unused parameter warning is for the parameters themselves. In Dart, unused named/positional params in public API are typically fine if the analyzer isn't `unused_element`. Public API parameters are not unused_element. Unused local yes. **Public method parameters that are unused do trigger `unused_element` in some linters** (`avoid_unused_constructor_parameters` etc.). Check: `unnecessary_underscore` — I'll use the dartdoc mention and if analyze fails, assign to `_`.

- [ ] **Step 4: Run the cubit tests and verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workspace_tools_cubit_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/workspace_tools_cubit.dart client/test/cubits/workspace_tools_cubit_test.dart
git commit -m "$(cat <<'EOF'
Store right-tools tabs in one hydrated global set.

EOF
)"
```

---

### Task 4: Wire seed, prune, hydrate

**Files:**
- Modify: `client/lib/widgets/right_tools/right_tool_ids.dart`
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart`
- Modify: `client/lib/widgets/right_tools/tabbed_panel.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/widgets/right_tools_tabbed_panel_test.dart`

**Interfaces:**
- Consumes: `WorkspaceToolsCubit.seedTeamDefaults`, `WorkspaceToolsCubit.hydrate`, `LayoutCubit.setRightToolOpenSet`, `RightToolOpenSet.from` preferences fields via `RightToolOpenSet.sanitize` / `RightToolOpenSet(...)`.
- Produces: Team catalogs (native or mixed, not personal) call `seedTeamDefaults`. App start hydrates from layout prefs via `RightToolOpenSet.sanitize`. Closing a tab passes `_catalogIds` into `closeTool`.

- [ ] **Step 1: Add the failing tabbed-panel regression**

In `client/test/widgets/right_tools_tabbed_panel_test.dart`, add:

```dart
  testWidgets('catalog shrink keeps remembered ids for the next catalog', (
    tester,
  ) async {
    final toolsCubit = WorkspaceToolsCubit()
      ..ensureOpenAndSelect('ws-1', 'members')
      ..ensureOpenAndSelect('ws-1', 'fileTree');
    addTearDown(toolsCubit.close);

    Widget panel(List<ToolView> views) => _wrap(
      TabbedPanel(scopeId: 'ws-1', views: views),
      toolsCubit: toolsCubit,
    );

    const membersAndTree = [
      ToolView(
        id: 'members',
        icon: Icons.groups_outlined,
        label: 'Members',
        child: Text('members-body'),
      ),
      ToolView(
        id: 'fileTree',
        icon: Icons.folder_outlined,
        label: 'Files',
        child: Text('tree-body'),
      ),
    ];
    const treeOnly = [
      ToolView(
        id: 'fileTree',
        icon: Icons.folder_outlined,
        label: 'Files',
        child: Text('tree-body'),
      ),
    ];

    await tester.pumpWidget(panel(membersAndTree));
    expect(find.text('members-body'), findsOneWidget);

    await tester.pumpWidget(panel(treeOnly));
    await tester.pump();
    expect(find.text('members-body'), findsNothing);
    expect(toolsCubit.openIdsFor('ws-1'), ['members', 'fileTree']);

    await tester.pumpWidget(panel(membersAndTree));
    await tester.pump();
    expect(find.text('members-body'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the new widget test and verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/right_tools_tabbed_panel_test.dart --plain-name "catalog shrink"`

Expected: FAIL if Task 3 is not yet wired into `TabbedPanel.pruneToAvailable` (members dropped after rebuild). If Task 3 already made prune a no-op, this test may already PASS — continue with the remaining wiring in this task.

- [ ] **Step 3: Update `RightToolIds`**

In `client/lib/widgets/right_tools/right_tool_ids.dart`, delete `mixedTeamDefaults` and add:

```dart
  static const teamSeedIds = ['members', 'mailbox'];
```

Grep the repo for `mixedTeamDefaults` and replace remaining references. Production remaining site is `right_tools_tool_views.dart` (next step).

- [ ] **Step 4: Replace mixed first-visit seeding**

In `client/lib/widgets/right_tools/right_tools_tool_views.dart`:

1. Remove `_mixedDefaultsSeeded`, the `didUpdateWidget` reset, and `_seedMixedTeamDefaultsIfNeeded`.
2. After `_cachedViews` is assigned / reused, call a new method:

```dart
  void _seedTeamToolsIfNeeded(BuildContext context, List<ToolView> views) {
    if (widget.isPersonalContext || widget.team == null) return;
    final catalog = [for (final view in views) view.id];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WorkspaceToolsCubit>().seedTeamDefaults(
        widget.toolsScopeId,
        catalog,
      );
    });
  }
```

Call it from `_buildWithUnread` where `_seedMixedTeamDefaultsIfNeeded` used to run:

```dart
    _seedTeamToolsIfNeeded(context, _cachedViews!);
```

`seedTeamDefaults` is idempotent; extra post-frame calls are OK.

Do **not** gate on `TeamMode.mixed`. Native teams must seed members.

- [ ] **Step 5: Pass catalog on close in `TabbedPanel`**

In `client/lib/widgets/right_tools/tabbed_panel.dart`, change `_close` to:

```dart
  void _close(String id) {
    final scope = widget.scopeId;
    if (scope != null) {
      context.read<WorkspaceToolsCubit>().closeTool(
        scope,
        id,
        catalog: _catalogIds,
      );
    } else {
      setState(() {
        final index = _localOpenIds.indexOf(id);
        if (index < 0) return;
        _localOpenIds.removeAt(index);
        if (_localSelectedId == id) {
          if (_localOpenIds.isEmpty) {
            _localSelectedId = null;
          } else if (index > 0) {
            _localSelectedId = _localOpenIds[index - 1];
          } else {
            _localSelectedId = _localOpenIds.first;
          }
        }
      });
    }
  }
```

Leave `_schedulePrune` calling `pruneToAvailable` (now a no-op) so catalog changes still rebuild via `didUpdateWidget`; display already intersects with `byId`.

- [ ] **Step 6: Hydrate in `app_shell.dart`**

`WorkspaceToolsCubit` is constructed around line 1688, `layoutCubit.load()` around 2369. Wire:

Where cubit is created:

```dart
    final workspaceToolsCubit = WorkspaceToolsCubit(
      persist: layoutCubit.setRightToolOpenSet,
    );
```

`setRightToolOpenSet` returns `Future<void>`. The cubit persist typedef is `void Function(RightToolOpenSet set)`. Do **not** pass the Future-returning method tear-off if the typedef is void-returning and unawaited futures trigger lints.

Use:

```dart
    final workspaceToolsCubit = WorkspaceToolsCubit(
      persist: (set) {
        unawaited(layoutCubit.setRightToolOpenSet(set));
      },
    );
```

`dart:async` `unawaited` is already used in `app_shell.dart`.

Immediately after `await layoutCubit.load();` (beside `floatingWorkspacePersistence.hydrateFromLayout();`):

```dart
    workspaceToolsCubit.hydrate(
      RightToolOpenSet.sanitize(
        openIds: layoutCubit.state.preferences.rightToolOpenIds,
        selectedId: layoutCubit.state.preferences.rightToolSelectedId,
        dismissedIds: layoutCubit.state.preferences.rightToolDismissedIds,
      ),
    );
```

Add `import '../models/right_tool_open_set.dart';` to `app_shell.dart`.

- [ ] **Step 7: Run widget + cubit tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/widgets/right_tools_tabbed_panel_test.dart
cd client && dart run tool/run_tests.dart test/cubits/workspace_tools_cubit_test.dart
```

Expected: PASS, including `catalog shrink keeps remembered ids`.

- [ ] **Step 8: Commit**

```bash
git add client/lib/widgets/right_tools/right_tool_ids.dart \
  client/lib/widgets/right_tools/right_tools_tool_views.dart \
  client/lib/widgets/right_tools/tabbed_panel.dart \
  client/lib/app/app_shell.dart \
  client/test/widgets/right_tools_tabbed_panel_test.dart
git commit -m "$(cat <<'EOF'
Restore team members and mailbox from the remembered open set.

EOF
)"
```

---

### Task 5: Analyze and full test run

**Files:**
- None planned unless analyze/tests expose a missed `openDefaultsIfEmpty` / `mixedTeamDefaults` / `LayoutPreferences(` copy.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: Green analyze + full `run_tests.dart`.

- [ ] **Step 1: Grep for leftover API**

```bash
rg "openDefaultsIfEmpty|mixedTeamDefaults|openIdsByScope" client
```

Expected: no production hits. Tests should not reference the old names.

If `workspace_split_pane.dart` / `right_tools_tool_preferences.dart` construct a subset `LayoutPreferences(` for the panel, they do **not** need the new fields; defaults are empty and the panel does not own persistence.

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in touched files. Fix unused imports (`RightToolIds` if seed no longer uses `mixedTeamDefaults` but still uses `members` elsewhere — keep the import if still referenced).

- [ ] **Step 3: Full suite**

Run: `cd client && dart run tool/run_tests.dart`

Expected: PASS. If anything still asserts two scopes with different `openIdsFor` lists, change it so both scopes see the same global list.

- [ ] **Step 4: Commit only if Step 3 required extra fixes**

```bash
git add -u client
git commit -m "$(cat <<'EOF'
Fix leftover right-tools open-set callers after persistence.

EOF
)"
```

Skip this commit if there is nothing to add.

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| Persist `rightToolOpenIds` / `selected` / `dismissed` | 2 |
| Unknown-id strip on load | 1 + 2 |
| Display = intersection; do not delete unavailable ids | 1, 3, 4 |
| Open / close / select unified | 1, 3, 4 |
| Team seed members+mailbox; skip unavailable; skip dismissed | 1, 3, 4 |
| Empty open set still seeds | 1 |
| Native then mixed seeds mailbox | 1 |
| Do not seed board | 1 |
| Replace mixed first-visit seeding | 4 |
| Global set; ignore scope; hydrate after load | 3, 4 |
| `removeWorkspace` does not clear | 3 |
| No settings UI; do not auto-show pane | non-goal, no task |
| Tests listed in spec | 1–4 |
