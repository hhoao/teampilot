// test/cubits/workbench/workbench_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');

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
      expect(cubit.state.bar(_ws).center.order.where((t) => t == _s1).length, 1);
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

    test('re-activating a closed id re-adds at the end (explicit open only)', () async {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      await cubit.close(_ws, _s1);
      cubit.openSession(_ws, 's1'); // explicit re-open
      expect(cubit.state.bar(_ws).center.order, [_s2, _s1]);
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

  group('legacy facade', () {
    test('bucket exposes old getters for existing readers', () {
      cubit.openSession(_ws, 's1');
      final bucket = cubit.state.bucket(_ws);
      expect(bucket.tabOrder, [_s1]);
      expect(bucket.activeTabId, _s1);
      expect(bucket.previewTabIds, isEmpty);
      expect(bucket.welcomeActive, isFalse);
    });

    test('legacy syncSessions still aligns sessions into the bar', () {
      cubit.openSession(_ws, 's1');
      cubit.syncSessions(_ws, ['s1', 's2']);
      expect(cubit.state.bar(_ws).center.order, contains(_s2));
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
  });
}
