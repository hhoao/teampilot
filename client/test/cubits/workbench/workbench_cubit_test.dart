// test/cubits/workbench/workbench_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
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
      final bar = cubit.state.bar(_ws);
      expect(bar.center.order, [_s1]);
      expect(bar.center.activeId, _s1);
    });

    test('does not duplicate when opened twice', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's1');
      expect(
        cubit.state.bar(_ws).center.order.where((t) => t == _s1).length,
        1,
      );
    });
  });

  group('close', () {
    test('removes by id and never resurrects it', () async {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      final removed = await cubit.close(_ws, _s1);
      expect(removed, _s1);
      final order = cubit.state.bar(_ws).center.order;
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
        expect(cubit.state.bar(_ws).center.order, [_s2, _s1]);
      },
    );

    test('closing the final session clears the Landing prefill', () async {
      cubit
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      await cubit.close(_ws, _s1);

      final center = cubit.state.bar(_ws).center;
      expect(center.order, isEmpty);
      expect(center.landingInitialText, isNull);
    });
  });

  group('workspace isolation', () {
    test('buckets are independent per workspace', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession('other', 's2');
      expect(cubit.state.bar(_ws).center.order, [_s1]);
      expect(cubit.state.bar('other').center.order, [_s2]);
    });
  });

  group('reorder', () {
    test('moves a tab within bounds', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.reorder(_ws, 0, 1);
      expect(cubit.state.bar(_ws).center.order, [_s2, _s1]);
    });

    test('clamps newIndex == order.length (no crash, order kept)', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      // ReorderableListView may pass newIndex == itemCount when dragging to
      // the end; the cubit must not crash or mutate the order.
      cubit.reorder(_ws, 0, 2);
      expect(cubit.state.bar(_ws).center.order, [_s1, _s2]);
    });
  });

  group('closeOthers / closeRight / closeAll', () {
    test('closeOthers returns removed list', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.openSession(_ws, 's3');
      final removed = cubit.closeOthers(_ws, _s2);
      expect(removed, [_s1, _s3]);
      expect(cubit.state.bar(_ws).center.order, [_s2]);
    });

    test('closeOthers clears Landing prefill when a file remains', () {
      cubit
        ..openFile(_ws, '/a.dart')
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      cubit.closeOthers(_ws, _f);

      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_f]);
      expect(center.landingInitialText, isNull);
    });

    test('closeRight clears Landing prefill when a diff remains', () {
      cubit
        ..openDiff(_ws, _d)
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

      cubit.closeRight(_ws, _d);

      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_d]);
      expect(center.landingInitialText, isNull);
    });

    test('closeAll clears a Landing prefill', () {
      cubit
        ..openSession(_ws, 's1')
        ..enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session')
        ..closeAll(_ws);

      final center = cubit.state.bar(_ws).center;
      expect(center.order, isEmpty);
      expect(center.landingInitialText, isNull);
    });

    test(
      'closeAll clears a Landing prefill when the center is already empty',
      () {
        cubit.enterLanding(_ws, initialText: '审查并继续完成该会话: /data/session');

        final removed = cubit.closeAll(_ws);

        expect(removed, isEmpty);
        final center = cubit.state.bar(_ws).center;
        expect(center.order, isEmpty);
        expect(center.landingInitialText, isNull);
      },
    );
  });
}
