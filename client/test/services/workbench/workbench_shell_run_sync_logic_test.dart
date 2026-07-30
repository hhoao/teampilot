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

  group('planWorkbenchShellRunSync', () {
    test('only syncs run tabs; never projects shell onto center strip', () {
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
      expect(plan.runIdsToEnsureAndSelect, ['new-run']);
      expect(plan.runTabsToRemove, [WorkbenchTabId.run('drop-run')]);
    });
  });
}
