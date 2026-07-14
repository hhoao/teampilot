import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/workspace_dock_tab.dart';

void main() {
  test('shell and run tabs use distinct id namespaces', () {
    const shell = WorkspaceDockShellTab('e1');
    const run = WorkspaceDockRunTab('e1');
    expect(shell.id, 'shell:e1');
    expect(run.id, 'run:e1');
    expect(shell, isNot(equals(run)));
  });
}
