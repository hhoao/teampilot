import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('openFile activates workbench tab before disk read finishes', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)..files['/repo/a.txt'] = 'hello';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    final pending = opener.openFile('ws', '/repo/a.txt');
    await Future<void>.delayed(Duration.zero);

    expect(
      workbench.activeTabId('ws'),
      WorkbenchTabId.file('/repo/a.txt'),
    );
    expect(editor.state.bucket('ws').openFilePaths, isEmpty);

    gate.complete();
    await pending;
    expect(editor.state.bucket('ws').openFilePaths, ['/repo/a.txt']);
  });

  test('openFile ensures workbench tab for image paths', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)
      ..byteFiles['/repo/a.png'] = const [1, 2, 3];
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    final pending = opener.openFile('ws', '/repo/a.png');
    await Future<void>.delayed(Duration.zero);

    expect(workbench.activeTabId('ws'), WorkbenchTabId.file('/repo/a.png'));
    gate.complete();
    await pending;
    expect(editor.bytesFor('ws', '/repo/a.png'), isNotNull);
  });
}

class _GatedFilesystem extends InMemoryFilesystem {
  _GatedFilesystem(this._gate);

  final Completer<void> _gate;

  @override
  Future<FsStat> stat(String path) async {
    await _gate.future;
    return super.stat(path);
  }
}
