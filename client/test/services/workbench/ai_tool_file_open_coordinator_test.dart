import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/ai_tool_file_open_coordinator.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  const workspaceId = 'ws-1';

  late InMemoryFilesystem fs;
  late EditorCubit editor;
  late WorkbenchEditorOpener opener;
  late AiToolFileOpenCoordinator coordinator;

  setUp(() {
    fs = InMemoryFilesystem();
    editor = EditorCubit(fs: fs);
    opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: WorkbenchCubit(),
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );
    coordinator = AiToolFileOpenCoordinator(
      opener: opener,
      editor: editor,
    );
  });

  tearDown(() {
    editor.close();
  });

  test('relative path resolves against session working directory first', () async {
    fs.files['/session/src/foo.dart'] = 'line1\nline2\n';
    fs.files['/workspace/src/foo.dart'] = 'other';

    final result = await coordinator.openToolFile(
      workspaceId: workspaceId,
      target: const AiToolFileTarget(path: 'src/foo.dart'),
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const ['/workspace'],
      fs: fs,
    );

    expect(result.isMissing, isFalse);
    expect(result.resolvedPath, '/session/src/foo.dart');
    expect(editor.state.bucket(workspaceId).openFilePaths, ['/session/src/foo.dart']);
  });

  test('falls back to workspace folder when missing in session cwd', () async {
    fs.files['/workspace/src/foo.dart'] = 'line1\n';

    final result = await coordinator.openToolFile(
      workspaceId: workspaceId,
      target: const AiToolFileTarget(path: 'src/foo.dart'),
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const ['/workspace', '/other'],
      fs: fs,
    );

    expect(result.isMissing, isFalse);
    expect(result.resolvedPath, '/workspace/src/foo.dart');
    expect(editor.state.bucket(workspaceId).openFilePaths, ['/workspace/src/foo.dart']);
  });

  test('absolute path is used as-is when it exists', () async {
    fs.files['/abs/path.dart'] = 'content';

    final result = await coordinator.openToolFile(
      workspaceId: workspaceId,
      target: const AiToolFileTarget(path: '/abs/path.dart'),
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const ['/workspace'],
      fs: fs,
    );

    expect(result.isMissing, isFalse);
    expect(result.resolvedPath, '/abs/path.dart');
    expect(editor.state.bucket(workspaceId).openFilePaths, ['/abs/path.dart']);
  });

  test('missing path returns isMissing without throwing', () async {
    final result = await coordinator.openToolFile(
      workspaceId: workspaceId,
      target: const AiToolFileTarget(path: 'missing.dart'),
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const ['/workspace'],
      fs: fs,
    );

    expect(result.isMissing, isTrue);
    expect(result.resolvedPath, isNull);
    expect(editor.state.bucket(workspaceId).openFilePaths, isEmpty);
  });

  test('selects line range when startLine is set', () async {
    fs.files['/session/a.dart'] = 'a\nb\nc\n';

    await coordinator.openToolFile(
      workspaceId: workspaceId,
      target: const AiToolFileTarget(path: 'a.dart', startLine: 2, endLine: 3),
      sessionWorkingDirectory: '/session',
      workspaceFolderPaths: const [],
      fs: fs,
    );

    final controller = editor.controllerFor(workspaceId, '/session/a.dart');
    expect(controller, isNotNull);
    expect(
      controller!.selection,
      const CodeLineSelection(
        baseIndex: 1,
        baseOffset: 0,
        extentIndex: 2,
        extentOffset: 1,
      ),
    );
  });
}
