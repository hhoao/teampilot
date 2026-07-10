import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../editor/file_editor_theme.dart';
import '../io/filesystem.dart';

/// Single entry for opening file/diff center tabs (editor bucket + workbench).
class WorkbenchEditorOpener {
  WorkbenchEditorOpener({
    required EditorCubit editor,
    required WorkbenchCubit workbench,
    ChatCubit? chat,
  }) : _editor = editor,
       _workbench = workbench,
       _chat = chat;

  final EditorCubit _editor;
  final WorkbenchCubit _workbench;
  final ChatCubit? _chat;

  Future<void> openFile(
    String workspaceId,
    String path, {
    Filesystem? fs,
    bool preview = true,
  }) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    // Activate the tab immediately so preview is not gated on disk IO.
    if (!isEditorOpenableFilePath(normalized)) {
      await _editor.openFile(workspaceId, normalized, fs: fs);
      return;
    }
    final tab = WorkbenchTabId.file(normalized);
    final replaced = _workbench.ensureTab(
      workspaceId,
      tab,
      preview: preview,
    );
    _closeReplaced(workspaceId, replaced);
    _chat?.dismissCompose();
    await _editor.openFile(workspaceId, normalized, fs: fs);
  }

  void openDiff({
    required String workspaceId,
    required String absolutePath,
    required bool staged,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
    bool preview = true,
  }) {
    _editor.openDiff(
      workspaceId: workspaceId,
      absolutePath: absolutePath,
      staged: staged,
      title: title,
      diffText: diffText,
      reloadDiff: reloadDiff,
    );
    final tab = WorkbenchTabId.diff(absolutePath, staged: staged);
    final replaced = _workbench.ensureTab(
      workspaceId,
      tab,
      preview: preview,
    );
    _closeReplaced(workspaceId, replaced);
    _chat?.dismissCompose();
  }

  void _closeReplaced(String workspaceId, WorkbenchTabId? replaced) {
    if (replaced == null) return;
    switch (replaced.kind) {
      case WorkbenchTabKind.session:
        break;
      case WorkbenchTabKind.file:
        _editor.closeFile(workspaceId, replaced.id, force: true);
      case WorkbenchTabKind.diff:
        _editor.closeDiff(workspaceId, replaced.id);
    }
  }
}
