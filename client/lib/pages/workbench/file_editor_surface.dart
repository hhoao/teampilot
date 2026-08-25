import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/editor/file_editor_ai_context.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor/file_editor_toolbar.dart';
import '../../services/editor/html_view_mode_store.dart';
import '../../services/editor/markdown_preview_link_handler.dart';
import '../../services/editor/markdown_view_mode_store.dart';
import '../../services/editor_platform/document_session.dart';
import '../../services/editor_platform/editor_viewport_token_binder.dart';
import '../../services/selection_ai/selection_ask_ai.dart';
import '../../services/selection_ai/selection_ask_ai_fab_host.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/workbench/code_editor_find_panel.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';
import '../../widgets/workbench/markdown_view_mode_toggle.dart';
import '../../widgets/workbench/html_view_mode_toggle.dart';
import 'file_editor_image_preview.dart';
import 'markdown_preview_pane.dart';
import '../preview/html_preview_pane.dart';

/// Shell fill for file preview — matches floating panel / window chrome
/// ([ColorScheme.surface]) so toolbar, code, and markdown share one plane.
Color _fileEditorShellColor(ColorScheme cs) => cs.surface;

/// File-preview chrome insets — domain anchors on top of [TpWidthScale].
///
/// Only set the stops you care about (often `sm` + `xxl`); the rest lerp.
class _FileEditorInsets {
  const _FileEditorInsets({
    required this.codeMargin,
    required this.markdownPadding,
    required this.toolbarPadding,
    required this.lineNumberPadding,
    required this.gutterGap,
  });

  final EdgeInsets codeMargin;
  final EdgeInsets markdownPadding;
  final EdgeInsets toolbarPadding;
  final EdgeInsets lineNumberPadding;
  final double gutterGap;

  static const _codeMargin = TpScaledEdgeInsets(
    sm: EdgeInsets.zero,
    xxl: EdgeInsets.fromLTRB(16, 10, 16, 16),
  );

  static const _markdownPadding = TpScaledEdgeInsets(
    sm: EdgeInsets.fromLTRB(16, 12, 16, 24),
    xxl: EdgeInsets.fromLTRB(64, 48, 64, 48),
  );

  static const _toolbarPadding = TpScaledEdgeInsets(
    sm: EdgeInsets.fromLTRB(8, 2, 8, 2),
    xxl: EdgeInsets.fromLTRB(28, 8, 28, 8),
  );

  static const _lineNumberPadding = TpScaledEdgeInsets(
    sm: EdgeInsets.only(left: 6, right: 6),
    xxl: EdgeInsets.only(left: 16, right: 12),
  );

  static const _gutterGap = TpScaledDouble(sm: 10, xxl: 24);

  /// Mid-band defaults when no [TpWidthValueHost] is above.
  static final comfortable = _FileEditorInsets.forWidth(TpBreakpoints.md);

  factory _FileEditorInsets.forWidth(double width) {
    return _FileEditorInsets(
      codeMargin: _codeMargin.forWidth(width),
      markdownPadding: _markdownPadding.forWidth(width),
      toolbarPadding: _toolbarPadding.forWidth(width),
      lineNumberPadding: _lineNumberPadding.forWidth(width),
      gutterGap: _gutterGap.forWidth(width),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _FileEditorInsets &&
        codeMargin == other.codeMargin &&
        markdownPadding == other.markdownPadding &&
        toolbarPadding == other.toolbarPadding &&
        lineNumberPadding == other.lineNumberPadding &&
        gutterGap == other.gutterGap;
  }

  @override
  int get hashCode => Object.hash(
    codeMargin,
    markdownPadding,
    toolbarPadding,
    lineNumberPadding,
    gutterGap,
  );
}

/// Center-pane file editor for one path (no inner tab bar).
class FileEditorSurface extends StatelessWidget {
  const FileEditorSurface({
    required this.workspaceId,
    required this.path,
    super.key,
  });

  final String workspaceId;
  final String path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shell = _fileEditorShellColor(cs);
    if (isImagePreviewPath(path)) {
      return ColoredBox(
        color: shell,
        child: FileEditorImagePreview(workspaceId: workspaceId, path: path),
      );
    }
    // Center preview tabs pin on first edit; floating tabs are not in the
    // workbench preview set so [pin] is a no-op there.
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (prev, next) {
        final wasDirty = prev.bucket(workspaceId).isDirty(path);
        final isDirty = next.bucket(workspaceId).isDirty(path);
        return !wasDirty && isDirty;
      },
      listener: (context, state) {
        context.read<WorkbenchCubit>().pin(
          workspaceId,
          WorkbenchTabId.file(path),
        );
      },
      child: BlocListener<EditorCubit, EditorState>(
        listenWhen: (previous, next) =>
            previous.snackbarMessage != next.snackbarMessage &&
            next.snackbarMessage != null &&
            isDiffEditorSurfaceSnackbar(next.snackbarMessage!),
        listener: (context, state) =>
            _onFileEditorDiffSnackbar(context, state.snackbarMessage),
        child: ColoredBox(
          color: shell,
          child: TpWidthValueHost<_FileEditorInsets>(
            resolve: _FileEditorInsets.forWidth,
            fallback: _FileEditorInsets.comfortable,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FileEditorToolbar(workspaceId: workspaceId, path: path),
                const Divider(height: 1),
                Expanded(
                  child: _FileEditorBody(workspaceId: workspaceId, path: path),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _onFileEditorDiffSnackbar(BuildContext context, String? code) {
  if (code == null || !context.mounted) return;
  final message = context.l10n.diffEditorSnackbarMessage(code);
  if (message == null) return;
  AppToast.show(context, message: message);
  context.read<EditorCubit>().clearSnackbarMessage();
}

Future<void> _saveFileWithDiffGate(
  BuildContext context,
  String workspaceId,
  String path,
) async {
  final editor = context.read<EditorCubit>();
  if (editor.anyWritableDiffDirtyFor(workspaceId, path)) {
    final confirmed = await _confirmDiscardDiffBeforeFileSave(context);
    if (!confirmed || !context.mounted) return;
    await editor.saveFile(workspaceId, path, discardDiffDirty: true);
    return;
  }
  await editor.saveFile(workspaceId, path);
}

Future<bool> _confirmDiscardDiffBeforeFileSave(BuildContext context) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TpDialog(
      maxWidth: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.diffDiscardDiffBeforeFileSaveTitle),
          const SizedBox(height: 12),
          Text(l10n.diffDiscardDiffBeforeFileSaveBody),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.editorDiscard),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

class _FileEditorToolbar extends StatelessWidget {
  const _FileEditorToolbar({required this.workspaceId, required this.path});

  final String workspaceId;
  final String path;

  @override
  Widget build(BuildContext context) {
    final dirty = context.select<EditorCubit, bool>(
      (c) => c.state.bucket(workspaceId).isDirty(path),
    );
    final readOnly = context.select<EditorCubit, bool>(
      (c) => c.isReadOnly(workspaceId, path),
    );
    final name = p.basename(path);
    final canToggleDiff = gitCubitForAbsolutePath(context, path) != null;
    final isMarkdown = isMarkdownEditorPath(path);
    final isHtml = isHtmlPreviewPath(path);
    final opener = context.read<WorkbenchEditorOpener>();
    final insets = TpWidthValueScope.of<_FileEditorInsets>(context);
    final iconColor = Theme.of(context).colorScheme.tpIconMuted;
    // Height follows content + scaled padding; Row centers title vs actions.
    return Padding(
      padding: insets.toolbarPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              dirty ? '$name •' : name,
              style: TpTextStyles.of(context).mdSemibold,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!readOnly) ...[
            TpIconButton(
              tooltip: context.l10n.editorSave,
              icon: Icons.save_outlined,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: iconColor,
              onTap: () =>
                  unawaited(_saveFileWithDiffGate(context, workspaceId, path)),
            ),
            TpIconButton(
              tooltip: context.l10n.editorRevertChanges,
              icon: Icons.undo,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: iconColor,
              enabled: dirty,
              onTap: dirty
                  ? () => context.read<EditorCubit>().revertFile(
                      workspaceId,
                      path,
                    )
                  : null,
            ),
          ],
          if (isMarkdown) ...[
            const SizedBox(width: 4),
            ListenableBuilder(
              listenable: opener.markdownViewModes,
              builder: (context, _) {
                return MarkdownViewModeToggle(
                  mode: opener.markdownViewModes.modeFor(path),
                  onModeChanged: (mode) =>
                      opener.markdownViewModes.setMode(path, mode),
                );
              },
            ),
          ],
          if (isHtml) ...[
            const SizedBox(width: 4),
            ListenableBuilder(
              listenable: opener.htmlViewModes,
              builder: (context, _) {
                return HtmlViewModeToggle(
                  mode: opener.htmlViewModes.modeFor(path),
                  onModeChanged: (mode) =>
                      opener.htmlViewModes.setMode(path, mode),
                );
              },
            ),
          ],
          if (canToggleDiff) ...[
            const SizedBox(width: 4),
            FileDiffSurfaceToggle(
              mode: FileDiffSurfaceMode.file,
              onModeChanged: (mode) {
                if (mode == FileDiffSurfaceMode.diff) {
                  unawaited(
                    switchFileDiffSurface(
                      context: context,
                      workspaceId: workspaceId,
                      absolutePath: path,
                      target: mode,
                    ),
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FileEditorBody extends StatelessWidget {
  const _FileEditorBody({required this.workspaceId, required this.path});

  final String workspaceId;
  final String path;

  @override
  Widget build(BuildContext context) {
    final model = context.select<EditorCubit, _FileBodyModel>(
      (c) => _FileBodyModel.from(c.state.bucket(workspaceId), path),
    );
    final l10n = context.l10n;

    if (model.isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (model.loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.editorPanelErrorMessage(model.loadError!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final editor = context.read<EditorCubit>();
    final controller = editor.controllerFor(workspaceId, path);
    if (controller == null) {
      return Center(child: Text(l10n.editorNotReady));
    }

    if (isHtmlPreviewPath(path)) {
      final opener = context.read<WorkbenchEditorOpener>();
      return ListenableBuilder(
        listenable: opener.htmlViewModes,
        builder: (context, _) {
          final mode = opener.htmlViewModes.modeFor(path);
          if (mode == HtmlViewMode.preview) {
            return HtmlPreviewPane(workspaceId: workspaceId, path: path);
          }
          return _CodeEditorPane(
            workspaceId: workspaceId,
            path: path,
            controller: controller,
            readOnly: model.readOnly,
          );
        },
      );
    }

    if (!isMarkdownEditorPath(path)) {
      return _CodeEditorPane(
        workspaceId: workspaceId,
        path: path,
        controller: controller,
        readOnly: model.readOnly,
      );
    }

    final opener = context.read<WorkbenchEditorOpener>();
    return ListenableBuilder(
      listenable: opener.markdownViewModes,
      builder: (context, _) {
        final mode = opener.markdownViewModes.modeFor(path);
        if (mode == MarkdownViewMode.preview) {
          // Floating file preview is a Stack sibling of WorkspaceToolsScope —
          // resolve roots via inherited scope, registry peek, then workspace
          // folderPaths.
          final roots = markdownPreviewWorkspaceRoots(
            context,
            workspaceId: workspaceId,
          );
          return MarkdownPreviewPane(
            controller: controller,
            resolvers: MarkdownResolvers(
              onLinkTap: (href) {
                unawaited(
                  handleMarkdownPreviewLink(
                    href: href,
                    markdownFilePath: path,
                    workspaceId: workspaceId,
                    workspaceRoots: roots,
                    opener: opener,
                    fs: editor.filesystemFor(workspaceId, path),
                  ),
                );
              },
              resolveImage: (src) => resolveMarkdownPreviewImage(
                src: src,
                markdownFilePath: path,
                workspaceRoots: roots,
              ),
            ),
            codeBlockMode: context.select<LayoutCubit, ContentDisplayMode>(
              (c) => c.state.preferences.fileCodeBlockMode,
            ),
            markdownPadding: TpWidthValueScope.of<_FileEditorInsets>(
              context,
            ).markdownPadding,
            shellColor: _fileEditorShellColor(Theme.of(context).colorScheme),
          );
        }
        return _CodeEditorPane(
          workspaceId: workspaceId,
          path: path,
          controller: controller,
          readOnly: model.readOnly,
        );
      },
    );
  }
}

class _CodeEditorPane extends StatefulWidget {
  const _CodeEditorPane({
    required this.workspaceId,
    required this.path,
    required this.controller,
    required this.readOnly,
  });

  final String workspaceId;
  final String path;
  final CodeLineEditingController controller;
  final bool readOnly;

  @override
  State<_CodeEditorPane> createState() => _CodeEditorPaneState();
}

class _CodeEditorPaneState extends State<_CodeEditorPane> {
  final _menuOpen = ValueNotifier(false);

  void _setMenuOpen(bool value) {
    if (mounted) _menuOpen.value = value;
  }

  @override
  void dispose() {
    _menuOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorCubit>();
    final shell = _fileEditorShellColor(Theme.of(context).colorScheme);
    final insets = TpWidthValueScope.of<_FileEditorInsets>(context);
    final codeEditor = CodeEditor(
      key:
          editor.editorKeyFor(widget.workspaceId, widget.path) ??
          ValueKey(widget.path),
      controller: widget.controller,
      readOnly: widget.readOnly,
      // Margin wraps line numbers + field; padding is field-only (re-editor).
      margin: insets.codeMargin,
      // Gap between padded line-number column and code (like VS Code gutter).
      sperator: SizedBox(width: insets.gutterGap),
      padding: const EdgeInsets.fromLTRB(4, 5, 5, 5),
      toolbarController: FileEditorContextMenuController(
        onMenuOpenChanged: _setMenuOpen,
        workspaceId: widget.workspaceId,
        filePath: widget.path,
      ),
      // Find/replace (Ctrl+F / Ctrl+Alt+F): re-editor enables its find
      // shortcuts and shows the find bar only when a builder is supplied.
      findBuilder: (context, controller, readOnly) =>
          CodeEditorFindPanel(controller: controller, readOnly: readOnly),
      style: codeEditorStyleFor(
        context,
        widget.path,
        backgroundColor: shell,
        tokenProvider: editor.tokenProviderFor(widget.workspaceId, widget.path),
      ),
      wordWrap: false,
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return Padding(
              padding: insets.lineNumberPadding,
              child: _LineNumberWithViewportBinder(
                controller: editingController,
                notifier: notifier,
                session: editor.documentSessionFor(
                  widget.workspaceId,
                  widget.path,
                ),
              ),
            );
          },
    );
    return ShortcutFocus(
      // The code editor owns Mod+F (re-editor find); document the claim so any
      // future global command binding Mod+F is suppressed here.
      claims: {
        KeyChord(key: 'f', mods: [KeyChordMod.mod]),
      },
      child: ListenableBuilder(
        listenable: _menuOpen,
        child: codeEditor,
        builder: (context, child) {
          return SelectionAskAiFabHost(
            listenable: widget.controller,
            selectionActive: () => !widget.controller.selection.isCollapsed,
            readAiContext: () => formatEditorAiContext(
              filePath: widget.path,
              controller: widget.controller,
            ),
            onAskAi: (aiContext) async {
              final workspace = context
                  .read<ChatCubit>()
                  .state
                  .workspaces
                  .firstWhereOrNull(
                    (candidate) => candidate.workspaceId == widget.workspaceId,
                  );
              if (workspace == null) return;
              await SelectionAskAi.openComposeDialog(
                context,
                aiContext: aiContext,
                workspace: workspace,
                tabScopeId: widget.workspaceId,
              );
            },
            menuOpen: _menuOpen.value,
            child: child!,
          );
        },
      ),
    );
  }
}

/// Renders the gutter line numbers and, when the file has a tree-sitter
/// [DocumentSession], keeps its viewport token requests in sync with the
/// visible line band published by re-editor's indicator notifier.
class _LineNumberWithViewportBinder extends StatefulWidget {
  const _LineNumberWithViewportBinder({
    required this.controller,
    required this.notifier,
    required this.session,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final DocumentSession? session;

  @override
  State<_LineNumberWithViewportBinder> createState() =>
      _LineNumberWithViewportBinderState();
}

class _LineNumberWithViewportBinderState
    extends State<_LineNumberWithViewportBinder> {
  EditorViewportTokenBinder? _binder;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_LineNumberWithViewportBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.notifier != widget.notifier) {
      _bind();
    }
  }

  void _bind() {
    _binder?.dispose();
    final session = widget.session;
    _binder = session == null
        ? null
        : EditorViewportTokenBinder(
            session: session,
            notifier: widget.notifier,
          );
  }

  @override
  void dispose() {
    _binder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultCodeLineNumber(
      controller: widget.controller,
      notifier: widget.notifier,
    );
  }
}

class _FileBodyModel {
  const _FileBodyModel({
    required this.isLoading,
    required this.readOnly,
    this.loadError,
  });

  factory _FileBodyModel.from(WorkspaceEditorBucket bucket, String path) {
    return _FileBodyModel(
      isLoading: bucket.loadingPaths.contains(path),
      readOnly: bucket.readOnlyPaths.contains(path),
      loadError: bucket.errorByPath[path],
    );
  }

  final bool isLoading;
  final bool readOnly;
  final String? loadError;
}
