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
import '../editor/svg_view_mode_store.dart';
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
    SvgViewModeStore? svgViewModes,
    required MarkdownOpenMode Function() readMarkdownOpenMode,
    bool Function()? readFilePreviewInFloating,
    bool Function()? readFloatingPreviewTabs,
    ChatCubit? chat,
  }) : _editor = editor,
       _workbench = workbench,
       _floating = floating,
       _readMarkdownOpenMode = readMarkdownOpenMode,
       _readFilePreviewInFloating =
           readFilePreviewInFloating ?? (() => true),
       _readFloatingPreviewTabs =
           readFloatingPreviewTabs ?? (() => true),
       _chat = chat,
       htmlViewModes = htmlViewModes ?? HtmlViewModeStore(),
       svgViewModes = svgViewModes ?? SvgViewModeStore();

  final EditorCubit _editor;
  final WorkbenchCubit _workbench;
  final FloatingWorkspaceCubit _floating;
  final ChatCubit? _chat;
  final MarkdownViewModeStore markdownViewModes;
  final HtmlViewModeStore htmlViewModes;
  final SvgViewModeStore svgViewModes;
  final MarkdownOpenMode Function() _readMarkdownOpenMode;
  final bool Function() _readFilePreviewInFloating;
  final bool Function() _readFloatingPreviewTabs;

  /// Opens [tab] on the floating strip through the preview slot when
  /// enabled. A dirty preview-slot tab is promoted (kept) instead of
  /// replaced, so unsaved content is never dropped by a new preview.
  void _openFloatingPreviewTab(String workspaceId, WorkbenchTabId tab) {
    _floating.ensureOpen();
    _floating.setActiveWorkspace(workspaceId);
    if (!_readFloatingPreviewTabs()) {
      _workbench.openFloating(workspaceId, tab, activate: true);
      return;
    }
    _promoteDirtyFloatingPreview(workspaceId);
    final replaced = _workbench.openFloating(
      workspaceId,
      tab,
      preview: true,
      activate: true,
    );
    _closeReplaced(workspaceId, replaced);
  }

  /// Promotes the current floating preview tab when its file is dirty, so
  /// the reducer never replaces a tab with unsaved content.
  void _promoteDirtyFloatingPreview(String workspaceId) {
    final strip = _workbench.mergedFloatingStrip(workspaceId);
    for (final id in strip.previewIds) {
      final path = id.filePath;
      if (path != null && _editor.state.bucket(workspaceId).isDirty(path)) {
        _workbench.promote(workspaceId, id);
      }
    }
  }

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
      _openFloatingPreviewTab(workspaceId, WorkbenchTabId.file(normalized));
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
      _openFloatingPreviewTab(workspaceId, tab);
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

  /// Opens a git-compare file diff tab (left/right sides from [identity]).
  Future<void> openCompareDiff({
    required String workspaceId,
    required CompareDiffIdentity identity,
    required Future<String?> Function({bool ignoreWhitespace, bool fullContext})
    loadDiff,
    String? title,
    bool preview = true,
  }) async {
    final path = identity.absolutePath.trim();
    if (path.isEmpty) return;
    final diffText =
        await loadDiff(ignoreWhitespace: false, fullContext: true) ?? '';
    openDiff(
      workspaceId: workspaceId,
      identity: identity,
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
