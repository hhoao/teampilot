import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_tab_projection.dart';

void main() {
  test('session tabs carry pinned; file tabs are not pinnable', () {
    final tabs = projectWorkbenchTabs(
      tabOrder: [
        WorkbenchTabId.session('s1'),
        WorkbenchTabId.file('/tmp/a.dart'),
        WorkbenchTabId.session('s2'),
      ],
      sessionTitles: {'s1': 'One', 's2': 'Two'},
      sessionWorking: const {},
      sessionCli: const {},
      sessionPinned: {'s1': true, 's2': false},
      editorBucket: const WorkspaceEditorBucket(),
      previewTabIds: const {},
    );

    expect(tabs[0].pinned, isTrue);
    expect(tabs[0].pinnable, isTrue);
    expect(tabs[1].pinned, isFalse);
    expect(tabs[1].pinnable, isFalse);
    expect(tabs[2].pinned, isFalse);
    expect(tabs[2].pinnable, isTrue);
  });
}
