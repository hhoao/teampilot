import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_shell_run_sync_logic.dart';

void main() {
  group('runIdsToEnsureAndSelect', () {
    test('new RunPanel session → ensure run + select that id', () {
      expect(
        runIdsToEnsureAndSelect(
          tabOrder: [WorkbenchTabId.session('s1')],
          runPanelSessionIds: ['r1', 'r2'],
        ),
        ['r1', 'r2'],
      );
    });

    test('existing run tabs are not re-ensured', () {
      expect(
        runIdsToEnsureAndSelect(
          tabOrder: [WorkbenchTabId.run('r1')],
          runPanelSessionIds: ['r1', 'r2'],
        ),
        ['r2'],
      );
    });

    test('preserves runPanelSessionIds order so last is newest to select', () {
      expect(
        runIdsToEnsureAndSelect(
          tabOrder: const [],
          runPanelSessionIds: ['r-old', 'r-new'],
        ),
        ['r-old', 'r-new'],
      );
    });
  });

  group('runTabsToRemove', () {
    test('Run session gone → removeTab', () {
      expect(
        runTabsToRemove(
          tabOrder: [
            WorkbenchTabId.run('r1'),
            WorkbenchTabId.run('gone'),
            WorkbenchTabId.shell('e1'),
          ],
          runPanelSessionIds: ['r1'],
        ),
        [WorkbenchTabId.run('gone')],
      );
    });
  });

  group('floatingRunIdsToEnsure', () {
    test('live sessions missing from floating → ensure ids', () {
      expect(
        floatingRunIdsToEnsure(
          existingFloatingRunSessionIds: ['r1'],
          liveRunPanelSessionIds: ['r1', 'r2', 'r3'],
        ),
        ['r2', 'r3'],
      );
    });

    test('preserves live order', () {
      expect(
        floatingRunIdsToEnsure(
          existingFloatingRunSessionIds: const [],
          liveRunPanelSessionIds: ['r-old', 'r-new'],
        ),
        ['r-old', 'r-new'],
      );
    });

    test('all live sessions already floating → empty', () {
      expect(
        floatingRunIdsToEnsure(
          existingFloatingRunSessionIds: ['r1', 'r2'],
          liveRunPanelSessionIds: ['r1', 'r2'],
        ),
        isEmpty,
      );
    });
  });

  group('floatingRunIdsToRemove', () {
    test('floating run tab whose session is gone → remove id', () {
      expect(
        floatingRunIdsToRemove(
          existingFloatingRunSessionIds: ['r1', 'gone'],
          liveRunPanelSessionIds: ['r1'],
        ),
        ['gone'],
      );
    });

    test('no stale floating tabs → empty', () {
      expect(
        floatingRunIdsToRemove(
          existingFloatingRunSessionIds: ['r1'],
          liveRunPanelSessionIds: ['r1', 'r2'],
        ),
        isEmpty,
      );
    });
  });

  group('planWorkbenchShellRunSync', () {
    test('only removes stale center run tabs; never ensures run on center', () {
      final plan = planWorkbenchShellRunSync(
        tabOrder: [
          WorkbenchTabId.shell('keep-shell'),
          WorkbenchTabId.shell('drop-shell'),
          WorkbenchTabId.run('keep-run'),
          WorkbenchTabId.run('drop-run'),
          WorkbenchTabId.session('s1'),
        ],
        registryEntryIds: ['keep-shell', 'new-shell'],
        runPanelSessionIds: ['keep-run', 'new-run'],
      );

      expect(plan.shellIdsToEnsure, isEmpty);
      expect(plan.shellTabsToRemove, isEmpty);
      expect(plan.runIdsToEnsureAndSelect, isEmpty);
      expect(plan.runTabsToRemove, [WorkbenchTabId.run('drop-run')]);
    });
  });
}
