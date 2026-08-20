import 'package:ai_message_core/ai_message_core.dart';

import '../../cubits/editor_cubit.dart';
import '../io/filesystem.dart';
import 'workbench_editor_opener.dart';
import 'workspace_file_locator.dart';

class AiToolFileOpenResult {
  const AiToolFileOpenResult({this.resolvedPath});

  final String? resolvedPath;

  bool get isMissing => resolvedPath == null;
}

class AiToolFileOpenCoordinator {
  AiToolFileOpenCoordinator({
    required WorkbenchEditorOpener opener,
    required EditorCubit editor,
    WorkspaceFileLocator locator = const WorkspaceFileLocator(),
  }) : _opener = opener,
       _editor = editor,
       _locator = locator;

  final WorkbenchEditorOpener _opener;
  final EditorCubit _editor;
  final WorkspaceFileLocator _locator;

  Future<AiToolFileOpenResult> openToolFile({
    required String workspaceId,
    required AiToolFileTarget target,
    required String? sessionWorkingDirectory,
    required List<String> workspaceFolderPaths,
    required Filesystem fs,
  }) async {
    final searchBases = <String>[
      if (sessionWorkingDirectory != null &&
          sessionWorkingDirectory.trim().isNotEmpty)
        sessionWorkingDirectory.trim(),
      ...workspaceFolderPaths,
    ];
    final resolved = await _locator.locate(
      rawPath: target.path,
      fs: fs,
      searchBases: searchBases,
    );
    if (resolved == null) {
      return const AiToolFileOpenResult();
    }

    await _opener.openFile(workspaceId, resolved, fs: fs);
    if (target.startLine != null) {
      _editor.selectLines(
        workspaceId,
        resolved,
        startLine: target.startLine!,
        endLine: target.endLine,
      );
    }
    return AiToolFileOpenResult(resolvedPath: resolved);
  }
}
