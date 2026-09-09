// lib/cubits/workbench/workbench_split_layout.dart
//
// Split-group layout state for the workbench: a binary tree whose leaves are
// tab-strip groups, plus the pure reducer that evolves it. Mirrors
// [TabStripReducer] — every method is a total function of its inputs, never
// mutates in place, and performs no IO. Snapshot helpers persist the layout
// (Task 9); landing fields on [TabStrip] are runtime-only and not persisted.
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Axis;

import '../../models/diff_identity.dart';
import '../../models/git_compare.dart';
import 'tab_strip.dart';
import 'workbench_tab.dart';

/// One node of the split tree: a group leaf or a split branch.
@immutable
sealed class SplitNode extends Equatable {
  const SplitNode();
}

/// A leaf hosting exactly one tab-strip group.
@immutable
class SplitLeaf extends SplitNode {
  const SplitLeaf(this.groupId);

  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

/// An interior split dividing two subtrees along [axis].
@immutable
class SplitBranch extends SplitNode {
  const SplitBranch({
    required this.axis,
    required this.first,
    required this.second,
    this.firstFraction = 0.5,
  });

  final Axis axis;

  /// First child — left (horizontal) or top (vertical).
  final SplitNode first;

  /// Second child — right (horizontal) or bottom (vertical).
  final SplitNode second;

  /// Share of the available extent granted to [first]. Kept within
  /// [SplitLayoutReducer.minResizeFraction] …
  /// [SplitLayoutReducer.maxResizeFraction] once set through
  /// [SplitLayoutReducer.commitResizeByPath].
  final double firstFraction;

  SplitBranch copyWith({
    Axis? axis,
    SplitNode? first,
    SplitNode? second,
    double? firstFraction,
  }) => SplitBranch(
    axis: axis ?? this.axis,
    first: first ?? this.first,
    second: second ?? this.second,
    firstFraction: firstFraction ?? this.firstFraction,
  );

  @override
  List<Object?> get props => [axis, first, second, firstFraction];
}

/// The whole workbench layout: the split tree, one strip per group leaf, and
/// which group currently holds focus / is maximized.
@immutable
class WorkbenchGroupLayout extends Equatable {
  static const Object _unset = Object();

  const WorkbenchGroupLayout({
    required this.root,
    required this.groups,
    required this.focusedGroupId,
    this.maximizedGroupId,
  });

  final SplitNode root;

  /// One [TabStrip] per group leaf. Keys are exactly the tree's leaf group
  /// ids (enforced by [validateLayout]).
  final Map<String, TabStrip> groups;

  final String focusedGroupId;

  /// Group shown full-pane while set; null when no group is maximized.
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

  /// Depth-first leaf order, first-before-second (left/top before
  /// right/bottom at every level).
  List<String> get leafGroupIds => _leavesOf(root);

  static List<String> _leavesOf(SplitNode node) => switch (node) {
    SplitLeaf() => [node.groupId],
    SplitBranch() => [..._leavesOf(node.first), ..._leavesOf(node.second)],
  };

  @override
  List<Object?> get props => [root, groups, focusedGroupId, maximizedGroupId];
}

/// Factory: the degenerate single-group layout every workspace starts from.
/// [seedTabId], when given, becomes the sole group's only (active) tab.
WorkbenchGroupLayout singleGroupLayout([WorkbenchTabId? seedTabId]) {
  final strip = seedTabId == null
      ? const TabStrip()
      : const TabStripReducer().add(const TabStrip(), seedTabId, preview: false).$1;
  return WorkbenchGroupLayout(
    root: const SplitLeaf('g0'),
    groups: {'g0': strip},
    focusedGroupId: 'g0',
  );
}

/// Pure reducer over [WorkbenchGroupLayout]. Null returns mean "nothing to
/// do" (absent tab, invalid target, degenerate split) — callers keep their
/// previous state. Tree rewrites always build fresh nodes bottom-up.
class SplitLayoutReducer {
  const SplitLayoutReducer();

  /// Inclusive bounds applied to [SplitBranch.firstFraction] by
  /// [commitResizeByPath].
  static const double minResizeFraction = 0.05;
  static const double maxResizeFraction = 0.95;

  /// Splits [tab] out of its group into a new sibling group placed at the
  /// tab's owning group's leaf: that leaf becomes a [SplitBranch] along
  /// [axis], with the new group `first` ([before], left/up) or `second`
  /// (right/down). Null when [tab] is absent or is the only tab of its group
  /// (the source group would become empty). Focus moves to the new group.
  WorkbenchGroupLayout? split(
    WorkbenchGroupLayout layout, {
    required WorkbenchTabId tab,
    required Axis axis,
    required bool before,
  }) {
    final source = _groupContainingTab(layout, tab);
    if (source == null) return null;
    return _splitAt(
      layout,
      sourceGroupId: source,
      targetGroupId: source,
      tab: tab,
      axis: axis,
      before: before,
    );
  }

  /// Same split semantics as [split], but the new sibling group is placed
  /// adjacent to [targetGroupId] instead of the tab's owning group. Null when
  /// [tab] is absent, is the only tab of its source group, or
  /// [targetGroupId] is not a live leaf.
  WorkbenchGroupLayout? splitInto(
    WorkbenchGroupLayout layout, {
    required WorkbenchTabId tab,
    required String targetGroupId,
    required Axis axis,
    required bool before,
  }) {
    final source = _groupContainingTab(layout, tab);
    if (source == null) return null;
    if (!_treeContainsGroup(layout.root, targetGroupId)) return null;
    return _splitAt(
      layout,
      sourceGroupId: source,
      targetGroupId: targetGroupId,
      tab: tab,
      axis: axis,
      before: before,
    );
  }

  WorkbenchGroupLayout? _splitAt(
    WorkbenchGroupLayout layout, {
    required String sourceGroupId,
    required String targetGroupId,
    required WorkbenchTabId tab,
    required Axis axis,
    required bool before,
  }) {
    final sourceStrip = layout.groups[sourceGroupId];
    // Sole-tab groups cannot donate their tab (the group would empty).
    if (sourceStrip == null || sourceStrip.order.length < 2) return null;
    if (!_treeContainsGroup(layout.root, targetGroupId)) return null;
    final nextSource = const TabStripReducer().remove(sourceStrip, tab);
    if (nextSource == null) return null;
    final newGroupId = _nextGroupId(layout.groups.keys);
    final newLeaf = SplitLeaf(newGroupId);
    final groups = Map<String, TabStrip>.of(layout.groups)
      ..[sourceGroupId] = nextSource
      ..[newGroupId] = TabStrip(order: [tab], activeId: tab);
    final root = _replaceLeaf(
      layout.root,
      targetGroupId,
      (leaf) => SplitBranch(
        axis: axis,
        first: before ? newLeaf : leaf,
        second: before ? leaf : newLeaf,
      ),
    );
    final next = layout.copyWith(
      root: root,
      groups: groups,
      focusedGroupId: newGroupId,
    );
    assert(_debugCheck(next));
    return next;
  }

  /// Moves [tab] into [targetGroupId] (appended, activated) and focuses the
  /// target. Null when [tab] is absent or the target is not a live leaf.
  /// A source group emptied by the move is pruned and its sibling rolled up.
  /// Moving within the source group just activates and focuses.
  WorkbenchGroupLayout? moveTab(
    WorkbenchGroupLayout layout, {
    required WorkbenchTabId tab,
    required String targetGroupId,
  }) {
    final source = _groupContainingTab(layout, tab);
    if (source == null) return null;
    if (!_treeContainsGroup(layout.root, targetGroupId)) return null;
    const stripReducer = TabStripReducer();
    if (source == targetGroupId) {
      final next = layout.copyWith(
        groups: {
          ...layout.groups,
          source: stripReducer.activate(layout.groups[source]!, tab),
        },
        focusedGroupId: source,
      );
      assert(_debugCheck(next));
      return next;
    }
    final nextTarget = stripReducer.add(layout.groups[targetGroupId]!, tab, preview: false).$1;
    final nextSource = stripReducer.remove(layout.groups[source]!, tab)!;
    final groups = Map<String, TabStrip>.of(layout.groups)
      ..[targetGroupId] = nextTarget
      ..[source] = nextSource;
    var root = layout.root;
    if (nextSource.order.isEmpty) {
      groups.remove(source);
      root = _pruneEmptyGroups(root, groups)!;
    }
    final next = layout.copyWith(
      root: root,
      groups: groups,
      focusedGroupId: targetGroupId,
      maximizedGroupId: layout.maximizedGroupId == source ? null : layout.maximizedGroupId,
    );
    assert(_debugCheck(next));
    return next;
  }

  /// Removes [tabId] (delegates to [TabStripReducer.remove]). A group emptied
  /// by the removal is pruned and its sibling rolled up (recursively); the
  /// sole root group may go degenerate-empty instead. Focus follows the
  /// surviving sibling's leftmost leaf; maximize on a pruned group is
  /// cleared. Null when [tabId] is absent everywhere.
  WorkbenchGroupLayout? remove(WorkbenchGroupLayout layout, WorkbenchTabId tabId) {
    final groupId = _groupContainingTab(layout, tabId);
    if (groupId == null) return null;
    final nextStrip = const TabStripReducer().remove(layout.groups[groupId]!, tabId)!;
    final groups = Map<String, TabStrip>.of(layout.groups)..[groupId] = nextStrip;
    var root = layout.root;
    var focused = layout.focusedGroupId;
    var maximized = layout.maximizedGroupId;
    if (nextStrip.order.isEmpty && root is! SplitLeaf) {
      groups.remove(groupId);
      root = _pruneEmptyGroups(root, groups)!;
      if (focused == groupId) focused = _leftmostLeaf(root);
      if (maximized == groupId) maximized = null;
    }
    final next = layout.copyWith(
      root: root,
      groups: groups,
      focusedGroupId: focused,
      maximizedGroupId: maximized,
    );
    assert(_debugCheck(next));
    return next;
  }

  /// Focuses [groupId]; a no-op (same instance) when it is not a live leaf.
  WorkbenchGroupLayout focusGroup(WorkbenchGroupLayout layout, String groupId) {
    if (!_treeContainsGroup(layout.root, groupId)) return layout;
    final next = layout.copyWith(focusedGroupId: groupId);
    assert(_debugCheck(next));
    return next;
  }

  /// Maximizes [groupId], or restores it when already maximized; a no-op
  /// (same instance) when it is not a live leaf.
  WorkbenchGroupLayout toggleMaximize(WorkbenchGroupLayout layout, String groupId) {
    if (!_treeContainsGroup(layout.root, groupId)) return layout;
    final next = layout.copyWith(
      maximizedGroupId: layout.maximizedGroupId == groupId ? null : groupId,
    );
    assert(_debugCheck(next));
    return next;
  }

  /// Sets the [SplitBranch.firstFraction] of the branch at [path] — the
  /// sequence of second(=true)/first(=false) choices from the root. The
  /// fraction is clamped to [minResizeFraction] … [maxResizeFraction]. A
  /// path that ends on a leaf (or walks off the tree) returns the layout
  /// unchanged. Structural identity is unstable across immutable copies, so
  /// resizes address branches by position.
  WorkbenchGroupLayout commitResizeByPath(
    WorkbenchGroupLayout layout, {
    required List<bool> path,
    required double fraction,
  }) {
    final clamped = fraction
        .clamp(minResizeFraction, maxResizeFraction)
        .toDouble();
    final root = _replaceFractionAtPath(layout.root, path, clamped);
    if (root == null) return layout;
    final next = layout.copyWith(root: root);
    assert(_debugCheck(next));
    return next;
  }

  /// Resets to a single group `'g0'` holding every tab in stable depth-first
  /// (first-before-second) order, each group's internal order preserved. The
  /// active tab is the focused group's active when it survives, else the last
  /// tab. Focus is `'g0'`; maximize is cleared.
  WorkbenchGroupLayout collapse(WorkbenchGroupLayout layout) {
    final order = <WorkbenchTabId>[];
    final previews = <WorkbenchTabId>{};
    final pinneds = <WorkbenchTabId>{};
    WorkbenchTabId? focusedActive;
    for (final groupId in layout.leafGroupIds) {
      final strip = layout.groups[groupId];
      if (strip == null) continue;
      if (groupId == layout.focusedGroupId) focusedActive = strip.activeId;
      order.addAll(strip.order);
      previews.addAll(strip.previewIds);
      pinneds.addAll(strip.pinnedIds);
    }
    final active = focusedActive != null && order.contains(focusedActive)
        ? focusedActive
        : order.isEmpty
        ? null
        : order.last;
    final next = WorkbenchGroupLayout(
      root: const SplitLeaf('g0'),
      groups: {
        'g0': TabStrip(
          order: order,
          activeId: active,
          previewIds: previews,
          pinnedIds: pinneds,
        ),
      },
      focusedGroupId: 'g0',
    );
    assert(_debugCheck(next));
    return next;
  }

  /// Activates [tabId] within its owning group and focuses that group; a
  /// no-op (same instance) when the tab is absent.
  WorkbenchGroupLayout activate(WorkbenchGroupLayout layout, WorkbenchTabId tabId) {
    final groupId = _groupContainingTab(layout, tabId);
    if (groupId == null) return layout;
    final next = layout.copyWith(
      groups: {
        ...layout.groups,
        groupId: const TabStripReducer().activate(layout.groups[groupId]!, tabId),
      },
      focusedGroupId: groupId,
    );
    assert(_debugCheck(next));
    return next;
  }

  /// The strip of the group hosting [tabId], or null when absent.
  TabStrip? groupForTab(WorkbenchGroupLayout layout, WorkbenchTabId tabId) {
    final groupId = _groupContainingTab(layout, tabId);
    return groupId == null ? null : layout.groups[groupId];
  }
}

/// Layout invariants, checked by [assert]s inside the reducer and by tests:
///
/// 1. Tree leaves and [WorkbenchGroupLayout.groups] are in 1:1
///    correspondence (no dangling leaf, no orphan group, no duplicate leaf).
/// 2. No group is empty, except a degenerate single root group (the layout's
///    equivalent of an empty `TabStrip`).
/// 3. No tab appears in more than one group's order.
/// 4. `focusedGroupId` / `maximizedGroupId` (when set) point at live groups.
bool validateLayout(WorkbenchGroupLayout layout) {
  final leaves = layout.leafGroupIds;
  if (leaves.toSet().length != leaves.length) return false;
  if (leaves.length != layout.groups.length) return false;
  for (final groupId in leaves) {
    if (!layout.groups.containsKey(groupId)) return false;
  }
  final soleRootGroupId = layout.root is SplitLeaf
      ? (layout.root as SplitLeaf).groupId
      : null;
  for (final entry in layout.groups.entries) {
    if (entry.value.order.isEmpty && entry.key != soleRootGroupId) return false;
  }
  final seen = <WorkbenchTabId>{};
  for (final strip in layout.groups.values) {
    for (final tab in strip.order) {
      if (!seen.add(tab)) return false;
    }
  }
  if (!layout.groups.containsKey(layout.focusedGroupId)) return false;
  final maximized = layout.maximizedGroupId;
  if (maximized != null && !layout.groups.containsKey(maximized)) return false;
  return true;
}

bool _debugCheck(WorkbenchGroupLayout layout) => !kDebugMode || validateLayout(layout);

/// In-order neighbor leaf of [groupId]: the previous leaf when [before],
/// else the next one. Null when [groupId] is not a live leaf or has no
/// neighbor on that side. [axis] is accepted for future horizontal /
/// vertical differentiation; both axes currently use the in-order walk
/// (same order `workbenchFocusNextGroup` cycles in).
String? adjacentLeaf(
  WorkbenchGroupLayout layout,
  String groupId, {
  required Axis axis,
  required bool before,
}) {
  final leaves = layout.leafGroupIds;
  final index = leaves.indexOf(groupId);
  if (index < 0) return null;
  final target = before ? index - 1 : index + 1;
  return target >= 0 && target < leaves.length ? leaves[target] : null;
}

// ---------------------------------------------------------------------------
// Snapshot (Task 9 persistence format)
// ---------------------------------------------------------------------------

/// Encodes [layout] to the persisted snapshot format. `landing*` fields on
/// each strip are runtime-only and intentionally dropped. See
/// [layoutFromSnapshot] for the shape.
Map<String, Object?> toSnapshot(WorkbenchGroupLayout layout) => {
  'root': _nodeToSnapshot(layout.root),
  'groups': {
    for (final entry in layout.groups.entries) entry.key: _stripToSnapshot(entry.value),
  },
  'focusedGroupId': layout.focusedGroupId,
  'maximizedGroupId': layout.maximizedGroupId,
};

/// Decodes a snapshot produced by [toSnapshot]. Tabs that [tabResolves]
/// rejects are dropped; groups left empty are pruned (siblings rolled up).
/// Returns null when the snapshot is malformed or no group survives — the
/// caller falls back to [singleGroupLayout].
WorkbenchGroupLayout? layoutFromSnapshot(
  Map<String, Object?> json, {
  required bool Function(WorkbenchTabId) tabResolves,
}) {
  final rootJson = json['root'];
  if (rootJson is! Map) return null;
  final root = _nodeFromSnapshot(_typedMap(rootJson));
  if (root == null) return null;
  final groupsJson = json['groups'];
  if (groupsJson is! Map) return null;
  final groups = <String, TabStrip>{};
  for (final entry in groupsJson.entries) {
    if (entry.key is! String || entry.value is! Map) return null;
    groups[entry.key as String] = _stripFromSnapshot(
      _typedMap(entry.value as Map),
      tabResolves,
    );
  }
  final pruned = _pruneEmptyGroups(root, groups);
  if (pruned == null) return null;
  groups.removeWhere((groupId, _) => !_treeContainsGroup(pruned, groupId));
  if (groups.isEmpty) return null;
  final focusedJson = json['focusedGroupId'];
  final focused = focusedJson is String && groups.containsKey(focusedJson)
      ? focusedJson
      : _leftmostLeaf(pruned);
  final maximizedJson = json['maximizedGroupId'];
  final maximized = maximizedJson is String && groups.containsKey(maximizedJson)
      ? maximizedJson
      : null;
  final layout = WorkbenchGroupLayout(
    root: pruned,
    groups: groups,
    focusedGroupId: focused,
    maximizedGroupId: maximized,
  );
  return validateLayout(layout) ? layout : null;
}

Map<String, Object?> _typedMap(Map map) => Map<String, Object?>.from(map);

Map<String, Object?> _nodeToSnapshot(SplitNode node) => switch (node) {
  SplitLeaf() => {'kind': 'leaf', 'groupId': node.groupId},
  SplitBranch() => {
    'kind': 'branch',
    'axis': node.axis.name,
    'first': _nodeToSnapshot(node.first),
    'second': _nodeToSnapshot(node.second),
    'firstFraction': node.firstFraction,
  },
};

SplitNode? _nodeFromSnapshot(Map<String, Object?> json) {
  switch (json['kind']) {
    case 'leaf':
      final groupId = json['groupId'];
      return groupId is String ? SplitLeaf(groupId) : null;
    case 'branch':
      final axisName = json['axis'];
      final Axis axis;
      if (axisName == Axis.horizontal.name) {
        axis = Axis.horizontal;
      } else if (axisName == Axis.vertical.name) {
        axis = Axis.vertical;
      } else {
        return null;
      }
      final firstJson = json['first'];
      final secondJson = json['second'];
      if (firstJson is! Map || secondJson is! Map) return null;
      final first = _nodeFromSnapshot(_typedMap(firstJson));
      final second = _nodeFromSnapshot(_typedMap(secondJson));
      if (first == null || second == null) return null;
      final fraction = json['firstFraction'];
      return SplitBranch(
        axis: axis,
        first: first,
        second: second,
        firstFraction: fraction is num ? fraction.toDouble() : 0.5,
      );
  }
  return null;
}

Map<String, Object?> _stripToSnapshot(TabStrip strip) => {
  'order': [for (final tab in strip.order) _tabToParts(tab)],
  'activeId': strip.activeId == null ? null : _tabToParts(strip.activeId!),
  'previewIds': [for (final tab in strip.previewIds) _tabToParts(tab)],
  'pinnedIds': [for (final tab in strip.pinnedIds) _tabToParts(tab)],
};

TabStrip _stripFromSnapshot(
  Map<String, Object?> json,
  bool Function(WorkbenchTabId) tabResolves,
) {
  final order = _tabsFromParts(json['order'], tabResolves);
  var active = _tabsFromParts([json['activeId']], tabResolves).firstOrNull;
  if (active != null && !order.contains(active)) active = null;
  final previews = _tabsFromParts(json['previewIds'], tabResolves)
      .where(order.contains)
      .toSet();
  final pinneds = _tabsFromParts(json['pinnedIds'], tabResolves)
      .where(order.contains)
      .toSet();
  return TabStrip(
    order: order,
    activeId: active,
    previewIds: previews,
    pinnedIds: pinneds,
  );
}

/// `[["session", "s1"], …]` → tabs, dropping entries that are malformed,
/// unparseable, rejected by [tabResolves], or duplicated.
List<WorkbenchTabId> _tabsFromParts(
  Object? json,
  bool Function(WorkbenchTabId) tabResolves,
) {
  if (json is! List) return const [];
  final tabs = <WorkbenchTabId>[];
  for (final item in json) {
    if (item is! List || item.length != 2) continue;
    if (item[0] is! String || item[1] is! String) continue;
    final tab = _tabFromParts(item[0] as String, item[1] as String);
    if (tab == null || !tabResolves(tab) || tabs.contains(tab)) continue;
    tabs.add(tab);
  }
  return tabs;
}

List<Object> _tabToParts(WorkbenchTabId tab) => [tab.kind.name, tab.id];

WorkbenchTabId? _tabFromParts(String kind, String id) {
  switch (kind) {
    case 'session':
      return WorkbenchTabId.session(id);
    case 'file':
      return WorkbenchTabId.file(id);
    case 'diff':
      final identity = DiffIdentity.parseStorageKey(id);
      return identity == null ? null : WorkbenchTabId.diff(identity);
    case 'shell':
      return WorkbenchTabId.shell(id);
    case 'run':
      return WorkbenchTabId.run(id);
    case 'htmlPreview':
      return WorkbenchTabId.htmlPreview(id);
    case 'gitGraph':
      return WorkbenchTabId.gitGraph(id);
    case 'gitCompare':
      final spec = GitCompareSpec.tryParseTabId(id);
      return spec == null ? null : WorkbenchTabId.gitCompare(spec);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tree helpers
// ---------------------------------------------------------------------------

String? _groupContainingTab(WorkbenchGroupLayout layout, WorkbenchTabId tab) {
  for (final entry in layout.groups.entries) {
    if (entry.value.contains(tab)) return entry.key;
  }
  return null;
}

bool _treeContainsGroup(SplitNode node, String groupId) => switch (node) {
  SplitLeaf() => node.groupId == groupId,
  SplitBranch() =>
    _treeContainsGroup(node.first, groupId) ||
        _treeContainsGroup(node.second, groupId),
};

String _leftmostLeaf(SplitNode node) => switch (node) {
  SplitLeaf() => node.groupId,
  SplitBranch() => _leftmostLeaf(node.first),
};

/// Next free group id: one past the current max `g<n>` suffix. Derived from
/// the live ids (not their count) so pruned holes never cause collisions
/// with a surviving group.
String _nextGroupId(Iterable<String> groupIds) {
  var max = 0;
  for (final id in groupIds) {
    if (!id.startsWith('g') || id.length < 2) continue;
    final n = int.tryParse(id.substring(1));
    if (n != null && n > max) max = n;
  }
  return 'g${max + 1}';
}

/// Rebuilds the tree with the leaf [groupId] replaced by `replace(leaf)`.
SplitNode _replaceLeaf(
  SplitNode node,
  String groupId,
  SplitNode Function(SplitLeaf leaf) replace,
) => switch (node) {
  SplitLeaf() => node.groupId == groupId ? replace(node) : node,
  SplitBranch() => node.copyWith(
    first: _replaceLeaf(node.first, groupId, replace),
    second: _replaceLeaf(node.second, groupId, replace),
  ),
};

/// Drops every group whose strip is empty, rolling lone survivors up into
/// their parent's position (recursively). Returns null when nothing survives.
SplitNode? _pruneEmptyGroups(SplitNode node, Map<String, TabStrip> groups) {
  if (node is SplitBranch) {
    final first = _pruneEmptyGroups(node.first, groups);
    final second = _pruneEmptyGroups(node.second, groups);
    if (first == null && second == null) return null;
    if (first == null) return second;
    if (second == null) return first;
    return node.copyWith(first: first, second: second);
  }
  final leaf = node as SplitLeaf;
  return groups[leaf.groupId]?.order.isEmpty ?? true ? null : leaf;
}

/// Rebuilds the tree with the branch at [path] given [fraction]; null when
/// [path] addresses a leaf or walks off the tree.
SplitNode? _replaceFractionAtPath(SplitNode node, List<bool> path, double fraction) {
  if (path.isEmpty) {
    return node is SplitBranch ? node.copyWith(firstFraction: fraction) : null;
  }
  if (node is! SplitBranch) return null;
  final goSecond = path.first;
  final child = _replaceFractionAtPath(
    goSecond ? node.second : node.first,
    path.sublist(1),
    fraction,
  );
  if (child == null) return null;
  return node.copyWith(
    first: goSecond ? node.first : child,
    second: goSecond ? child : node.second,
  );
}
