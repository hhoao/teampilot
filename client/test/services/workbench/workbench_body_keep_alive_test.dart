import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_body_keep_alive.dart';

void main() {
  group('resolveWorkbenchBodyKeepAlive', () {
    test('empty tabOrder → no shell mount, no run surfaces', () {
      final plan = resolveWorkbenchBodyKeepAlive(
        tabOrder: const [],
        active: null,
        liveRunSessionIds: const ['r1'],
      );
      expect(plan.mountShell, isFalse);
      expect(plan.shellActiveEntryId, isNull);
      expect(plan.runSessionIds, isEmpty);
    });

    test('shell ids from tabOrder; active shell drives activeEntryId', () {
      final plan = resolveWorkbenchBodyKeepAlive(
        tabOrder: [
          WorkbenchTabId.session('s1'),
          WorkbenchTabId.shell('e1'),
          WorkbenchTabId.shell('e2'),
        ],
        active: WorkbenchTabId.shell('e1'),
        liveRunSessionIds: const [],
      );
      expect(plan.mountShell, isTrue);
      expect(plan.shellEntryIds, ['e1', 'e2']);
      expect(plan.shellActiveEntryId, 'e1');
      expect(plan.shellOffstage, isFalse);
    });

    test('when active is not shell, still mount and use last shell id', () {
      final plan = resolveWorkbenchBodyKeepAlive(
        tabOrder: [
          WorkbenchTabId.shell('e1'),
          WorkbenchTabId.session('s1'),
          WorkbenchTabId.shell('e2'),
        ],
        active: WorkbenchTabId.session('s1'),
        liveRunSessionIds: const [],
      );
      expect(plan.mountShell, isTrue);
      expect(plan.shellActiveEntryId, 'e2');
      expect(plan.shellOffstage, isTrue);
    });

    test('run ids = tabOrder ∩ live RunCubit sessions', () {
      final plan = resolveWorkbenchBodyKeepAlive(
        tabOrder: [
          WorkbenchTabId.run('r1'),
          WorkbenchTabId.session('s1'),
          WorkbenchTabId.run('gone'),
          WorkbenchTabId.run('r2'),
        ],
        active: WorkbenchTabId.run('r2'),
        liveRunSessionIds: const ['r1', 'r2'],
      );
      expect(plan.runSessionIds, ['r1', 'r2']);
      expect(plan.runOffstage('r1'), isTrue);
      expect(plan.runOffstage('r2'), isFalse);
    });
  });
}
