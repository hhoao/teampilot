import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

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
      workbench.state.bucket('ws').tabOrder.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      floating.state.activeBucket.tabs.any((t) => t.payload == '/repo/a.txt'),
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

    expect(workbench.activeTabId('ws')?.kind, isNot(WorkbenchTabKind.file));
    expect(
      workbench.state.bucket('ws').tabOrder.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      floating.state.activeBucket.tabs.any((t) => t.payload == '/repo/a.txt'),
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
      workbench.state.bucket('ws').tabOrder.where(
        (t) => t.kind == WorkbenchTabKind.file,
      ),
      isEmpty,
    );
    expect(
      floating.state.activeBucket.tabs.any((t) => t.payload == '/repo/a.png'),
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
      absolutePath: '/repo/a.txt',
      source: WorkbenchDiffSource.changes,
      title: 'a.txt',
      diffText: 'diff',
    );

    final diffKey = WorkbenchTabId.diffKey(
      '/repo/a.txt',
      source: WorkbenchDiffSource.changes,
    );
    expect(workbench.state.bucket('ws').tabOrder, isEmpty);
    expect(
      floating.state.activeBucket.tabs.any((t) => t.payload == diffKey),
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
      absolutePath: '/repo/a.txt',
      source: WorkbenchDiffSource.changes,
      title: 'a.txt',
      diffText: 'diff',
    );

    expect(
      workbench.activeTabId('ws'),
      WorkbenchTabId.diff('/repo/a.txt', source: WorkbenchDiffSource.changes),
    );
    expect(floating.state.activeBucket.tabs, isEmpty);
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

    expect(workbench.activeTabId('ws')?.kind, WorkbenchTabKind.file);
    expect(workbench.activeTabId('ws')?.id, '/repo/a.txt');
    expect(floating.state.activeBucket.tabs, isEmpty);
    expect(editor.state.bucket('ws').openFilePaths, contains('/repo/a.txt'));
  });

  group('dismissNewChat on open', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test('openFile floating path does not dismiss compose', () async {
      final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      final chat = _SpyChatCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      addTearDown(chat.close);

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        chat: chat,
      );
      await opener.openFile('ws', '/repo/a.txt');

      expect(chat.dismissNewChatCallCount, 0);
    });

    test('openDiff floating path does not dismiss compose', () {
      final editor = EditorCubit();
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      final chat = _SpyChatCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      addTearDown(chat.close);

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        chat: chat,
      );
      opener.openDiff(
        workspaceId: 'ws',
        absolutePath: '/repo/a.txt',
        source: WorkbenchDiffSource.changes,
        title: 'a.txt',
        diffText: 'diff',
      );

      expect(chat.dismissNewChatCallCount, 0);
    });

    test('openFile center path dismisses compose', () async {
      final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      final chat = _SpyChatCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      addTearDown(chat.close);

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readFilePreviewInFloating: () => false,
        chat: chat,
      );
      await opener.openFile('ws', '/repo/a.txt');

      expect(chat.dismissNewChatCallCount, 1);
    });

    test('openDiff center path dismisses compose', () {
      final editor = EditorCubit();
      final workbench = WorkbenchCubit();
      final floating = FloatingWorkspaceCubit();
      final chat = _SpyChatCubit();
      addTearDown(editor.close);
      addTearDown(workbench.close);
      addTearDown(floating.close);
      addTearDown(chat.close);

      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readFilePreviewInFloating: () => false,
        chat: chat,
      );
      opener.openDiff(
        workspaceId: 'ws',
        absolutePath: '/repo/a.txt',
        source: WorkbenchDiffSource.changes,
        title: 'a.txt',
        diffText: 'diff',
      );

      expect(chat.dismissNewChatCallCount, 1);
    });
  });
}

class _SpyChatCubit extends ChatCubit {
  _SpyChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  int dismissNewChatCallCount = 0;

  @override
  void dismissNewChat() {
    dismissNewChatCallCount++;
    super.dismissNewChat();
  }
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
