import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/diff_identity.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('openFile activates floating tab before disk read finishes', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)..files['/repo/a.txt'] = 'hello';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    final pending = opener.openFile('ws', '/repo/a.txt');
    await Future<void>.delayed(Duration.zero);

    expect(
      workbench.state.bar('ws').center.order.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      workbench.state.bar('ws').floating.order.any(
            (t) => t.kind == WorkbenchTabKind.file && t.id == '/repo/a.txt',
          ),
      isTrue,
    );
    expect(floating.state.visibility, FloatingPanelVisibility.open);
    expect(editor.state.bucket('ws').openFilePaths, isEmpty);

    gate.complete();
    await pending;
    expect(editor.state.bucket('ws').openFilePaths, contains('/repo/a.txt'));
  });

  test('openFile opens editor and floating tab, not workbench file tab', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)..files['/repo/a.txt'] = 'hello';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
    floating.setActiveWorkspace('ws');

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    gate.complete();
    await opener.openFile('ws', '/repo/a.txt');

    expect(workbench.centerActiveId('ws')?.kind, isNot(WorkbenchTabKind.file));
    expect(
      workbench.state.bar('ws').center.order.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      workbench.state.bar('ws').floating.order.any(
            (t) => t.kind == WorkbenchTabKind.file && t.id == '/repo/a.txt',
          ),
      isTrue,
    );
    expect(floating.state.visibility, FloatingPanelVisibility.open);
    expect(editor.state.bucket('ws').openFilePaths, contains('/repo/a.txt'));
  });

  test('openFile ensures floating tab for image paths', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)
      ..byteFiles['/repo/a.png'] = const [1, 2, 3];
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    final pending = opener.openFile('ws', '/repo/a.png');
    await Future<void>.delayed(Duration.zero);

    expect(
      workbench.state.bar('ws').center.order.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      workbench.state.bar('ws').floating.order.any(
            (t) => t.kind == WorkbenchTabKind.file && t.id == '/repo/a.png',
          ),
      isTrue,
    );
    expect(floating.state.visibility, FloatingPanelVisibility.open);
    gate.complete();
    await pending;
    expect(editor.bytesFor('ws', '/repo/a.png'), isNotNull);
  });

  test('openDiff opens floating diff tab by default', () {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    opener.openDiff(
      workspaceId: 'ws',
      identity: const ScmDiffIdentity('/repo/a.txt', ScmDiffMode.changes),
      title: 'a.txt',
      diffText: 'diff',
    );

    const diffKey = '/repo/a.txt::scm.changes';
    expect(workbench.state.bar('ws').center.order, isEmpty);
    expect(
      workbench.state.bar('ws').floating.order.any(
            (t) => t.kind == WorkbenchTabKind.diff && t.id == diffKey,
          ),
      isTrue,
    );
    expect(floating.state.visibility, FloatingPanelVisibility.open);
    expect(editor.state.bucket('ws').openDiffs.containsKey(diffKey), isTrue);
  });

  test('openDiff creates center workbench tab when filePreviewHost is center', () {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      readFilePreviewInFloating: () => false,
    );
    opener.openDiff(
      workspaceId: 'ws',
      identity: const ScmDiffIdentity('/repo/a.txt', ScmDiffMode.changes),
      title: 'a.txt',
      diffText: 'diff',
    );

    expect(
      workbench.centerActiveId('ws'),
      WorkbenchTabId.diffChanges('/repo/a.txt'),
    );
    expect(workbench.state.bar('ws').floating.order, isEmpty);
  });

  test('openFile opens center workbench tab when filePreviewHost is center', () async {
    final gate = Completer<void>();
    final fs = _GatedFilesystem(gate)..files['/repo/a.txt'] = 'hello';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      readFilePreviewInFloating: () => false,
    );
    gate.complete();
    await opener.openFile('ws', '/repo/a.txt');

    expect(workbench.centerActiveId('ws')?.kind, WorkbenchTabKind.file);
    expect(workbench.centerActiveId('ws')?.id, '/repo/a.txt');
    expect(workbench.state.bar('ws').floating.order, isEmpty);
    expect(editor.state.bucket('ws').openFilePaths, contains('/repo/a.txt'));
  });

  group('landing exit on open', () {
    test('openFile floating path stays on the landing', () async {
      final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      workbench.enterLanding('ws');

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      );
      await opener.openFile('ws', '/repo/a.txt');

      expect(workbench.state.bar('ws').center.landingActive, isTrue);
    });

    test('openDiff floating path stays on the landing', () {
      final editor = EditorCubit();
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      workbench.enterLanding('ws');

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      );
      opener.openDiff(
        workspaceId: 'ws',
        identity: const ScmDiffIdentity('/repo/a.txt', ScmDiffMode.changes),
        title: 'a.txt',
        diffText: 'diff',
      );

      expect(workbench.state.bar('ws').center.landingActive, isTrue);
    });

    test('openFile center path exits the landing', () async {
      final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      workbench.enterLanding('ws');

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readFilePreviewInFloating: () => false,
      );
      await opener.openFile('ws', '/repo/a.txt');

      expect(workbench.state.bar('ws').center.landingActive, isFalse);
      expect(workbench.centerActiveId('ws')?.kind, WorkbenchTabKind.file);
    });

    test('openDiff center path exits the landing', () {
      final editor = EditorCubit();
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      workbench.enterLanding('ws');

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readFilePreviewInFloating: () => false,
      );
      opener.openDiff(
        workspaceId: 'ws',
        identity: const ScmDiffIdentity('/repo/a.txt', ScmDiffMode.changes),
        title: 'a.txt',
        diffText: 'diff',
      );

      expect(workbench.state.bar('ws').center.landingActive, isFalse);
      expect(workbench.centerActiveId('ws')?.kind, WorkbenchTabKind.diff);
    });
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
