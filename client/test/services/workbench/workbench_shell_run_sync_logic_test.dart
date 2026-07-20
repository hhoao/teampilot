import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_shell_run_sync_logic.dart';

void main() {
  group('shellIdsToEnsure', () {
    test('new registry entry ids not in tabOrder → ensure shell', () {
      expect(
        shellIdsToEnsure(
          tabOrder: [WorkbenchTabId.session('s1')],
          registryEntryIds: ['e1', 'e2'],
        ),
        ['e1', 'e2'],
      );
    });

    test('existing shell tabs are not re-ensured', () {
      expect(
        shellIdsToEnsure(
          tabOrder: [
            WorkbenchTabId.shell('e1'),
            WorkbenchTabId.session('s1'),
          ],
          registryEntryIds: ['e1', 'e2'],
        ),
        ['e2'],
      );
    });

    test('activateToolWindow false shell still ensured (no select semantics)', () {
      // Pure ensure list is independent of activate flags; selection is a
      // separate apply step. Registry entries always appear here.
      expect(
        shellIdsToEnsure(
          tabOrder: const [],
          registryEntryIds: ['quiet-shell'],
        ),
        ['quiet-shell'],
      );
    });
  });

  group('shellTabsToRemove', () {
    test('registry missing entry still in tabOrder → removeTab', () {
      expect(
        shellTabsToRemove(
          tabOrder: [
            WorkbenchTabId.shell('e1'),
            WorkbenchTabId.shell('gone'),
            WorkbenchTabId.session('s1'),
          ],
          registryEntryIds: ['e1'],
        ),
        [WorkbenchTabId.shell('gone')],
      );
    });
  });

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
    test('combines ensure and remove for shell and run', () {
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

      expect(plan.shellIdsToEnsure, ['new-shell']);
      expect(plan.shellTabsToRemove, [WorkbenchTabId.shell('drop-shell')]);
      expect(plan.runIdsToEnsureAndSelect, ['new-run']);
      expect(plan.runTabsToRemove, [WorkbenchTabId.run('drop-run')]);
    });
  });
}
