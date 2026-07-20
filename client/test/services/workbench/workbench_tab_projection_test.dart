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

  test('shell and run tabs project titles, icons, and non-preview pinnable false', () {
    final shell = WorkbenchTabId.shell('e1');
    final run = WorkbenchTabId.run('r1');
    final tabs = projectWorkbenchTabs(
      tabOrder: [shell, run],
      sessionTitles: const {},
      sessionWorking: const {},
      sessionCli: const {},
      editorBucket: const WorkspaceEditorBucket(),
      previewTabIds: {shell, run},
      shellTitles: {'e1': 'Terminal 1'},
      runTitles: {'r1': 'Run npm test'},
      runWorking: {'r1': true},
    );

    expect(tabs, hasLength(2));

    expect(tabs[0].id, 'e1');
    expect(tabs[0].title, 'Terminal 1');
    expect(tabs[0].icon, Icons.terminal_outlined);
    expect(tabs[0].pinnable, isFalse);
    expect(tabs[0].preview, isFalse);
    expect(tabs[0].working, isFalse);

    expect(tabs[1].id, 'r1');
    expect(tabs[1].title, 'Run npm test');
    expect(tabs[1].icon, Icons.play_arrow_rounded);
    expect(tabs[1].working, isTrue);
    expect(tabs[1].pinnable, isFalse);
    expect(tabs[1].preview, isFalse);
  });

  test('shell and run fall back to tab id when titles missing', () {
    final tabs = projectWorkbenchTabs(
      tabOrder: [
        WorkbenchTabId.shell('e2'),
        WorkbenchTabId.run('r2'),
      ],
      sessionTitles: const {},
      sessionWorking: const {},
      sessionCli: const {},
      editorBucket: const WorkspaceEditorBucket(),
      previewTabIds: const {},
    );

    expect(tabs[0].title, 'e2');
    expect(tabs[1].title, 'r2');
    expect(tabs[1].working, isFalse);
  });
}
