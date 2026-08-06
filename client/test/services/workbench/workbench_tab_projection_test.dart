import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_tab_projection.dart';

void main() {
  group('projectWorkbenchTabs', () {
    const editorBucket = WorkspaceEditorBucket();

    test('omits shell and run tabs from center strip projection', () {
      final session = WorkbenchTabId.session('s1');
      final file = WorkbenchTabId.file('/repo/a.dart');
      final diff = WorkbenchTabId.diffStaged('/repo/a.dart', staged: false);
      final shell = WorkbenchTabId.shell('e1');
      final run = WorkbenchTabId.run('r1');

      final tabs = projectWorkbenchTabs(
        tabOrder: [session, file, diff, shell, run],
        sessionTitles: const {'s1': 'Chat'},
        sessionWorking: const {},
        sessionCli: const {},
        editorBucket: editorBucket,
        previewTabIds: const {},
      );

      expect(tabs.map((t) => t.id), ['s1', file.id, diff.id]);
    });
  });
}
