import 'package:ai_message_core/ai_message_core.dart';

import '../../cubits/editor_cubit.dart';
import '../io/filesystem.dart';
import 'workbench_editor_opener.dart';

class AiToolFileOpenResult {
  const AiToolFileOpenResult({this.resolvedPath});

  final String? resolvedPath;

  bool get isMissing => resolvedPath == null;
}

class AiToolFileOpenCoordinator {
  AiToolFileOpenCoordinator({
    required WorkbenchEditorOpener opener,
    required EditorCubit editor,
  }) : _opener = opener,
       _editor = editor;

  final WorkbenchEditorOpener _opener;
  final EditorCubit _editor;

  Future<AiToolFileOpenResult> openToolFile({
    required String workspaceId,
    required AiToolFileTarget target,
    required String? sessionWorkingDirectory,
    required List<String> workspaceFolderPaths,
    required Filesystem fs,
  }) async {
    final resolved = await _resolvePath(
      target: target,
      sessionWorkingDirectory: sessionWorkingDirectory,
      workspaceFolderPaths: workspaceFolderPaths,
      fs: fs,
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

  Future<String?> _resolvePath({
    required AiToolFileTarget target,
    required String? sessionWorkingDirectory,
    required List<String> workspaceFolderPaths,
    required Filesystem fs,
  }) async {
    final pathContext = fs.pathContext;
    final rawPath = target.path.trim();
    if (rawPath.isEmpty) return null;

    if (pathContext.isAbsolute(rawPath)) {
      final normalized = pathContext.normalize(rawPath);
      final stat = await fs.stat(normalized);
      return stat.isFile ? normalized : null;
    }

    final candidates = <String>[];
    final cwd = sessionWorkingDirectory?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      candidates.add(pathContext.join(cwd, rawPath));
    }
    for (final folder in workspaceFolderPaths) {
      final trimmed = folder.trim();
      if (trimmed.isEmpty) continue;
      candidates.add(pathContext.join(trimmed, rawPath));
    }

    for (final candidate in candidates) {
      final normalized = pathContext.normalize(candidate);
      final stat = await fs.stat(normalized);
      if (stat.isFile) return normalized;
    }
    return null;
  }
}
