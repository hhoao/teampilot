import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

void main() {
  test('gitGraph kind maps to gitGraph floating surface id', () {
    expect(surfaceIdFor(WorkbenchTabKind.gitGraph), 'gitGraph');
    expect(isCenterStripWorkbenchTab(WorkbenchTabKind.gitGraph), isFalse);
  });

  test('WorkbenchTabId.gitGraph carries repoRoot as id', () {
    final id = WorkbenchTabId.gitGraph('/repo');
    expect(id.kind, WorkbenchTabKind.gitGraph);
    expect(id.id, '/repo');
  });
}
