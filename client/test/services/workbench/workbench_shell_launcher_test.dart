import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_shell_launcher.dart';

void main() {
  group('resolveWorkbenchShellToggle', () {
    test('returns null when workspaceId is empty', () {
      expect(
        resolveWorkbenchShellToggle(
          workspaceId: '  ',
          resolveMostRecentShell: (_) => WorkbenchTabId.shell('e1'),
        ),
        isNull,
      );
    });

    test('selects most recent shell when present', () {
      final shell = WorkbenchTabId.shell('e1');
      final plan = resolveWorkbenchShellToggle(
        workspaceId: 'ws',
        resolveMostRecentShell: (id) {
          expect(id, 'ws');
          return shell;
        },
      );
      expect(plan, isNotNull);
      expect(plan!.action, WorkbenchShellToggleAction.selectExisting);
      expect(plan.existing, shell);
    });

    test('plans create when no shell tab exists', () {
      final plan = resolveWorkbenchShellToggle(
        workspaceId: 'ws',
        resolveMostRecentShell: (_) => null,
      );
      expect(plan, isNotNull);
      expect(plan!.action, WorkbenchShellToggleAction.createDefault);
      expect(plan.existing, isNull);
      expect(plan.workspaceId, 'ws');
    });
  });

  group('WorkbenchCubit.resolveMostRecentShell integration', () {
    late WorkbenchCubit cubit;

    setUp(() => cubit = WorkbenchCubit());
    tearDown(() => cubit.close());

    test('toggle plan selects last focused shell', () {
      const ws = 'ws';
      final e1 = WorkbenchTabId.shell('e1');
      final e2 = WorkbenchTabId.shell('e2');
      cubit.ensureTab(ws, e1);
      cubit.ensureTab(ws, e2);
      cubit.select(ws, e1);

      final plan = resolveWorkbenchShellToggle(
        workspaceId: ws,
        resolveMostRecentShell: cubit.resolveMostRecentShell,
      );
      expect(plan!.action, WorkbenchShellToggleAction.selectExisting);
      expect(plan.existing, e1);
    });
  });
}
