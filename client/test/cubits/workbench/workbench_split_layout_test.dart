import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

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
    'g0': r.add(strip, b, preview: false).$1,
  });
}

WorkbenchGroupLayout _addToGroup(
  WorkbenchGroupLayout layout,
  String groupId,
  WorkbenchTabId tab,
) {
  const r = TabStripReducer();
  return layout.copyWith(groups: {
    ...layout.groups,
    groupId: r.add(layout.groups[groupId]!, tab, preview: false).$1,
  });
}

/// Id of the sibling group created by a `before: false` horizontal split.
String _splitSiblingId(WorkbenchGroupLayout layout) =>
    ((layout.root as SplitBranch).second as SplitLeaf).groupId;

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

    test('seeded form activates the seed tab', () {
      final l = singleGroupLayout(_s1);
      expect(l.groups['g0']!.order, [_s1]);
      expect(l.groups['g0']!.activeId, _s1);
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
      expect(
        r.split(singleGroupLayout(_s1), tab: _s3, axis: Axis.horizontal, before: false),
        isNull,
      );
    });

    test('before: true puts the new group as the first child', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.vertical, before: true)!;
      final b = l1.root as SplitBranch;
      expect(b.axis, Axis.vertical);
      final newId = (b.first as SplitLeaf).groupId;
      expect((b.second as SplitLeaf).groupId, 'g0');
      expect(l1.groups[newId]!.order, [_s2]);
      expect(l1.focusedGroupId, newId);
      expect(validateLayout(l1), isTrue);
    });

    test('new ids never collide with live groups', () {
      const r = SplitLayoutReducer();
      var l = _addToGroup(_seed(_s1, _s2), 'g0', _s3);
      l = r.split(l, tab: _s3, axis: Axis.horizontal, before: false)!; // g1
      l = r.split(l, tab: _s2, axis: Axis.horizontal, before: false)!; // g2
      // Pruning g1 must not let a later split reuse g1 or collide with g2.
      l = r.remove(l, _s3)!;
      expect(l.groups.keys, contains('g2'));
      l = _addToGroup(l, 'g0', _s3);
      l = r.split(l, tab: _s3, axis: Axis.horizontal, before: false)!;
      final newEntry = l.groups.entries.singleWhere((e) => e.value.order.contains(_s3));
      expect(newEntry.key, 'g3');
      expect(validateLayout(l), isTrue);
    });
  });

  group('splitInto', () {
    test('places the new sibling adjacent to the target group', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final targetId = _splitSiblingId(l1);
      final l2 = _addToGroup(l1, 'g0', _s3);
      final l3 = r.splitInto(
        l2,
        tab: _s3,
        targetGroupId: targetId,
        axis: Axis.horizontal,
        before: false,
      )!;
      expect(l3.leafGroupIds, ['g0', targetId, 'g2']);
      expect(l3.groups['g0']!.order, [_s1]);
      expect(l3.groups['g2']!.order, [_s3]);
      expect(l3.groups['g2']!.activeId, _s3);
      expect(l3.focusedGroupId, 'g2');
      expect(validateLayout(l3), isTrue);
    });

    test('before: true places the new group before the target', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final targetId = _splitSiblingId(l1);
      final l2 = _addToGroup(l1, 'g0', _s3);
      final l3 = r.splitInto(
        l2,
        tab: _s3,
        targetGroupId: targetId,
        axis: Axis.vertical,
        before: true,
      )!;
      expect(l3.leafGroupIds, ['g0', 'g2', targetId]);
      expect(l3.groups['g2']!.order, [_s3]);
      expect(l3.focusedGroupId, 'g2');
      expect(validateLayout(l3), isTrue);
    });

    test('degrades to split semantics when the target is the source group', () {
      const r = SplitLayoutReducer();
      final l1 = r.splitInto(
        _seed(_s1, _s2),
        tab: _s2,
        targetGroupId: 'g0',
        axis: Axis.horizontal,
        before: false,
      )!;
      final b = l1.root as SplitBranch;
      expect((b.first as SplitLeaf).groupId, 'g0');
      expect(l1.groups[(b.second as SplitLeaf).groupId]!.order, [_s2]);
      expect(l1.focusedGroupId, 'g1');
      expect(validateLayout(l1), isTrue);
    });

    test('null when the tab is the only tab of its source group', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = _addToGroup(l1, 'g0', _s3);
      expect(
        r.splitInto(l2, tab: _s2, targetGroupId: 'g0', axis: Axis.horizontal, before: false),
        isNull,
      );
    });

    test('null when the target group is not a live leaf', () {
      const r = SplitLayoutReducer();
      expect(
        r.splitInto(
          _seed(_s1, _s2),
          tab: _s2,
          targetGroupId: 'g9',
          axis: Axis.horizontal,
          before: false,
        ),
        isNull,
      );
    });
  });

  group('moveTab', () {
    test('moves across groups, activates the tab and focuses the target', () {
      const r = SplitLayoutReducer();
      final l0 = _addToGroup(_seed(_s1, _s2), 'g0', _s3);
      final l1 = r.split(l0, tab: _s3, axis: Axis.horizontal, before: false)!;
      final targetId = _splitSiblingId(l1);
      final l2 = r.moveTab(l1, tab: _s2, targetGroupId: targetId)!;
      expect(l2.groups['g0']!.order, [_s1]);
      expect(l2.groups[targetId]!.order, [_s3, _s2]);
      expect(l2.groups[targetId]!.activeId, _s2);
      expect(l2.focusedGroupId, targetId);
      expect(l2.root, isA<SplitBranch>());
      expect(validateLayout(l2), isTrue);
    });

    test('moving the sole tab prunes the source and rolls it up', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = r.moveTab(l1, tab: _s2, targetGroupId: 'g0')!;
      expect(l2.root, isA<SplitLeaf>());
      expect((l2.root as SplitLeaf).groupId, 'g0');
      expect(l2.groups['g0']!.order, [_s1, _s2]);
      expect(l2.groups['g0']!.activeId, _s2);
      expect(l2.focusedGroupId, 'g0');
      expect(validateLayout(l2), isTrue);
    });

    test('within the same group just activates and focuses', () {
      const r = SplitLayoutReducer();
      final l0 = _addToGroup(_seed(_s1, _s2), 'g0', _s3);
      final l1 = r.moveTab(l0, tab: _s1, targetGroupId: 'g0')!;
      expect(l1.groups['g0']!.order, [_s1, _s2, _s3]);
      expect(l1.groups['g0']!.activeId, _s1);
      expect(l1.focusedGroupId, 'g0');
      expect(validateLayout(l1), isTrue);
    });

    test('null when tab absent', () {
      const r = SplitLayoutReducer();
      expect(r.moveTab(singleGroupLayout(_s1), tab: _f, targetGroupId: 'g0'), isNull);
    });

    test('null when target group invalid', () {
      const r = SplitLayoutReducer();
      expect(r.moveTab(singleGroupLayout(_s1), tab: _s1, targetGroupId: 'gX'), isNull);
    });
  });

  group('activate / groupForTab', () {
    test('activate activates the tab in its owning group and focuses it', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final siblingId = _splitSiblingId(l1);
      final l2 = r.activate(l1, _s1);
      expect(l2.groups['g0']!.activeId, _s1);
      expect(l2.focusedGroupId, 'g0');
      expect(l2.groups[siblingId]!.order, [_s2]);
      expect(validateLayout(l2), isTrue);
    });

    test('activate is a no-op when the tab is absent', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      expect(identical(r.activate(l0, _f), l0), isTrue);
    });

    test('groupForTab returns the owning strip or null', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      expect(r.groupForTab(l1, _s2)!.order, [_s2]);
      expect(r.groupForTab(l1, _f), isNull);
    });
  });

  group('focusGroup', () {
    test('focuses the given group', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = r.focusGroup(l1, 'g0');
      expect(l2.focusedGroupId, 'g0');
      expect(validateLayout(l2), isTrue);
    });

    test('is a no-op for an unknown group', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      expect(identical(r.focusGroup(l0, 'gX'), l0), isTrue);
    });
  });

  group('toggleMaximize', () {
    test('sets then clears the maximized group', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      final l1 = r.toggleMaximize(l0, 'g0');
      expect(l1.maximizedGroupId, 'g0');
      final l2 = r.toggleMaximize(l1, 'g0');
      expect(l2.maximizedGroupId, isNull);
    });

    test('switches to another group', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final siblingId = _splitSiblingId(l1);
      final l2 = r.toggleMaximize(l1, 'g0');
      expect(l2.maximizedGroupId, 'g0');
      final l3 = r.toggleMaximize(l2, siblingId);
      expect(l3.maximizedGroupId, siblingId);
      expect(validateLayout(l3), isTrue);
    });

    test('is a no-op for an unknown group', () {
      const r = SplitLayoutReducer();
      final l0 = singleGroupLayout(_s1);
      expect(identical(r.toggleMaximize(l0, 'gX'), l0), isTrue);
    });
  });

  group('commitResizeByPath', () {
    test('sets the fraction of the branch at the path', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = r.commitResizeByPath(l1, path: const [], fraction: 0.7);
      expect((l2.root as SplitBranch).firstFraction, 0.7);
      expect(validateLayout(l2), isTrue);
    });

    test('resizes a nested branch via a non-empty path', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final targetId = _splitSiblingId(l1);
      final l2 = _addToGroup(l1, 'g0', _s3);
      final l3 = r.splitInto(
        l2,
        tab: _s3,
        targetGroupId: targetId,
        axis: Axis.vertical,
        before: false,
      )!;
      final l4 = r.commitResizeByPath(l3, path: const [true], fraction: 0.8);
      final root = l4.root as SplitBranch;
      final inner = root.second as SplitBranch;
      expect(inner.firstFraction, 0.8);
      expect(root.firstFraction, 0.5);
    });

    test('clamps out-of-range fractions to 0.05 / 0.95', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final tooBig = r.commitResizeByPath(l1, path: const [], fraction: 5);
      expect((tooBig.root as SplitBranch).firstFraction, 0.95);
      final tooSmall = r.commitResizeByPath(l1, path: const [], fraction: -3);
      expect((tooSmall.root as SplitBranch).firstFraction, 0.05);
    });

    test('returns the layout unchanged when the path hits a leaf', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final l2 = r.commitResizeByPath(l1, path: const [true], fraction: 0.8);
      expect(identical(l2, l1), isTrue);
    });
  });

  group('collapse', () {
    test('preserves all tabs and keeps the focused group active tab', () {
      const r = SplitLayoutReducer();
      final l0 = _addToGroup(_seed(_s1, _s2), 'g0', _s3);
      final l1 = r.split(l0, tab: _s3, axis: Axis.horizontal, before: false)!;
      final siblingId = _splitSiblingId(l1);
      final l2 = r.toggleMaximize(l1, siblingId);
      final l3 = r.collapse(l2);
      expect(l3.root, isA<SplitLeaf>());
      expect((l3.root as SplitLeaf).groupId, 'g0');
      expect(l3.groups.keys, ['g0']);
      expect(l3.groups['g0']!.order, [_s1, _s2, _s3]);
      expect(l3.groups['g0']!.activeId, _s3);
      expect(l3.focusedGroupId, 'g0');
      expect(l3.maximizedGroupId, isNull);
      expect(validateLayout(l3), isTrue);
    });

    test('falls back to the last tab when the focused group has no active', () {
      const r = SplitLayoutReducer();
      const stripReducer = TabStripReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final siblingId = _splitSiblingId(l1);
      final landed = l1.copyWith(groups: {
        ...l1.groups,
        siblingId: stripReducer.enterLanding(l1.groups[siblingId]!),
      });
      final l2 = r.collapse(landed);
      expect(l2.groups['g0']!.order, [_s1, _s2]);
      expect(l2.groups['g0']!.activeId, _s2);
      expect(validateLayout(l2), isTrue);
    });

    test('empty layout collapses to the degenerate empty root', () {
      const r = SplitLayoutReducer();
      final l = r.collapse(singleGroupLayout());
      expect(l.groups['g0']!.order, isEmpty);
      expect(l.root, isA<SplitLeaf>());
      expect(validateLayout(l), isTrue);
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

    test('repairs focus and clears maximize when the pruned group was focused', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final siblingId = _splitSiblingId(l1);
      expect(l1.focusedGroupId, siblingId);
      final l2 = r.toggleMaximize(l1, siblingId);
      final l3 = r.remove(l2, _s2)!;
      expect(l3.root, isA<SplitLeaf>());
      expect(l3.focusedGroupId, 'g0');
      expect(l3.maximizedGroupId, isNull);
      expect(validateLayout(l3), isTrue);
    });

    test('null when tab absent', () {
      const r = SplitLayoutReducer();
      expect(r.remove(singleGroupLayout(_s1), _f), isNull);
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

    test('rejects an orphan group present only in the groups map', () {
      final l0 = singleGroupLayout(_s1);
      final orphan = l0.copyWith(groups: {
        ...l0.groups,
        'g1': l0.groups['g0']!.copyWith(order: [_s2], activeId: _s2),
      });
      expect(validateLayout(orphan), isFalse);
    });

    test('rejects an empty non-root group', () {
      const r = SplitLayoutReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final emptied = l1.copyWith(groups: {
        ...l1.groups,
        'g0': l1.groups['g0']!.copyWith(order: [], activeId: null),
      });
      expect(validateLayout(emptied), isFalse);
    });

    test('rejects a stale focusedGroupId', () {
      final l0 = singleGroupLayout(_s1);
      expect(validateLayout(l0.copyWith(focusedGroupId: 'gX')), isFalse);
    });

    test('rejects a dangling leaf without a groups entry', () {
      final l0 = singleGroupLayout(_s1);
      expect(validateLayout(l0.copyWith(groups: {})), isFalse);
    });

    test('accepts the degenerate empty sole root', () {
      expect(validateLayout(singleGroupLayout()), isTrue);
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

    test('round-trips preview and pinned sets', () {
      const r = SplitLayoutReducer();
      const stripReducer = TabStripReducer();
      final l1 = r.split(_seed(_s1, _s2), tab: _s2, axis: Axis.horizontal, before: false)!;
      final newId = _splitSiblingId(l1);
      final l2 = l1.copyWith(groups: {
        ...l1.groups,
        'g0': stripReducer.add(l1.groups['g0']!, _f, preview: true).$1,
        newId: stripReducer.pin(l1.groups[newId]!, _s2),
      });
      final back = layoutFromSnapshot(toSnapshot(l2), tabResolves: (_) => true)!;
      expect(back.groups['g0']!.previewIds, {_f});
      expect(back.groups['g0']!.order, [_s1, _f]);
      expect(back.groups[newId]!.pinnedIds, {_s2});
      expect(validateLayout(back), isTrue);
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

    test('returns null when no group survives pruning', () {
      final back = layoutFromSnapshot(
        toSnapshot(singleGroupLayout(_s1)),
        tabResolves: (_) => false,
      );
      expect(back, isNull);
    });
  });
}
