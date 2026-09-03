import 'package:path/path.dart' as p;

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/diff_identity.dart';
import '../../models/layout_preferences.dart';
import '../editor/file_editor_theme.dart';
import '../editor/html_view_mode_store.dart';
import '../editor/markdown_view_mode_store.dart';
import '../io/filesystem.dart';

/// Single entry for opening file/diff tabs (editor bucket + host strip).
///
/// File and diff opens go to the floating surfaces when
/// [readFilePreviewInFloating] is true; otherwise they use the center strip.
class WorkbenchEditorOpener {
  WorkbenchEditorOpener({
    required EditorCubit editor,
    required WorkbenchCubit workbench,
    required FloatingWorkspaceCubit floating,
    required this.markdownViewModes,
    HtmlViewModeStore? htmlViewModes,
    required MarkdownOpenMode Function() readMarkdownOpenMode,
    bool Function()? readFilePreviewInFloating,
    ChatCubit? chat,
  }) : _editor = editor,
       _workbench = workbench,
       _floating = floating,
       _readMarkdownOpenMode = readMarkdownOpenMode,
       _readFilePreviewInFloating =
           readFilePreviewInFloating ?? (() => true),
       _chat = chat,
       htmlViewModes = htmlViewModes ?? HtmlViewModeStore();

  final EditorCubit _editor;
  final WorkbenchCubit _workbench;
  final FloatingWorkspaceCubit _floating;
  final ChatCubit? _chat;
  final MarkdownViewModeStore markdownViewModes;
  final HtmlViewModeStore htmlViewModes;
  final MarkdownOpenMode Function() _readMarkdownOpenMode;
  final bool Function() _readFilePreviewInFloating;

  Future<void> openFile(
    String workspaceId,
    String path, {
    Filesystem? fs,
    bool preview = true,
  }) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    // Activate the tab immediately so preview is not gated on disk IO.
    if (!isWorkbenchOpenableFilePath(normalized)) {
      await _editor.openFile(workspaceId, normalized, fs: fs);
      return;
    }
    if (isMarkdownEditorPath(normalized)) {
      markdownViewModes.seedOnOpen(normalized, _readMarkdownOpenMode());
    }

    if (_readFilePreviewInFloating()) {
      _floating.ensureOpen();
      _floating.setActiveWorkspace(workspaceId);
      _workbench.openFloating(
        workspaceId,
        WorkbenchTabId.file(normalized),
        activate: true,
      );
      await _editor.openFile(workspaceId, normalized, fs: fs);
      return;
    }

    final tab = WorkbenchTabId.file(normalized);
    final replaced = _workbench.openFile(workspaceId, tab.id, preview: preview);
    _closeReplaced(workspaceId, replaced);
    await _editor.openFile(workspaceId, normalized, fs: fs);
  }

  void openDiff({
    required String workspaceId,
    required DiffIdentity identity,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
    Future<void> Function()? onWorkingTreeWritten,
    bool preview = true,
  }) {
    _editor.openDiff(
      workspaceId: workspaceId,
      identity: identity,
      title: title,
      diffText: diffText,
      reloadDiff: reloadDiff,
      onWorkingTreeWritten: onWorkingTreeWritten,
    );
    final tab = WorkbenchTabId.diff(identity);
    if (_readFilePreviewInFloating()) {
      _floating.ensureOpen();
      _floating.setActiveWorkspace(workspaceId);
      _workbench.openFloating(workspaceId, tab, activate: true);
      return;
    }
    final replaced = _workbench.openDiff(workspaceId, tab, preview: preview);
    _closeReplaced(workspaceId, replaced);
  }

  /// Opens a floating rendered html preview tab (no editor bucket entry).
  void openHtmlPreview(String workspaceId, String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    _floating.ensureOpen();
    _floating.setActiveWorkspace(workspaceId);
    _workbench.openFloating(
      workspaceId,
      WorkbenchTabId.htmlPreview(normalized),
      activate: true,
    );
  }

  /// Opens HEAD-vs-working-tree diff for [absolutePath] (File↔Diff toggle).
  Future<void> openChangesDiff({
    required String workspaceId,
    required String absolutePath,
    required Future<String?> Function({bool ignoreWhitespace, bool fullContext})
    loadDiff,
    String? title,
    bool preview = true,
  }) async {
    final path = absolutePath.trim();
    if (path.isEmpty) return;
    final diffText =
        await loadDiff(ignoreWhitespace: false, fullContext: true) ?? '';
    if (diffText.isEmpty && preview) {
      // Still open so the user can see the empty "no changes" state.
    }
    openDiff(
      workspaceId: workspaceId,
      identity: ScmDiffIdentity(path, ScmDiffMode.changes),
      title: title ?? p.basename(path),
      diffText: diffText,
      reloadDiff: (ignoreWhitespace, fullContext) => loadDiff(
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      ),
      preview: preview,
    );
  }

  void _closeReplaced(String workspaceId, WorkbenchTabId? replaced) {
    if (replaced == null) return;
    switch (replaced.kind) {
      case WorkbenchTabKind.session:
        _chat?.closeSessionTab(replaced.id);
      case WorkbenchTabKind.file:
        _editor.closeFile(workspaceId, replaced.id, force: true);
      case WorkbenchTabKind.diff:
        _editor.closeDiff(workspaceId, replaced.id);
      case WorkbenchTabKind.shell:
      case WorkbenchTabKind.run:
      case WorkbenchTabKind.htmlPreview:
      case WorkbenchTabKind.gitGraph:
      case WorkbenchTabKind.gitCompare:
        break;
    }
  }
}
