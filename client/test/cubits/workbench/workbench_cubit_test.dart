// test/cubits/workbench/workbench_cubit_test.dart
import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');
final _f = WorkbenchTabId.file('/a.dart');
final _d = WorkbenchTabId.diffChanges('/a.dart');

void main() {
  late WorkbenchCubit cubit;
  setUp(() => cubit = WorkbenchCubit());

  group('openSession', () {
    test('adds and activates a new session tab', () {
      cubit.openSession(_ws, 's1');
      expect(cubit.centerOrder(_ws), [_s1]);
      expect(cubit.centerActiveId(_ws), _s1);
    });

    test('does not duplicate when opened twice', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's1');
      expect(cubit.centerOrder(_ws).where((t) => t == _s1).length, 1);
    });
  });

  group('close', () {
    test('removes by id and never resurrects it', () async {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      final removed = await cubit.close(_ws, _s1);
      expect(removed, _s1);
      final order = cubit.centerOrder(_ws);
      expect(order, [_s2]);
      expect(order.contains(_s1), isFalse);
    });

    test(
      're-activating a closed id re-adds at the end (explicit open only)',
      () async {
        cubit.openSession(_ws, 's1');
        cubit.openSession(_ws, 's2');
        await cubit.close(_ws, _s1);
        cubit.openSession(_ws, 's1'); // explicit re-open
        expect(cubit.centerOrder(_ws), [_s2, _s1]);
      },
    );

    test('closing the final session clears the Landing prefill', () async {
      cubit
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      await cubit.close(_ws, _s1);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, isEmpty);
      expect(center.landingInitialText, isNull);
    });
  });

  group('workspace isolation', () {
    test('buckets are independent per workspace', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession('other', 's2');
      expect(cubit.centerOrder(_ws), [_s1]);
      expect(cubit.centerOrder('other'), [_s2]);
    });
  });

  group('reorder', () {
    test('moves a tab within bounds', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.reorder(_ws, 0, 1);
      expect(cubit.centerOrder(_ws), [_s2, _s1]);
    });

    test('clamps newIndex == order.length (no crash, order kept)', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      // ReorderableListView may pass newIndex == itemCount when dragging to
      // the end; the cubit must not crash or mutate the order.
      cubit.reorder(_ws, 0, 2);
      expect(cubit.centerOrder(_ws), [_s1, _s2]);
    });
  });

  group('closeOthers / closeRight / closeAll', () {
    test('closeOthers returns removed list', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.openSession(_ws, 's3');
      final removed = cubit.closeOthers(_ws, _s2);
      expect(removed, [_s1, _s3]);
      expect(cubit.centerOrder(_ws), [_s2]);
    });

    test('closeOthers clears Landing prefill when a file remains', () {
      cubit
        ..openFile(_ws, '/a.dart')
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      cubit.closeOthers(_ws, _f);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, [_f]);
      expect(center.landingInitialText, isNull);
    });

    test('closeOthers preserves a reference to an unopened Session', () {
      cubit
        ..openFile(_ws, '/a.dart')
        ..openSession(_ws, 'unrelated')
        ..enterLanding(
          _ws,
          initialText: '审查并继续完成该会话: /data/referenced',
          referencedSessionId: 'unopened-reference',
        );

      cubit.closeOthers(_ws, _f);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, [_f]);
      expect(center.landingInitialText, '审查并继续完成该会话: /data/referenced');
      expect(center.landingReferenceSessionId, 'unopened-reference');
    });

    test('closeRight clears Landing prefill when a diff remains', () {
      cubit
        ..openDiff(_ws, _d)
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      cubit.closeRight(_ws, _d);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, [_d]);
      expect(center.landingInitialText, isNull);
    });

    test(
      'closeRight preserves a reference when removing an unrelated Session',
      () {
        cubit
          ..openDiff(_ws, _d)
          ..openSession(_ws, 'unrelated')
          ..enterLanding(
            _ws,
            initialText: '审查并继续完成该会话: /data/referenced',
            referencedSessionId: 'unopened-reference',
          );

        cubit.closeRight(_ws, _d);

        final center = cubit.centerFocusedStrip(_ws);
        expect(center.order, [_d]);
        expect(center.landingInitialText, '审查并继续完成该会话: /data/referenced');
        expect(center.landingReferenceSessionId, 'unopened-reference');
      },
    );

    test('closeAll clears a Landing prefill', () {
      cubit
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session')
        ..closeAll(_ws);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, isEmpty);
      expect(center.landingInitialText, isNull);
    });

    test('closeAll preserves a reference to an unopened Session', () {
      cubit
        ..openFile(_ws, '/a.dart')
        ..openSession(_ws, 'unrelated')
        ..enterLanding(
          _ws,
          initialText: '审查并继续完成该会话: /data/referenced',
          referencedSessionId: 'unopened-reference',
        );

      cubit.closeAll(_ws);

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.order, isEmpty);
      expect(center.landingInitialText, '审查并继续完成该会话: /data/referenced');
      expect(center.landingReferenceSessionId, 'unopened-reference');
    });

    test(
      'closeAll clears a Landing prefill when the center is already empty',
      () {
        cubit.enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

        final removed = cubit.closeAll(_ws);

        expect(removed, isEmpty);
        final center = cubit.centerFocusedStrip(_ws);
        expect(center.order, isEmpty);
        expect(center.landingInitialText, isNull);
      },
    );

    test('onSessionDeleted clears reference and advances its revision', () {
      cubit
        ..openSession(_ws, 'unrelated')
        ..enterLanding(
          _ws,
          initialText: '审查并继续完成该会话: /data/referenced',
          referencedSessionId: 'deleted',
        );
      final before = cubit.centerFocusedStrip(_ws);

      cubit.onSessionDeleted(_ws, 'deleted');

      final center = cubit.centerFocusedStrip(_ws);
      expect(center.landingInitialText, isNull);
      expect(center.landingReferenceSessionId, isNull);
      expect(
        center.landingInitialTextRevision,
        before.landingInitialTextRevision + 1,
      );
    });
  });

  group('floating preview/pin', () {
    test('openFloating(preview: true) replaces the previous preview slot', () {
      final replaced1 = cubit.openFloating(
        _ws,
        WorkbenchTabId.file('/a.dart'),
        preview: true,
      );
      expect(replaced1, isNull);
      final replaced2 = cubit.openFloating(
        _ws,
        WorkbenchTabId.file('/b.dart'),
        preview: true,
      );
      expect(replaced2, WorkbenchTabId.file('/a.dart'));
      expect(cubit.floatingOrder(_ws), [WorkbenchTabId.file('/b.dart')]);
      expect(
        cubit.floatingFocusedStrip(_ws).previewIds,
        {WorkbenchTabId.file('/b.dart')},
      );
    });

    test('openFloating(preview: false) keeps both tabs (normal)', () {
      cubit.openFloating(_ws, WorkbenchTabId.file('/a.dart'));
      cubit.openFloating(_ws, WorkbenchTabId.file('/b.dart'));
      expect(cubit.floatingOrder(_ws).length, 2);
      expect(cubit.floatingFocusedStrip(_ws).previewIds, isEmpty);
    });

    test('pin/unpin route by strip presence (floating)', () {
      final id = WorkbenchTabId.shell('e1');
      cubit.openFloating(_ws, id);
      cubit.pin(_ws, id);
      expect(cubit.floatingFocusedStrip(_ws).pinnedIds, {id});
      cubit.unpin(_ws, id);
      expect(cubit.floatingFocusedStrip(_ws).pinnedIds, isEmpty);
    });

    test('promote routes by strip presence (floating)', () {
      cubit.openFloating(_ws, _f, preview: true);
      cubit.promote(_ws, _f);
      expect(cubit.floatingFocusedStrip(_ws).previewIds, isEmpty);
    });

    test('closeAll skips pinned center tabs', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2');
      cubit.pin(_ws, _s1);
      final removed = cubit.closeAll(_ws);
      expect(removed, [_s2]);
      expect(cubit.centerOrder(_ws), [_s1]);
    });

    test('closeOthers and closeRight skip pinned center tabs', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..openSession(_ws, 's3');
      cubit.pin(_ws, _s3);
      final removed = cubit.closeOthers(_ws, _s1);
      expect(removed, [_s2]);
      expect(cubit.centerOrder(_ws), [_s1, _s3]);

      final removedRight = cubit.closeRight(_ws, _s1);
      expect(removedRight, isEmpty);
      expect(cubit.centerOrder(_ws), [_s1, _s3]);
    });
  });

  group('split groups', () {
    test('splitTab moves tab into new group and focuses it', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
      expect(cubit.centerOrder(_ws), [_s2]); // focused = new group
      expect(cubit.centerActiveId(_ws), _s2);
      final layout = cubit.centerLayout(_ws);
      expect(layout.root, isA<SplitBranch>());
      expect(
        cubit.state.bar(_ws).center.groups.values
            .expand((s) => s.order)
            .toSet(),
        {_s1, _s2},
      );
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
      // focus back to g0 by activating its tab
      cubit.activate(_ws, _s1);
      expect(cubit.centerFocusedGroupId(_ws), 'g0');
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

    test(
      'closeAll keeps pinned tabs of the focused group only (group-scoped)',
      () {
        cubit
          ..openSession(_ws, 's1')
          ..openSession(_ws, 's2')
          ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
          // s3 lands in the focused split group; pin s2 inside it.
          ..openSession(_ws, 's3')
          ..pin(_ws, _s2);
        final removed = cubit.closeAll(_ws);
        // The focused group's unpinned tab closed; its pinned tab survived.
        expect(removed, [_s3]);
        expect(cubit.centerOrder(_ws), [_s2]);
        expect(
          cubit.centerLayout(_ws).groups['g1']!.pinnedIds,
          contains(_s2),
        );
        // The non-focused group is untouched by the group-scoped closeAll.
        expect(cubit.centerLayout(_ws).groups['g0']!.order, [_s1]);
      },
    );

    test('moveTab moves a tab between groups and prunes an emptied source',
        () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
        ..openSession(_ws, 's3'); // g1 = [s2, s3]
      cubit.moveTab(_ws, _s2, 'g0');
      expect(cubit.centerLayout(_ws).root, isA<SplitBranch>());
      expect(cubit.centerFocusedGroupId(_ws), 'g0');
      expect(cubit.centerOrder(_ws), [_s1, _s2]);
      expect(cubit.centerLayout(_ws).groups['g1']!.order, [_s3]);
    });

    test('focusGroup / toggleMaximizeGroup / collapseSplitLayout round-trip',
        () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false);
      cubit.focusGroup(_ws, 'g0');
      expect(cubit.centerFocusedGroupId(_ws), 'g0');
      cubit.toggleMaximizeGroup(_ws, 'g0');
      expect(cubit.centerLayout(_ws).maximizedGroupId, 'g0');
      cubit.toggleMaximizeGroup(_ws, 'g0');
      expect(cubit.centerLayout(_ws).maximizedGroupId, isNull);
      cubit.collapseSplitLayout(_ws);
      expect(cubit.centerLayout(_ws).root, isA<SplitLeaf>());
      expect(cubit.centerOrder(_ws), [_s1, _s2]);
    });

    test('splitTab on a sole tab is a silent no-op', () {
      cubit.openSession(_ws, 's1');
      final before = cubit.state.bar(_ws);
      cubit.splitTab(_ws, _s1, axis: Axis.horizontal, before: false);
      expect(cubit.state.bar(_ws), before);
    });
  });

  group('revealTabBeside', () {
    test('moves the tab into the adjacent right group and focuses it', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..openSession(_ws, 's3')
        ..splitTab(_ws, _s3, axis: Axis.horizontal, before: false) // g1 [s3]
        ..activate(_ws, _s1); // focused g0, active s1
      cubit.revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
      final layout = cubit.centerLayout(_ws);
      expect(layout.groups['g0']!.order, [_s1]);
      expect(layout.groups['g1']!.order, [_s3, _s2]);
      expect(layout.groups['g1']!.activeId, _s2);
      expect(layout.focusedGroupId, 'g1');
      expect(validateLayout(layout), isTrue);
    });

    test('tab already in the adjacent group just activates and focuses', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false) // g1 [s2]
        ..activate(_ws, _s1) // focused g0, active s1
        ..revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
      final layout = cubit.centerLayout(_ws);
      expect(layout.groups['g0']!.order, [_s1]);
      expect(layout.groups['g1']!.order, [_s2]);
      expect(layout.focusedGroupId, 'g1');
      expect(layout.groups['g1']!.activeId, _s2);
    });

    test('sole tab of the rightmost group degrades to activate + focus', () {
      cubit
        ..openSession(_ws, 's1')
        ..openSession(_ws, 's2')
        ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false); // g1 [s2], focused g1
      cubit.revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
      final layout = cubit.centerLayout(_ws);
      expect(layout.leafGroupIds, ['g0', 'g1']); // tree unchanged
      expect(layout.focusedGroupId, 'g1');
      expect(layout.groups['g1']!.activeId, _s2);
    });

    test('absent tab is a silent no-op', () {
      cubit.openSession(_ws, 's1');
      cubit.revealTabBeside(
        _ws,
        WorkbenchTabId.session('s9'),
        axis: Axis.horizontal,
        before: false,
      );
      expect(cubit.centerLayout(_ws).groups['g0']!.order, [_s1]);
    });
  });
}
