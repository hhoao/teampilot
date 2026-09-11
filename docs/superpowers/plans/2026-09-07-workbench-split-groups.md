# Workbench Split Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VSCode-style split editor groups for the center workbench and the floating workspace panel, backed by a cubit-owned immutable split tree with per-group tab strips, a shared recursive renderer, and per-workspace layout persistence.

**Architecture:** `WorkspaceTabBar.center/floating` change from a single `TabStrip` to a `WorkbenchGroupLayout` (binary split tree of groups, each group holding its own `TabStrip`). A pure `SplitLayoutReducer` owns all tree mutations; `WorkbenchCubit` exposes group-aware APIs whose "active" reads are always the *focused group's* active tab so existing consumers keep their semantics. A shared `WorkbenchSplitLayoutView` renders the tree recursively for both center and floating surfaces.

**Tech Stack:** Flutter / `flutter_bloc` (cubit-only state), `equatable`, existing `TpKeepAliveLayer` / `TpDeferredForegroundMount` keep-alive, existing `WorkspaceTerminalHoldHandle` PTY bracketing, `CommandBus` / `CommandCatalog` for shortcuts, JSON file persistence via the workspace storage backend.

**Spec:** `docs/specs/2026-09-07-workbench-split-groups-design.md` — the plan argues from the spec; read both.

## Global Constraints

- Spec: split semantics are **move**, never copy (sessions own live terminals).
- Spec: `centerActiveId(workspaceId)` / `floatingActiveId(workspaceId)` return the **focused group's** active id.
- Spec: reducer clamps branch fraction to 0.05–0.95; per-side pixel minimums `minSplitGroupExtent = 240` (center), `180` (floating).
- Spec: tab id appears in exactly one group's `order` across a layout (global uniqueness invariant).
- Spec: no empty groups after any operation; `focusedGroupId` / `maximizedGroupId` always null or live.
- Spec: drag never commits mid-drag — live resize uses a local `ValueNotifier`, cubit commit fires once on drag end.
- Spec: narrow screens (`WorkspacePanePolicy` narrow, or floating panel below minimum split size) render only the focused group; tree and fractions survive.
- Conventions: tests through `cd client && dart run tool/run_tests.dart <paths>` — **never raw `flutter test`**. l10n keys only in `app_en.arb` + `app_zh.arb`. No `print` (use `AppLogger` for diagnostics). No `Process.run` / raw paths in UI. State is cubit-only. Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`.
- Files starting from the spec's "Components & Files" table; test file paths mirror `client/test/` structure (existing workbench tests live in `client/test/cubits/workbench/`).

## Conventions used in this plan

- Test ids: `_ws` = workspace id string, `_s1/_s2/_s3` = `WorkbenchTabId.session('s1'…)` etc. — mirror the existing `client/test/cubits/workbench/workbench_cubit_test.dart` header style.
- Group ids: opaque strings produced by the reducer (`g0`, `g1`, …). Tests never construct group ids by hand except `'g0'` for the initial root group, which the layout factory must use deterministically.
- All reducer/cubit code in this plan is Dart meant to be pasted and adapted to analyzer satisfaction — matching surrounding code style, not copied blindly.

---

### Task 1: Split tree model + `SplitLayoutReducer` (pure state layer)

**Files:**
- Create: `client/lib/cubits/workbench/workbench_split_layout.dart`
- Test: `client/test/cubits/workbench/workbench_split_layout_test.dart`

**Interfaces:**
- Consumes: `TabStrip` / `TabStripReducer` from `client/lib/cubits/workbench/tab_strip.dart` (unchanged).
- Produces (later tasks rely on these exact names):
  - `sealed class SplitNode`; `class SplitLeaf extends SplitNode` with `final String groupId`; `class SplitBranch extends SplitNode` with `final Axis axis`, `final SplitNode first`, `final SplitNode second`, `final double firstFraction`.
  - `class WorkbenchGroupLayout extends Equatable` with fields `final SplitNode root`, `final Map<String, TabStrip> groups`, `final String focusedGroupId`, `final String? maximizedGroupId`; method `WorkbenchGroupLayout copyWith({SplitNode? root, Map<String, TabStrip>? groups, Object? focusedGroupId = _unset, Object? maximizedGroupId = _unset})`.
  - `WorkbenchGroupLayout singleGroupLayout([String? seedTabId])` — factory: one group `'g0'`, root `SplitLeaf('g0')`, empty strip or a strip whose `order`/`activeId` is the seed tab, focused `'g0'`.
  - `class SplitLayoutReducer` with pure methods:
    - `WorkbenchGroupLayout? split(WorkbenchGroupLayout layout, {required WorkbenchTabId tab, required Axis axis, required bool before})` — null when the tab is absent or is the only tab of its group.
    - `WorkbenchGroupLayout? moveTab(WorkbenchGroupLayout layout, {required WorkbenchTabId tab, required String targetGroupId})` — null when absent or target invalid.
    - `WorkbenchGroupLayout? remove(WorkbenchGroupLayout layout, WorkbenchTabId tabId)` — null when absent; delegates to `TabStripReducer.remove`, prunes empty groups.
    - `WorkbenchGroupLayout focusGroup(WorkbenchGroupLayout layout, String groupId)`
    - `WorkbenchGroupLayout toggleMaximize(WorkbenchGroupLayout layout, String groupId)`
    - `WorkbenchGroupLayout commitResize(WorkbenchGroupLayout layout, {required SplitBranch branch, required double fraction})`
    - `WorkbenchGroupLayout collapse(WorkbenchGroupLayout layout)` — reset: single group with all tabs in stable (depth-first, first-before-second) order.
    - `WorkbenchGroupLayout activate(WorkbenchGroupLayout layout, WorkbenchTabId tabId)`
    - `TabStrip? groupForTab(WorkbenchGroupLayout layout, WorkbenchTabId tabId)` — helper for callers.
  - `bool validateLayout(WorkbenchGroupLayout layout)` — the four invariants (used in `assert`s inside the reducer and in tests).
  - Serialization helpers for Task 9 (defined here, tested later): `Map<String, Object?> toSnapshot(WorkbenchGroupLayout layout)` and `WorkbenchGroupLayout? layoutFromSnapshot(Map<String, Object?> json, {required bool Function(WorkbenchTabId) tabResolves})`.

**Design notes for the implementer:**

- Branch identity for `commitResize`: structural identity is unstable (immutable copies), so compare by position. Simplest correct approach: `commitResize` walks the tree and replaces the *first branch node whose `(axis, first leaf list, second leaf list)`* matches the passed prototype, or — simpler and adequate — the reducer exposes `commitResizeByPath(WorkbenchGroupLayout layout, {required List<bool> path, required double fraction})` where `path` is the sequence of first(=false)/second(=true) choices from the root. **Use the path approach**; the renderer (Task 4) can compute the path trivially while walking. Name it `commitResizeByPath`; drop the `branch` variant from the interface.
- `split` with `before: true` puts the new group as `first` (split left/up); `before: false` puts it as `second` (right/down). The new sibling group is created at the *target leaf* (the dragged tab's owning group): that leaf becomes `SplitBranch(axis, first: originalLeafOrNewLeaf, second: …)` per `before`. New group id: `'g${int.parse(currentMaxGroupNumberSuffix) + 1}'` — derive from the current max numeric suffix, not `groups.length` (ids never recycle).
- `split` edge case (spec): when the moved tab is the group's *only* tab, the source group would become empty → return null (the cubit turns this into a plain `openGroup`-style move handled by Task 2's `splitTab` fallback). When the group has other tabs, the moved tab is removed from the source strip (via `TabStripReducer.remove`) and becomes the new group's single tab.
- `remove` pruning: after strip removal, if the group's `order` is empty, remove the leaf and roll the sibling up into the parent's position (recursive). When the root itself is a leaf that becomes empty, keep the layout with an empty strip only if it is the sole group — actually per invariant "no empty groups", a sole empty group *is* allowed as the degenerate root (it is equivalent to today's empty `TabStrip`): amend the invariant to "no empty group **except the single root group**". Implement `validateLayout` accordingly. Focus repair: when focus/maximize pointed at a pruned group, move focus to the surviving sibling's first leaf (leftmost) / clear maximize.
- `collapse`: gather all strips' tabs depth-first; the focused group's active tab (if any) becomes the single group's active; focused = `'g0'`; maximized = null.
- `layoutFromSnapshot` prunes unresolved tabs; if any group ends empty → prune it; if the root ends with no groups → return null (caller falls back to `singleGroupLayout()`). Validate with `validateLayout` before returning; return null on failure.
- Snapshot format (must match Task 9):
  ```json
  {
    "root": {"kind": "leaf", "groupId": "g0"} | {"kind": "branch", "axis": "horizontal", "first": <node>, "second": <node>, "firstFraction": 0.5},
    "groups": {"g0": <TabStripSnapshot>},
    "focusedGroupId": "g0",
    "maximizedGroupId": null
  }
  ```
  `TabStripSnapshot` = `{"order": [["session", "s1"], ["file", "/a"]], "activeId": ["session", "s1"], "previewIds": [...], "pinnedIds": [...]}` (kind string + id string pairs; landing fields are runtime-only, not persisted).

- [ ] **Step 1: Write the failing tests** — create `client/test/cubits/workbench/workbench_split_layout_test.dart` covering: factory degenerate form; `split` right/down creates sibling + moves tab + focuses new group; `split` null when tab absent; `split` null when tab is sole tab of group; `moveTab` across groups activates + focuses; `remove` prunes empty group and rolls sibling up; `remove` last tab of sole group keeps degenerate empty root; `focusGroup`; `toggleMaximize` set/clear; `commitResizeByPath` clamps to 0.05/0.95; `collapse` preserves all tabs and active of focused; `validateLayout` catches a hand-built inconsistent layout (orphan group, empty non-root group, duplicate tab across groups, stale focus); `toSnapshot`/`layoutFromSnapshot` round-trip; snapshot pruning of unresolved ids. Test skeleton:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');
final _f = WorkbenchTabId.file('/a.dart');

WorkbenchGroupLayout _seed(WorkbenchTabId a, [WorkbenchTabId? b]) {
  final layout = singleGroupLayout(a);
  if (b == null) return layout;
  const r = TabStripReducer();
  final strip = layout.groups['g0']!;
  return layout.copyWith(groups: {
    'g0': r.add(strip, b, preview: false),
  });
}

void main() {
  group('singleGroupLayout', () {
    test('degenerate form: one group, leaf root, focused', () {
      final l = singleGroupLayout();
      expect(l.root, isA<SplitLeaf>());
      expect((l.root as SplitLeaf).groupId, 'g0');
      expect(l.groups.keys, ['g0']);
      expect(l.focusedGroupId, 'g0');
      expect(validateLayout(l), isTrue);
    });
  });

  group('split', () {
    test('moves tab into new right sibling and focuses it', () {
      const r = SplitLayoutReducer();
      final l0 = _seed(_s1, _s2);
      final l1 = r.split(l0, tab: _s2, axis: Axis.horizontal, before: false);
      expect(l1, isNotNull);
      final root = l1!.root;
      expect(root, isA<SplitBranch>());
      final b = root as SplitBranch;
      expect(b.axis, Axis.horizontal);
      expect(l1.groups['g0']!.order, [_s1]);
      final newId = (b.second as SplitLeaf).groupId;
      expect(l1.groups[newId]!.order, [_s2]);
      expect(l1.groups[newId]!.activeId, _s2);
      expect(l1.focusedGroupId, newId);
      expect(validateLayout(l1), isTrue);
    });

    test('null when tab is the only tab of its group', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      expect(r.split(l0, tab: _s1, axis: Axis.vertical, before: true), isNull);
    });

    test('null when tab absent', () {
      const r = SplitLayoutReducer();
      expect(r.split(singleGroupLayout(_s1), tab: _s3, axis: Axis.horizontal, before: false), isNull);
    });
  });

  group('remove / prune', () {
    test('prunes emptied group and rolls sibling up', () {
      const r = SplitLayoutReducer();
      final l0 = _seed(_s1, _s2);
      final l1 = r.split(l0, tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = r.remove(l1, _s2);
      expect(l2, isNotNull);
      expect(l2!.root, isA<SplitLeaf>());
      expect((l2.root as SplitLeaf).groupId, 'g0');
      expect(validateLayout(l2), isTrue);
    });

    test('last tab of sole group keeps degenerate empty root', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      final l1 = r.remove(l0, _s1);
      expect(l1, isNotNull);
      expect(l1!.groups['g0']!.order, isEmpty);
      expect(validateLayout(l1), isTrue);
    });
  });

  group('validateLayout invariants', () {
    test('rejects duplicate tab across groups', () {
      // hand-build via public API: split then inject duplicate through copyWith
      const r = SplitLayoutReducer();
      final l0 = _seed(_s1, _s2);
      final l1 = r.split(l0, tab: _s2, axis: Axis.horizontal, before: false)!;
      final newId = ((l1.root as SplitBranch).second as SplitLeaf).groupId;
      final dup = l1.copyWith(groups: {
        ...l1.groups,
        newId: l1.groups[newId]!.copyWith(order: [_s1, _s2]),
      });
      expect(validateLayout(dup), isFalse);
    });
  });

  group('snapshot', () {
    test('round-trips a two-group layout', () {
      const r = SplitLayoutReducer();
      final l0 = _seed(_s1, _s2);
      final l1 = r.split(l0, tab: _s2, axis: Axis.horizontal, before: false)!;
      final snap = toSnapshot(l1);
      final back = layoutFromSnapshot(snap, tabResolves: (_) => true)!;
      expect(back.root, isA<SplitBranch>());
      expect(validateLayout(back), isTrue);
      final allTabs = [...back.groups.values].expand((s) => s.order).toSet();
      expect(allTabs, {_s1, _s2});
    });

    test('prunes unresolved tabs and empty groups', () {
      const r = SplitLayoutReducer();
      final l0 = _seed(_s1, _s2);
      final l1 = r.split(l0, tab: _s2, axis: Axis.horizontal, before: false)!;
      final back = layoutFromSnapshot(
        toSnapshot(l1),
        tabResolves: (t) => t != _s2,
      )!;
      expect([...back.groups.values].expand((s) => s.order), [_s1]);
      expect(back.root, isA<SplitLeaf>());
    });
  });
}
```

Extend with the remaining cases listed above (`moveTab`, `focusGroup`, `toggleMaximize`, `commitResizeByPath` clamp, `collapse`, focus repair on prune) in the same style — each asserted via `validateLayout` where applicable.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart`
Expected: FAIL — `workbench_split_layout.dart` does not exist (import error).

- [ ] **Step 3: Implement `workbench_split_layout.dart`**

Implement the model + reducer per the interface block. Key implementation shapes (adapt, don't paste blindly):

```dart
// lib/cubits/workbench/workbench_split_layout.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Axis;

import 'tab_strip.dart';
import 'workbench_tab.dart';

sealed class SplitNode extends Equatable {
  const SplitNode();
}

class SplitLeaf extends SplitNode {
  const SplitLeaf(this.groupId);
  final String groupId;
  @override
  List<Object?> get props => [groupId];
}

class SplitBranch extends SplitNode {
  const SplitBranch({
    required this.axis,
    required this.first,
    required this.second,
    this.firstFraction = 0.5,
  });
  final Axis axis;
  final SplitNode first;
  final SplitNode second;
  final double firstFraction;
  @override
  List<Object?> get props => [axis, first, second, firstFraction];

  SplitBranch copyWith({Axis? axis, SplitNode? first, SplitNode? second, double? firstFraction}) =>
      SplitBranch(
        axis: axis ?? this.axis,
        first: first ?? this.first,
        second: second ?? this.second,
        firstFraction: firstFraction ?? this.firstFraction,
      );
}

class WorkbenchGroupLayout extends Equatable {
  static const Object _unset = Object();
  const WorkbenchGroupLayout({
    required this.root,
    required this.groups,
    required this.focusedGroupId,
    this.maximizedGroupId,
  });

  final SplitNode root;
  final Map<String, TabStrip> groups;
  final String focusedGroupId;
  final String? maximizedGroupId;

  WorkbenchGroupLayout copyWith({
    SplitNode? root,
    Map<String, TabStrip>? groups,
    Object? focusedGroupId = _unset,
    Object? maximizedGroupId = _unset,
  }) => WorkbenchGroupLayout(
    root: root ?? this.root,
    groups: groups ?? this.groups,
    focusedGroupId:
        focusedGroupId == _unset ? this.focusedGroupId : focusedGroupId as String,
    maximizedGroupId: maximizedGroupId == _unset
        ? this.maximizedGroupId
        : maximizedGroupId as String?,
  );

  /// Depth-first leaf order, first-before-second.
  List<String> get leafGroupIds => _leaves(root);
  static List<String> _leaves(SplitNode node) => switch (node) {
    SplitLeaf(:final groupId) => [groupId],
    SplitBranch(:final first, :final second) => [..._leaves(first), ..._leaves(second)],
  };

  @override
  List<Object?> get props => [root, groups, focusedGroupId, maximizedGroupId];
}

WorkbenchGroupLayout singleGroupLayout([WorkbenchTabId? seedTabId]) {
  final strip = seedTabId == null
      ? const TabStrip()
      : const TabStripReducer().add(const TabStrip(), seedTabId, preview: false);
  return WorkbenchGroupLayout(
    root: const SplitLeaf('g0'),
    groups: {'g0': strip},
    focusedGroupId: 'g0',
  );
}
```

The reducer: every mutating method starts with `assert(validateLayout(input) || true)` — no, do **not** assert in release paths; instead run `debugAssertValid(next)` as a `bool _debugCheck(WorkbenchGroupLayout l) => !kDebugMode || validateLayout(l);` guard used in each method's return (mirror how `TabStripReducer` stays side-effect free). Tree rewrite helper:

```dart
typedef _NodeRewrite = SplitNode? Function(SplitNode node);

SplitNode? _rewrite(SplitNode node, _NodeRewrite fn) {
  final direct = fn(node);
  if (direct != null) return direct;
  if (node is SplitBranch) {
    final f = _rewrite(node.first, fn);
    final s = _rewrite(node.second, fn);
    if (f == null && s == null) return null;
    return node.copyWith(first: f ?? node.first, second: s ?? node.second);
  }
  return null;
}
```

- `split`: locate owning group; if `strip.order.length < 2` or tab absent → null. Remove tab from source strip, create `newId`, put `TabStrip(order: [tab], activeId: tab)` under `newId`, replace the source leaf with `SplitBranch(axis, first: before ? newLeaf : originalLeaf, second: before ? originalLeaf : newLeaf, firstFraction: 0.5)`, focus `newId`.
- `moveTab`: remove from source (via `TabStripReducer.remove`), add to target (via `TabStripReducer.add`, `preview: false`), prune empty source leaf (roll-up), activate + focus target. Null when target absent from `groups` or tab absent anywhere.
- `remove`: `_rewrite` with a leaf-level function that removes the tab from that leaf's strip; when the strip becomes empty, delete the group and return `null` from the rewrite so the branch roll-up deletes it — handle root-is-empty-leaf specially (keep degenerate). Fix `focusedGroupId`/`maximizedGroupId` afterwards.
- `commitResizeByPath`: walk `path` (list of `true` = go second); clamp `fraction` to `(0.05, 0.95)`; rebuild the branch at that path.
- `collapse`: collect strips depth-first into one order (strip-level merge preserving each group's internal order), active = focused group's active if it survived else last tab, focused `'g0'`, maximized null, groups `{'g0': merged}`. Re-seed group id `'g0'` even if it was previously deleted.
- Snapshot helpers: hand-written JSON encode/decode per the format block (no codegen).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` (no new issues).

```bash
git add client/lib/cubits/workbench/workbench_split_layout.dart client/test/cubits/workbench/workbench_split_layout_test.dart
git commit -m "feat(workbench): split tree model and SplitLayoutReducer"
```

---

### Task 2: `WorkbenchCubit` group-aware API + bar state re-shape

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_tab_bar.dart` (full rewrite — small file)
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`
- Modify: `client/test/cubits/workbench/workbench_cubit_test.dart` (update expectations; add new groups)
- Modify: `client/test/cubits/workbench/tab_strip_test.dart` only if it touches `WorkspaceTabBar` (it shouldn't — strip-only).

**Interfaces:**
- Consumes: Task 1 (`WorkbenchGroupLayout`, `singleGroupLayout`, `SplitLayoutReducer`, `SplitNode`/`SplitLeaf`/`SplitBranch`).
- Produces (UI tasks 3–6 and service code rely on these exact signatures):
  - `WorkspaceTabBar`: fields `final WorkbenchGroupLayout center; final WorkbenchGroupLayout floating;` — `const WorkspaceTabBar({this.center = ..., this.floating = ...})` with `singleGroupLayout()` as the default. NOTE: `const` default requires a const-capable default; since `singleGroupLayout()` is not const, make the default `null`-able via a static `const _emptyLayout` — simplest: make the fields non-nullable but the constructor non-const with `WorkspaceTabBar()` constructing `singleGroupLayout()`; `WorkbenchState.bar` already falls back to `const WorkspaceTabBar()` — change that fallback to a cached `_defaultBar`. Provide `bar(String) => byWorkspace[id] ?? _defaultBar;`.
  - Cubit read APIs (behavior-compatible with today for the single-group degenerate):
    - `WorkbenchTabId? centerActiveId(String workspaceId)` → focused group's active id (existing signature kept).
    - `List<WorkbenchTabId> centerOrder(String workspaceId)` → focused group's order.
    - `TabStrip centerFocusedStrip(String workspaceId)` (new).
    - `String centerFocusedGroupId(String workspaceId)` (new).
    - `WorkbenchGroupLayout centerLayout(String workspaceId)` / `floatingLayout(String workspaceId)` (new).
    - Same trio for floating: `floatingActiveId`, `floatingOrder`, `floatingFocusedStrip`.
    - `bool centerLandingActive(String workspaceId)` → focused group's `landingActive` (new convenience; consumers migrate to it in Tasks 5/6).
    - `String? centerLandingInitialText(String workspaceId)` / `int centerLandingInitialTextRevision(...)` / `String? centerLandingReferenceSessionId(...)` — focused-group reads (new).
    - `bool canExitLanding(String workspaceId)` — focused group.
  - Cubit mutation APIs:
    - Existing keep-exact signatures (now group-aware inside): `openSession`, `openFile`, `openDiff`, `openFloating`, `openShell`, `openRun`, `close`, `activate`, `pin`, `unpin`, `promote`, `reorder`, `reorderFloating`, `closeOthers`, `closeRight`, `closeAll`, `enterLanding`, `exitLanding`, `onSessionDeleted`, `clearWorkspace`.
    - New: `void splitTab(String workspaceId, WorkbenchTabId tab, {required Axis axis, required bool before})` — reducer `split`; on null return (sole-tab case) emits nothing and the caller (command layer, Task 6) may surface "cannot split sole tab" — reducer-null is silent.
    - New: `void moveTab(String workspaceId, WorkbenchTabId tab, String targetGroupId)`.
    - New: `void focusGroup(String workspaceId, String groupId, {bool floating = false})`.
    - New: `void commitSplitResize(String workspaceId, {required List<bool> path, required double fraction, bool floating = false})`.
    - New: `void toggleMaximizeGroup(String workspaceId, String groupId, {bool floating = false})`.
    - New: `void collapseSplitLayout(String workspaceId, {bool floating = false})`.
    - New: `void resetLayoutToSnapshot(String workspaceId, WorkbenchGroupLayout? center, WorkbenchGroupLayout? floating)` — Task 9 restore entry.
  - Domain port contract unchanged: `close(ws, id)` still calls `_port.onTabRemoved(workspaceId, id)` after bar removal.

**Migration rules the implementer must apply inside the cubit:**

- `_owningStrip(bar, id)` becomes `_owningGroup(WorkbenchTabBar bar, WorkbenchTabId id)` returning `(WorkbenchGroupLayout, bool isCenter, String groupId)`: search every group of `center`, then every group of `floating`, then kind-route to the focused group of the appropriate layout.
- All strip-level mutations (`activate`, `pin`, …) apply `TabStripReducer` to the owning group's strip and write it back into the layout's `groups` map (new map instance — immutability), then emit.
- `open*` adds target the **focused group** of the target layout (spec: new tabs open into the focused group) and focuses that group.
- `enterLanding` acts on the focused group of center. `exitLanding` re-activates the focused group's `landingReturnTabId`.
- `closeAll` keeps pinned tabs of the **focused group only** (spec) — note this changes today's center-wide semantics deliberately (spec: group-scoped).
- `closeOthers`/`closeRight` operate on the **owning group's** strip (not focused) — they are invoked from a tab's context menu, which belongs to a specific group.
- Empty-layout degenerate: when a layout's sole group strip is empty, it stays the degenerate root (Task 1 invariant); `centerActiveId` returns null → landing.

- [ ] **Step 1: Update + extend the failing tests** — in `workbench_cubit_test.dart`:
  - Existing assertions like `bar.center.order` become `cubit.centerOrder(_ws)` / `cubit.centerActiveId(_ws)` (focused-group reads). Keep the same behavioral expectations — single-group equivalence is the point.
  - New group:

```dart
group('split groups', () {
  test('splitTab moves tab into new group and focuses it', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
    expect(cubit.centerOrder(_ws), [_s2]);       // focused = new group
    expect(cubit.centerActiveId(_ws), _s2);
    final layout = cubit.centerLayout(_ws);
    expect(layout.root, isA<SplitBranch>());
    expect(cubit.state.bar(_ws).center.groups.values
        .expand((s) => s.order).toSet(), {_s1, _s2});
  });

  test('openSession lands in the focused group', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
      ..openSession(_ws, 's3');
    expect(cubit.centerOrder(_ws), [_s2, _s3]);
  });

  test('activate focuses the owning group', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
    final layout = cubit.centerLayout(_ws);
    // focus back to g0 by activating its tab
    cubit.activate(_ws, _s1);
    expect(cubit.centerFocusedGroupId(_ws), (layout.root as SplitBranch).first is SplitLeaf
        ? 'g0' : 'g0');
    expect(cubit.centerActiveId(_ws), _s1);
  });

  test('close prunes the emptied group', () async {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
    await cubit.close(_ws, _s2);
    expect(cubit.centerLayout(_ws).root, isA<SplitLeaf>());
    expect(cubit.centerOrder(_ws), [_s1]);
  });

  test('enterLanding is group-scoped', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
      ..enterLanding(_ws);
    expect(cubit.centerLandingActive(_ws), isTrue);
    // the other group still has its tab active
    final other = cubit.centerLayout(_ws).groups['g0']!;
    expect(other.activeId, _s1);
  });

  test('closeAll keeps pinned tabs of the focused group only', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
      ..pin(_ws, _s1);
    cubit.focusGroup(_ws, 'g0');
    cubit.closeAll(_ws);
    expect(cubit.centerLayout(_ws).groups['g0']!.order, [_s1]);
    expect(cubit.centerLayout(_ws).groups['g0']!.pinnedIds, contains(_s1));
    // the focused (split) group's tab closed
    expect(cubit.centerOrder(_ws), isEmpty);
  });
});
```

Note: `pin` currently routes by presence — after `splitTab`, `_s2`'s group is focused; `pin(_ws, _s1)` must find g0 by presence. Keep that behavior.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/`
Expected: FAIL — compile errors (`center` is no longer a `TabStrip`; new methods missing).

- [ ] **Step 3: Implement**

Rewrite `workbench_tab_bar.dart`:

```dart
// lib/cubits/workbench/workbench_tab_bar.dart
import 'package:equatable/equatable.dart';

import 'tab_strip.dart';
import 'workbench_split_layout.dart';

/// Per-workspace tab state: the center layout (session/file/diff groups) and
/// the floating layout (shell/run/file-preview groups). Both are
/// [WorkbenchGroupLayout]s — each leaf group holds one [TabStrip].
class WorkspaceTabBar extends Equatable {
  WorkspaceTabBar({
    WorkbenchGroupLayout? center,
    WorkbenchGroupLayout? floating,
  }) : center = center ?? singleGroupLayout(),
       floating = floating ?? singleGroupLayout();

  final WorkbenchGroupLayout center;
  final WorkbenchGroupLayout floating;

  WorkspaceTabBar copyWith({WorkbenchGroupLayout? center, WorkbenchGroupLayout? floating}) =>
      WorkspaceTabBar(center: center ?? this.center, floating: floating ?? this.floating);

  @override
  List<Object?> get props => [center, floating];
}
```

In `workbench_cubit.dart`, add `late final WorkspaceTabBar _defaultBar = WorkspaceTabBar();` and change `bar(String workspaceId) => byWorkspace[workspaceId] ?? _defaultBar;`. Then implement every API per the migration rules. Structure the layout write-back with one private helper:

```dart
WorkbenchState _withCenter(String workspaceId, WorkbenchGroupLayout layout) =>
    state.withBar(workspaceId, state.bar(workspaceId).copyWith(center: layout));

WorkbenchState _withFloating(String workspaceId, WorkbenchGroupLayout layout) =>
    state.withBar(workspaceId, state.bar(workspaceId).copyWith(floating: layout));
```

Apply strip mutations with:

```dart
void _mutateOwningGroup(String workspaceId, WorkbenchTabId id,
    TabStrip Function(TabStrip strip) mutate) {
  final bar = state.bar(workspaceId);
  final (layout, isCenter, groupId) = _owningGroup(bar, id);
  final next = mutate(layout.groups[groupId]!);
  if (identical(next, layout.groups[groupId])) return;
  final nextLayout = layout.copyWith(groups: {...layout.groups, groupId: next});
  emit(isCenter
      ? _withCenter(workspaceId, nextLayout)
      : _withFloating(workspaceId, nextLayout));
}
```

`_owningGroup` (presence wins, then kind routing to focused group):

```dart
(WorkbenchGroupLayout, bool, String) _owningGroup(WorkspaceTabBar bar, WorkbenchTabId id) {
  for (final e in bar.center.groups.entries) {
    if (e.value.contains(id)) return (bar.center, true, e.key);
  }
  for (final e in bar.floating.groups.entries) {
    if (e.value.contains(id)) return (bar.floating, false, e.key);
  }
  return isCenterStripWorkbenchTab(id.kind)
      ? (bar.center, true, bar.center.focusedGroupId)
      : (bar.floating, false, bar.floating.focusedGroupId);
}
```

`remove` after strip removal must run the layout-level prune — route through `SplitLayoutReducer.remove(layout, id)` for the whole layout instead of strip-only mutation on close paths.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/workbench/`
Expected: PASS.

Also run the full suite to surface every compile break in consumers (they will fail to compile — that is the next tasks' work, but record the list):

Run: `cd client && dart run tool/run_tests.dart`
Expected: COMPILE ERRORS in consumers of `bar.center` / `bar.floating` (`chat_page_shell.dart`, `workspace_split_pane.dart`, `workspace_sidebar.dart`, `home_workspace_title_bar.dart`, `workspace_shell_tabs.dart`, `workspace_new_chat_active.dart`, `workbench_strip_navigator.dart`, `chat_page_structural_signal.dart`, `floating_workspace_panel.dart`, `workbench_editor_opener.dart`, `workbench_shell_run_sync.dart`, `close_floating_tab.dart`, and their tests). Fix the trivially mechanical ones now — wherever a consumer reads `bar(ws).center.order/activeId/previewIds/pinnedIds/landing*`, replace with the cubit focused-group read APIs from this task's Produces list; wherever it reads `bar(ws).floating.*`, replace with `floatingActiveId/floatingOrder/floatingFocusedStrip`. Mechanical consumer fixes are part of this task (they must compile for the suite to run); behavioral UI restructuring is NOT — that is Tasks 4–7.

- [ ] **Step 5: Analyze + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` (clean).

```bash
git add -A client/lib/cubits/workbench client/lib client/test
git commit -m "feat(workbench): group-aware WorkbenchCubit over split layout

Bar state becomes WorkbenchGroupLayout per surface; active reads are
focused-group scoped; splitTab/moveTab/focusGroup/commitSplitResize/
toggleMaximizeGroup/collapseSplitLayout added; consumer strip reads
migrated to focused-group APIs."
```

---

### Task 3: `WorkbenchSplitLayoutView` — shared recursive renderer

**Files:**
- Create: `client/lib/widgets/workbench/workbench_split_layout_view.dart`
- Test: `client/test/widgets/workbench/workbench_split_layout_view_test.dart`

**Interfaces:**
- Consumes: Task 1 (`WorkbenchGroupLayout`, `SplitNode`, `SplitBranch`, `SplitLeaf`); `WorkspaceTerminalHoldHandle` from `client/lib/widgets/workspace_terminal_panel.dart`.
- Produces (Tasks 5, 6 rely on these exact names):
  - `typedef SplitGroupBuilder = Widget Function(BuildContext context, String groupId, TabStrip strip);`
  - `class WorkbenchSplitLayoutView extends StatefulWidget` with:
    ```dart
    const WorkbenchSplitLayoutView({
      required this.layout,
      required this.groupBuilder,
      this.holdHandle,
      this.splitEnabled = true,
      this.onResizeCommit,          // void Function(List<bool> path, double fraction)
      this.onGroupFocused,          // void Function(String groupId)?
      this.onDividerDoubleTap,      // VoidCallback? — fires with focused/maximized target resolved by caller
      this.minGroupExtent = 240,
      this.focusedGroupIdOverride,  // String? — narrow mode focuses this group
      super.key,
    });
    ```
  - Rendering contract:
    - `maximizedGroupId != null && splitEnabled` → render only that leaf full-size (still via `groupBuilder`).
    - `!splitEnabled` → render only the focused group (or `focusedGroupIdOverride`) full-size; no dividers.
    - Branch → recursive `first`/`second` with a divider between. Live fraction during drag comes from a local `ValueNotifier<double>`; `onResizeCommit(path, fraction)` fires once on drag end; during the drag `holdHandle?.beginPtyHold()` on start and `holdHandle?.endPtyHold(flush: true)` on end.
    - Divider: `MouseRegion` (resize cursor per axis) + `GestureDetector` with `onPanStart/Update/End`; 6px visual, 12px hit area (match `resizable_split_view.dart` conventions: `dividerThickness = 1` visual, `dividerHitBuffer` hit buffer — follow the existing constants in that file for visual thickness; hit area is the wider one).
    - `onDoubleTap` on the divider → `onDividerDoubleTap` (caller dispatches `toggleMaximizeGroup`).
    - Each leaf wraps its child in a `Listener`-free tap focus: wrap `groupBuilder` output with a `GestureDetector(behavior: translucent, onTap: () => onGroupFocused?.call(groupId))` — translucent so inner interactive content still receives taps.
    - Focus highlight is NOT in this view (group chrome belongs to `groupBuilder` callers); expose only `onGroupFocused` and let the caller highlight. Additionally export `class SplitGroupFocusFrame extends StatelessWidget` — a thin `DecoratedBox` border overlay (2px, `colorScheme.primary` when focused) that Tasks 5/6 wrap their group chrome in, so the highlight style is defined once:
      ```dart
      class SplitGroupFocusFrame extends StatelessWidget {
        const SplitGroupFocusFrame({required this.focused, required this.child, super.key});
        final bool focused; final Widget child;
        // Stack: child + IgnorePointer(Positioned.fill(DecoratedBox(border: ...)))
      }
      ```
  - Min-extent math: during drag, clamp the live fraction so each side keeps `minGroupExtent` of the branch's current extent (computed in `LayoutBuilder` — this widget may use LayoutBuilder; the panes-package LayoutBuilder-in-layout caveat does not apply because this view sits above pane content, not inside a panes `paneBuilder`). Store branch extent from the last layout pass in the State.

- [ ] **Step 1: Write failing widget tests** — pump with a two-group layout (`_seed` + `split` right, as in Task 1 tests) and:
  - `groupBuilder` output appears twice (one per leaf).
  - `splitEnabled: false` renders only the focused group's builder output.
  - `maximizedGroupId` set renders only that group.
  - Drag the divider (axis horizontal): `onResizeCommit` receives path `[]` (root branch) and a fraction clamped to respect `minGroupExtent` under a 500px-wide pump; `beginPtyHold`/`endPtyHold` called around the gesture (use a fake `WorkspaceTerminalHoldHandle` — it is a concrete class with bindable state; instead, drive a real `WorkspaceTerminalPanel`-free test by subclassing? No — `WorkspaceTerminalHoldHandle` methods are non-virtual and bind to panel state. **Test the bracket via `onResizeCommit` order + a listener-flagged `holdHandle` is not possible — instead expose the bracket callbacks as injectable constructor params `onPtyHoldBegin`/`onPtyHoldEnd` (defaults forward to `holdHandle`) so tests can record calls.** Add those two optional params to the Produces interface.)
  - Tap inside a group fires `onGroupFocused(groupId)`.
  - Double-tap divider fires `onDividerDoubleTap`.

```dart
// test/widgets/workbench/workbench_split_layout_view_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/widgets/workbench/workbench_split_layout_view.dart';

final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late WorkbenchGroupLayout layout;
  setUp(() {
    const r = SplitLayoutReducer();
    final base = singleGroupLayout(_s1);
    final withTwo = base.copyWith(groups: {
      'g0': const TabStripReducer().add(base.groups['g0']!, _s2, preview: false),
    });
    layout = r.split(withTwo, tab: _s2, axis: Axis.horizontal, before: false)!;
  });

  testWidgets('renders one group builder output per leaf', (tester) async {
    await tester.pumpWidget(_host(WorkbenchSplitLayoutView(
      layout: layout,
      groupBuilder: (context, id, strip) => Text('group-$id'),
    )));
    expect(find.text('group-g0'), findsOneWidget);
    expect(
      find.textWidget('group-${((layout.root as SplitBranch).second as SplitLeaf).groupId}'),
      findsOneWidget,
    );
  });

  testWidgets('splitEnabled false renders only focused group', (tester) async {
    final focused = ((layout.root as SplitBranch).second as SplitLeaf).groupId;
    await tester.pumpWidget(_host(WorkbenchSplitLayoutView(
      layout: layout,
      splitEnabled: false,
      groupBuilder: (context, id, strip) => Text('group-$id'),
    )));
    expect(find.text('group-$focused'), findsOneWidget);
    expect(find.text('group-g0'), findsNothing);
  });

  testWidgets('divider drag commits once on end and brackets pty hold', (tester) async {
    final holds = <String>[];
    double? committed;
    await tester.pumpWidget(_host(WorkbenchSplitLayoutView(
      layout: layout,
      minGroupExtent: 100,
      onPtyHoldBegin: () => holds.add('begin'),
      onPtyHoldEnd: () => holds.add('end'),
      onResizeCommit: (path, f) => committed = f,
      groupBuilder: (context, id, strip) => Text('group-$id'),
    )));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(GestureDetector).first);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(holds, ['begin', 'end']);
    expect(committed, isNotNull);
    expect(committed! > 0.0 && committed! < 1.0, isTrue);
  });

  testWidgets('tap in group reports focus', (tester) async {
    String? focusedId;
    await tester.pumpWidget(_host(WorkbenchSplitLayoutView(
      layout: layout,
      onGroupFocused: (id) => focusedId = id,
      groupBuilder: (context, id, strip) => SizedBox.expand(child: Text('group-$id')),
    )));
    await tester.tap(find.text('group-g0'));
    expect(focusedId, 'g0');
  });
}
```

(Adapt: `find.textWidget` does not exist — build the expected second group id into a local variable before pumping and use `find.text`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_split_layout_view_test.dart`
Expected: FAIL — file/class missing.

- [ ] **Step 3: Implement the view** per the rendering contract. Structure:

```dart
class _BranchView extends StatelessWidget {
  // LayoutBuilder captures extent for min-clamp math; Row/Column splits
  // children by the *live* fraction (ValueListenableBuilder over the local
  // drag notifier, seeded from branch.firstFraction).
}
class _Divider extends StatelessWidget { /* MouseRegion + GestureDetector */ }
class _LeafView extends StatelessWidget { /* translucent tap + groupBuilder */ }
```

The StatefulWidget root owns the drag state machine (start → update local notifier → end → commit callback). Path computation: the recursion threads `List<bool> path` down; the divider at depth *d* appends nothing (it is the divider of the branch at that node) — `onResizeCommit` receives the path of the branch being resized, which is the path of the `_BranchView` node itself.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_split_layout_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
git add client/lib/widgets/workbench/workbench_split_layout_view.dart client/test/widgets/workbench/workbench_split_layout_view_test.dart
git commit -m "feat(workbench): shared recursive split layout renderer"
```

---

### Task 4: Tab drag-and-drop split (drop indicator + dispatch)

**Files:**
- Create: `client/lib/widgets/workbench/workbench_tab_drag.dart`
- Test: `client/test/widgets/workbench/workbench_tab_drag_test.dart`

**Interfaces:**
- Consumes: Task 3 (`WorkbenchSplitLayoutView.onGroupFocused`), Task 2 cubit APIs (`splitTab`, `moveTab`).
- Produces:
  - `enum SplitDropZone { right, left, up, down, center }`
  - `class WorkbenchTabDragScope extends InheritedWidget` — ancestor scope started/stopped by each tab bar's drag start; exposes:
    ```dart
    static WorkbenchTabDragScope? maybeOf(BuildContext context);
    final WorkbenchTabId draggedTab;
    final String sourceGroupId;
    final void Function(String targetGroupId, SplitDropZone zone) onDrop;
    bool get isActive;
    ```
    Tab bars (Tasks 5/6) call a drag starter: `void beginWorkbenchTabDrag(BuildContext context, {required WorkbenchTabId tab, required String sourceGroupId, required void Function(String targetGroupId, SplitDropZone zone) onDrop})` — implemented as a method on the scope's controller widget mounted above the split view (see below).
  - `class WorkbenchTabDropRegions extends StatelessWidget` — wraps one group's body slot; when a drag is active, paints the four-edge + center indicator (a `CustomPainter` or `Stack` of `Positioned` `DecoratedBox`es — `IgnorePointer`, purely visual) and hit-tests the pointer position on release (implemented as an overlay `Listener` that records the last pointer position inside this group, then on drag end computes the zone: relative x/y in the local rect → 20% edge bands → zone; center otherwise). Fires `onDrop(groupId, zone)`.
  - `void dispatchSplitDrop(WorkbenchCubit workbench, String workspaceId, {required WorkbenchTabId tab, required String sourceGroupId, required String targetGroupId, required SplitDropZone zone, bool floating = false})` — zone → action mapping:
    - `center` → `workbench.moveTab(ws, tab, targetGroupId)`
    - `right` → `splitTab(ws, tab, axis: horizontal, before: false)` (split *the target group's* active tab? No — spec: the dragged tab moves into a new sibling of the **target group**; but `splitTab` splits the dragged tab from its owning group. **Design decision locked here:** edge-drop semantics = "split the *target group*" — move the dragged tab into a new group placed adjacent to the target group. Implementation: `splitTab` handles source-group splits; for target-group splits the cubit needs `splitInto(String ws, WorkbenchTabId tab, String targetGroupId, {required Axis axis, required bool before})` — moves `tab` out of its source group and inserts a new group as sibling of `targetGroupId`. **Add `splitInto` to Task 2's Produces list and implement it there.** `dispatchSplitDrop` uses `splitInto` for edge zones.)
  - Rejection: dropping a tab onto its own group's edge → no-op (reducer returns same layout; cubit emits nothing).
  - Draggable source: a generic `class WorkbenchTabDraggable extends StatefulWidget` wrapping a tab widget: long-press (mobile) / immediate drag (desktop mouse) starts the scope via a controller. The controller: `class WorkbenchTabDragController extends ChangeNotifier` mounted by the host page (Tasks 5/6); scope reads from it.

- [ ] **Step 1: Write failing tests** — pure zone math + dispatch tests first (no pumping complexity beyond a minimal MaterialApp):

```dart
// zone math: export from workbench_tab_drag.dart
SplitDropZone splitDropZoneForOffset(Offset local, Size size) // 20% edge bands
```
Test: center of a 100x100 → `center`; (95, 50) → `right`; (5, 50) → `left`; (50, 5) → `up`; (50, 95) → `down`; corners: (95, 5) → `right` (x wins within horizontal band? define: corners belong to the axis whose band is entered first — lock: horizontal edges win at corners when the pointer is within the left/right 20% band regardless of y; otherwise vertical). Then dispatch tests with a real `WorkbenchCubit`: two groups; drop `center` on g0 moves the tab; drop `right` on g0 creates a sibling branch whose `first` is g0's subtree; drop on own group edge → state unchanged (`emit` count stable — use `cubit.stream` capture or compare `state` equality).

- [ ] **Step 2: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_tab_drag_test.dart`
Expected: FAIL — missing file.

- [ ] **Step 3: Implement** `workbench_tab_drag.dart` (zone math + scope + drop regions + dispatch + controller). Drop indicator visuals: 2px accent border inset on the hovered edge; center zone = 12.5% opacity primary fill overlay.

- [ ] **Step 4: Widget-test the overlay paint** — pump a group body wrapped in `WorkbenchTabDropRegions` with an active drag scope, `find.byType(CustomPaint)` (or the DecoratedBox marker key `Key('split_drop_indicator_right')` etc.) appears when the pointer is inside; disappears when drag scope deactivates.

- [ ] **Step 5: Run tests + analyze + commit**

```bash
git add client/lib/widgets/workbench/workbench_tab_drag.dart client/test/widgets/workbench/workbench_tab_drag_test.dart
git commit -m "feat(workbench): tab drag split drop zones and dispatch"
```

---

### Task 5: Center workbench per-group shell (`ChatPageShell` / `WorkbenchBody`)

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (restructure — the `WorkspaceShell`+`WorkbenchBody` block becomes a group builder)
- Modify: `client/lib/pages/workbench/workbench_body.dart` (accept `groupId` + strip; per-group keep-alive)
- Create: `client/lib/pages/workbench/workbench_group_host.dart` (the per-group `WorkspaceShell` + focus frame + drop regions + landing slot)
- Test: `client/test/pages/workbench/workbench_group_host_test.dart`, update `client/test/pages/chat/` suites that pump `ChatPageShell`

**Interfaces:**
- Consumes: Tasks 2–4 APIs; `WorkspaceShell` (existing, unchanged — one per group); `KeepAliveSessionStack` (unchanged, per group); `WorkspaceChatPane` (landing, per group: pass the group's `landingInitialText`/revision/reference; `onBack` exits the *group's* landing).
- Produces:
  - `class WorkbenchGroupHost extends StatelessWidget`:
    ```dart
    const WorkbenchGroupHost({
      required this.workspace, required this.workspaceId, required this.tabScopeId,
      required this.cwd, required this.additionalPaths,
      required this.groupId, required this.strip, required this.focused,
      required this.routeActive, this.holdHandle, super.key,
    });
    ```
    Renders: `SplitGroupFocusFrame(focused:)` → `WorkspaceShell(tabs: projected, activeTabIndex: …, child: body)` where body = strip's active tab body (session keep-alive stack / file / diff) or `WorkspaceChatPane` when `strip.landingActive`.
  - `WorkbenchBody` gains `final String groupId; final TabStrip strip;` and selects `activeId` from `strip` instead of `context.select<WorkbenchCubit, …>(centerActiveId)`. `_SessionKeepAliveHosts` receives the group's strip-derived `activeSessionId` (already passed via `workbenchSlice`).
  - `ChatPageShell._ChatWorkspaceShell.build` becomes:
    ```dart
    WorkbenchSplitLayoutView(
      layout: bar.center,
      holdHandle: holdHandle,
      splitEnabled: !isNarrow,   // from MediaQuery/pane policy — use the same width threshold as WorkspacePanePolicy.narrowBreakpointWidth
      onGroupFocused: (id) => workbench.focusGroup(workspaceId, id),
      onResizeCommit: (path, f) => workbench.commitSplitResize(workspaceId, path: path, fraction: f),
      onDividerDoubleTap: () => workbench.toggleMaximizeGroup(workspaceId, layout.focusedGroupId),
      groupBuilder: (context, id, strip) => WorkbenchGroupHost(...),
    )
    ```
    The existing single `WorkspaceShell` header actions (`_chatActions`) render once *above* the split view only in the single-group case; in multi-group they move into each group host's action row (duplicate per group is acceptable and matches VSCode).
  - Tab interactions inside a group host route to the same `WorkbenchShellActions` (already group-agnostic — they operate by tab id through the cubit, which now routes by owning group).
  - Group tab bar gains context-menu / long-press "Split Right"/"Split Down" entries via the existing tab menu composer chain (`services/workbench/tab_menu/`): add a `WorkbenchTabMenuSource` contribution — create `client/lib/services/workbench/tab_menu/split_tab_menu_source.dart` producing two items calling `workbench.splitTab(ws, tab, axis: …, before: false/true per direction)`; wire it into `defaultWorkbenchTabMenuSources` composition. (Check `default_workbench_tab_menu_sources.dart` for the list shape; follow it.)
  - Scroll anchor restore (spec): `ChatCubit` gains `final Map<String, double> sessionScrollAnchors = {};` (plain mutable map on the cubit, not state — document it); `ChatWorkbench`'s transcript list (locate the scroll controller owner in `chat_workbench.dart`) writes `sessionScrollAnchors[sessionId] = controller.offset` on dispose and restores via `jumpTo` in `postFrameCallback` on mount when an anchor exists. Keep it minimal: one controller per host, write-on-dispose/read-on-init.

- [ ] **Step 1: Write failing tests** for `WorkbenchGroupHost`: pump with a two-group `WorkbenchGroupLayout` and verify both groups' tab bars render, tapping a group focuses it (cubit state), landing shows in the group whose strip has `activeId == null`. Follow the pump harness of an existing chat page test (`client/test/pages/chat/` — read one first for the provider scaffolding: `setUpTestAppStorage` etc. per AGENTS.md when `AppStorage` is touched; if the group-host test only needs WorkbenchCubit + fakes, prefer plain `BlocProvider.value`).
- [ ] **Step 2: Verify failure** — Run: `cd client && dart run tool/run_tests.dart test/pages/workbench/`
- [ ] **Step 3: Implement** the three files per the interfaces. Move the `projectWorkbenchTabs` call into the group host (it takes `tabOrder`/`previewTabIds` — now the group's). The `WorkspaceShell` breadcrumb/title/subtitle stay per-group (they already resolve from focused context — pass the group's active session context; simplest: keep resolving via `WorkspaceActiveContext` but constrain by the group's active session id — pass `overrideActiveSessionId: strip.activeId?.sessionId` is NOT an existing param; instead resolve inside the host with `chat.tabStore.openTabBySessionId(strip.activeId?.sessionId)`).
- [ ] **Step 4: Run chat-page tests** — Run: `cd client && dart run tool/run_tests.dart test/pages/chat/ test/pages/workbench/` — fix regressions (existing tests expecting a single `WorkspaceShell` may need updating to find the group host instead; behavioral expectations must stay).
- [ ] **Step 5: Analyze + commit**

```bash
git add -A client/lib/pages/chat client/lib/pages/workbench client/lib/services/workbench client/lib/cubits/chat_cubit.dart client/test
git commit -m "feat(workbench): per-group center shell with split view and landing"
```

---

### Task 6: Floating panel split + commands/shortcuts + l10n

**Files:**
- Modify: `client/lib/pages/floating_workspace/floating_workspace_panel.dart` (`_FloatingTabBodyStack` → `WorkbenchSplitLayoutView` + floating group host)
- Create: `client/lib/pages/floating_workspace/floating_group_host.dart`
- Modify: `client/lib/services/commands/command_ids.dart`, `command_catalog.dart`
- Create: `client/lib/services/commands/split_command_registrar.dart`
- Modify: `client/lib/app/app_shell.dart` (register split commands)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Test: `client/test/pages/floating_workspace/` (new `floating_split_test.dart`), `client/test/services/commands/` if a catalog test exists

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces:
  - `FloatingGroupHost`: per-group body slot = slim header (that group's `FloatingWorkspaceTabBar` instance — the widget takes `tabs`/`activeTabId`/callbacks; re-instantiate per group with the group's strip projected through `resolveFloatingTabForId`) + the group's tab bodies (`_FloatingTabBodyStack` logic per group: `TpKeepAliveLayer` + `TpDeferredForegroundMount` per tab, keyed by tab id).
  - Panel title bar keeps rendering the **focused group's** strip (existing `FloatingWorkspaceTabBar` in `_TitleBar` — data source changes from `bar.floating` to `floatingFocusedStrip`); when more than one group exists, group hosts carry their own slim tab strips and the title bar strip is hidden (spec).
  - Narrow/tiny: panel width/height below `180 * 2 + divider` → `splitEnabled: false`.
  - Commands:
    ```dart
    // command_ids.dart
    static const String workbenchSplitRight = 'workbench.split.splitRight';
    static const String workbenchSplitDown = 'workbench.split.splitDown';
    static const String workbenchSplitReset = 'workbench.split.reset';
    static const String workbenchFocusNextGroup = 'workbench.split.focusNextGroup';
    static const String workbenchMoveTabToNextGroup = 'workbench.split.moveTabToNextGroup';
    ```
    Catalog entries (category `tabs`, `when: hasWorkspace`, `terminalPassthrough: true`): `workbenchSplitRight` → `KeyChord(key: '\\', mods: [KeyChordMod.mod])`; `workbenchSplitDown` → chord sequence `Ctrl/Cmd+K` then `Ctrl/Cmd+\` — check `KeyChord` for chord-sequence support (existing `sessionNewTab` style single chords; if sequences are unsupported, use `Ctrl/Cmd+Alt+\` for down and note the deviation); `workbenchSplitReset` → `KeyChord(key: 't', mods: [KeyChordMod.mod, KeyChordMod.ctrl])`; `workbenchFocusNextGroup` → `KeyChord(key: 'arrowRight', mods: [KeyChordMod.mod, KeyChordMod.alt])` is taken by workspaceNextTab — use `KeyChord(key: 'f', mods: [KeyChordMod.mod, KeyChordMod.alt])`.
  - `registerSplitCommands(CommandBus bus, ChatCubit chat, WorkbenchCubit workbench)`: splitRight/Down act on `centerActiveId`'s tab in the active workspace (no-op when null); reset → `collapseSplitLayout` on both layouts; focusNextGroup → cycles `focusedGroupId` through `layout.leafGroupIds`; moveTabToNextGroup → moves the focused group's active tab to the next leaf group.
  - l10n keys: `shortcutsWorkbenchSplitRight`, `shortcutsWorkbenchSplitDown`, `shortcutsWorkbenchSplitReset`, `shortcutsWorkbenchFocusNextGroup`, `shortcutsWorkbenchMoveTabToNextGroup`, `tabMenuSplitRight`, `tabMenuSplitDown` (en + zh).

- [ ] **Step 1: Failing tests** — floating: pump `FloatingWorkspacePanel` harness (mirror an existing floating panel test for scaffolding), open two tabs, invoke `workbench.splitTab` on the floating layout (`floating: true` path — the cubit's split APIs need the `floating` flag: **add `bool floating = false` to `splitTab`/`moveTab`/`focusGroup`/`commitSplitResize`/`toggleMaximizeGroup`/`collapseSplitLayout` in Task 2**), verify two group hosts render and the focused one shows the title-bar strip. Commands: unit-test `registerSplitCommands` with a real `CommandBus` + cubits (no widget pump).
- [ ] **Step 2: Verify failure** — Run: `cd client && dart run tool/run_tests.dart test/pages/floating_workspace/`
- [ ] **Step 3: Implement** all pieces.
- [ ] **Step 4: Run floating + command tests, then the full suite** — Run: `cd client && dart run tool/run_tests.dart`
- [ ] **Step 5: Analyze + commit**

```bash
git add -A client/lib client/test
git commit -m "feat(floating,commands): floating panel split groups and split shortcuts"
```

---

### Task 7: Narrow-screen degradation integration

**Files:**
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (already gets `splitEnabled` in Task 5 — this task wires the real `WorkspacePanePolicy` breakpoint and mobile hiding of split menu items)
- Modify: `client/lib/pages/floating_workspace/floating_workspace_panel.dart` (panel-size-driven `splitEnabled`)
- Test: `client/test/pages/chat/` narrow-width pump

**Interfaces:**
- Consumes: `WorkspacePanePolicy.narrowBreakpointWidth` (existing constant in `client/lib/services/workspace/workspace_pane_policy.dart` — verify the exact name before use), Task 3 `splitEnabled`, Task 5 menu source.
- Produces: no new APIs — integration only.

- [ ] **Step 1: Failing test** — pump `ChatPageShell` at width below the narrow breakpoint with a two-group layout: only the focused group renders; tree unchanged (`workbench.centerLayout(ws).root` still `SplitBranch`). Floating: panel rect 400x300 → single group render.
- [ ] **Step 2: Verify failure** — Run: `cd client && dart run tool/run_tests.dart test/pages/chat/`
- [ ] **Step 3: Implement** — `splitEnabled: MediaQuery.widthOf(context) >= WorkspacePanePolicy.narrowBreakpointWidth`; `SplitTabMenuSource` returns no items when narrow (pass a flag through the menu context; check `workbench_tab_menu_context.dart` for the context shape).
- [ ] **Step 4: Run + analyze + commit**

```bash
git add -A client/lib client/test
git commit -m "feat(workbench): narrow-screen split degradation"
```

---

### Task 8: Session scroll anchors (cross-group move restore)

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (anchor map)
- Modify: `client/lib/pages/chat_workbench.dart` (scroll controller write/read)
- Test: `client/test/pages/chat_workbench_scroll_anchor_test.dart`

**Interfaces:**
- Consumes: Task 5 (per-group hosts remount on group move).
- Produces: `Map<String, double> sessionScrollAnchors` on `ChatCubit` (sessionId → offset).

- [ ] **Step 1: Failing test** — pump a transcript host with a scrollable; set `chat.sessionScrollAnchors['s1'] = 200`; remount host; expect restored offset 200.
- [ ] **Step 2: Verify failure** — Run: `cd client && dart run tool/run_tests.dart test/pages/chat_workbench_scroll_anchor_test.dart`
- [ ] **Step 3: Implement** — in the transcript scroll controller owner: on init, `postFrameCallback` → `jumpTo(anchor)` if the anchor exists and the scroll position allows; on dispose, write `sessionScrollAnchors[sessionId] = controller.offset`.
- [ ] **Step 4: Run + analyze + commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/lib/pages/chat_workbench.dart client/test/pages/chat_workbench_scroll_anchor_test.dart
git commit -m "feat(chat): session scroll anchor restore across group moves"
```

---

### Task 9: Layout snapshot persistence

**Files:**
- Create: `client/lib/repositories/workbench_layout_snapshot_repository.dart`
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart` (restore entry already added in Task 2: `resetLayoutToSnapshot`)
- Modify: `client/lib/app/app_shell.dart` (instantiate repository; wire save-on-change + restore-on-workspace-open)
- Modify: `client/lib/cubits/floating_workspace/floating_workspace_cubit.dart` — NOT modified; floating layout persists through the same workbench bar snapshot.
- Test: `client/test/repositories/workbench_layout_snapshot_repository_test.dart`, `client/test/cubits/workbench/snapshot_restore_test.dart`

**Interfaces:**
- Consumes: Task 1 `toSnapshot`/`layoutFromSnapshot`; `AppStorage`/`WorkspaceLayout` path conventions (check `client/lib/services/storage/workspace_layout.dart` or the storage-layout doc `docs/workspace-storage-layout.md` for the exact per-workspace dir accessor — path: `<teampilotRoot>/workspace/workspaces/{id}/workbench-layout.json`; use `AppStorage.fs` + `AppStorage.paths` resolved via the workspace's runtime context, mirroring how `automations/automations.json` is written — read `AutomationCubit`'s persistence for the pattern and copy it).
- Produces:
  ```dart
  class WorkbenchLayoutSnapshotRepository {
    WorkbenchLayoutSnapshotRepository({required this.workspaceId});
    final String workspaceId;
    Future<void> save(WorkbenchGroupLayout center, WorkbenchGroupLayout floating);
    Future<void> restore(WorkbenchCubit workbench); // prunes unresolved, falls back
    Future<void> delete();
  }
  ```
  Save format = Task 1's snapshot JSON `{"center": <layout>, "floating": <layout>, "version": 1}`.
  `tabResolves` for restore: sessions resolve via `ChatCubit.tabStore`/`state.sessions`; file/diff/shell/run via presence — simplest robust rule: resolve session ids against the chat store, everything else resolves true (domain sync strips stale ids on its own, per `WorkbenchShellRunSync` precedent).
  Restore is invoked where workspace tabs rehydrate (find where `HomeWorkspaceBodyStack`/`SessionRepository` restore sessions per workspace — hook the restore after session rehydration so `tabResolves` is accurate; if no single hook point exists, hook `app_shell.dart`'s workspace-restore flow).
  Save trigger: a debounced (500ms) `WorkbenchCubit.stream` subscription in `app_shell.dart` (skip the first emission; skip while a restore is in flight) — mirror `LayoutCubit` persistence debounce style.

- [ ] **Step 1: Failing tests** — repository: round-trip through a temp dir; corrupt JSON → restore leaves the bar at single-group; unresolved session id pruned. Use the existing fake-filesystem harness (constructor-injected `Filesystem` — check how `automation_cubit_test.dart` or `launch_profile_repository` tests inject storage; follow that).
- [ ] **Step 2: Verify failure** — Run: `cd client && dart run tool/run_tests.dart test/repositories/workbench_layout_snapshot_repository_test.dart`
- [ ] **Step 3: Implement** repository + wiring.
- [ ] **Step 4: Run full suite + analyze**
- [ ] **Step 5: Commit**

```bash
git add -A client/lib client/test
git commit -m "feat(workbench): per-workspace split layout snapshot persistence"
```

---

### Task 10: Full verification pass

**Files:** none new.

- [ ] **Step 1: Full test suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS (no skips beyond pre-existing integration tags).

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean.

- [ ] **Step 3: Manual smoke (documented, desktop)** — launch the app, open a workspace with two sessions, context-menu "Split Right" on a tab, drag a tab between groups, double-click divider, `Ctrl+\`, collapse via reset command, narrow the window, restart the app (snapshot restore). Record results in the commit message of this task's no-op commit or in the PR body.

- [ ] **Step 4: Commit (docs touch-up if needed)**

```bash
git add -A
git commit -m "test(workbench): split groups full verification pass"
```

---

## Self-Review Notes (resolved during writing)

- Spec coverage: state model (Task 1), cubit API + focus semantics (Task 2), shared renderer + PTY bracket + divider double-click (Task 3), drag entry points + drop indicator (Task 4), center per-group shell + landing + context menu entry (Task 5), floating split + commands/shortcuts (Task 6), narrow degradation (Task 7), scroll anchors (Task 8), persistence + corrupt fallback (Task 9), verification (Task 10). UX "close group via closing its last tab" = reducer prune (Tasks 1/2). "Reset layout" = Task 6 command + Task 2 `collapseSplitLayout`.
- Locked deviations from the draft interface: `commitResizeByPath` (path-based) replaces `commitResize(branch:)`; `splitInto` added for target-group edge drops; cubit split APIs take a `floating` flag; `WorkbenchSplitLayoutView` exposes `onPtyHoldBegin/End` for testability.
- Type consistency checked across tasks: `WorkbenchGroupLayout`, `singleGroupLayout`, `SplitLayoutReducer.split/moveTab/remove/focusGroup/toggleMaximize/commitResizeByPath/collapse/activate`, `splitInto`, focused-group read APIs, `SplitDropZone`, `dispatchSplitDrop`, `WorkbenchGroupHost`, `FloatingGroupHost`, command ids.
