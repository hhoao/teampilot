import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/git_compare.dart';

void main() {
  test('gitCompare kind maps to gitCompare floating surface id', () {
    expect(surfaceIdFor(WorkbenchTabKind.gitCompare), 'gitCompare');
    expect(isCenterStripWorkbenchTab(WorkbenchTabKind.gitCompare), isFalse);
  });

  test('WorkbenchTabId.gitCompare carries spec.tabId as id', () {
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('main'),
      right: const GitCompareWorkingTree(),
    );
    final id = WorkbenchTabId.gitCompare(spec);
    expect(id.kind, WorkbenchTabKind.gitCompare);
    expect(id.id, spec.tabId);
  });
}
