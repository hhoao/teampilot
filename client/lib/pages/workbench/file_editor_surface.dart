import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor/file_editor_toolbar.dart';
import '../../services/editor/markdown_preview_link_handler.dart';
import '../../services/editor/markdown_view_mode_store.dart';
import '../../services/editor_platform/document_session.dart';
import '../../services/editor_platform/editor_viewport_token_binder.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';
import '../../widgets/workbench/markdown_view_mode_toggle.dart';

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
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (prev, next) {
        final wasDirty = prev.bucket(workspaceId).isDirty(path);
        final isDirty = next.bucket(workspaceId).isDirty(path);
        return !wasDirty && isDirty;
      },
      listener: (context, state) {
        context.read<WorkbenchCubit>().pinTab(
          workspaceId,
          WorkbenchTabId.file(path),
        );
      },
      child: ColoredBox(
        color: cs.workspaceCard,
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
    );
  }
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
    final opener = context.read<WorkbenchEditorOpener>();
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dirty ? '$name •' : name,
                style: AppTextStyles.of(
                  context,
                ).mdSemibold,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!readOnly) ...[
              IconButton(
                tooltip: context.l10n.editorSave,
                icon: const Icon(Icons.save_outlined, size: 18),
                onPressed: () => unawaited(
                  context.read<EditorCubit>().saveFile(workspaceId, path),
                ),
              ),
              IconButton(
                tooltip: context.l10n.editorRevertChanges,
                icon: const Icon(Icons.undo, size: 18),
                onPressed: dirty
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
          return _MarkdownPreviewPane(
            workspaceId: workspaceId,
            path: path,
            controller: controller,
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

class _CodeEditorPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final editor = context.read<EditorCubit>();
    return CodeEditor(
      key: editor.editorKeyFor(workspaceId, path) ?? ValueKey(path),
      controller: controller,
      readOnly: readOnly,
      toolbarController: const FileEditorContextMenuController(),
      style: codeEditorStyleFor(
        context,
        path,
        tokenProvider: editor.tokenProviderFor(workspaceId, path),
      ),
      wordWrap: false,
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return _LineNumberWithViewportBinder(
              controller: editingController,
              notifier: notifier,
              session: editor.documentSessionFor(workspaceId, path),
            );
          },
    );
  }
}

class _MarkdownPreviewPane extends StatelessWidget {
  const _MarkdownPreviewPane({
    required this.workspaceId,
    required this.path,
    required this.controller,
  });

  final String workspaceId;
  final String path;
  final CodeLineEditingController controller;

  @override
  Widget build(BuildContext context) {
    final opener = context.read<WorkbenchEditorOpener>();
    final roots = WorkspaceToolsScope.maybeOf(context)?.roots ?? const [];
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: MarkdownBody(
              data: controller.text,
              styleSheet: buildAppMarkdownStyleSheet(Theme.of(context)),
              selectable: false,
              onTapLink: (text, href, title) {
                unawaited(
                  handleMarkdownPreviewLink(
                    href: href,
                    markdownFilePath: path,
                    workspaceId: workspaceId,
                    workspaceRoots: roots,
                    opener: opener,
                  ),
                );
              },
            ),
          ),
        );
      },
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
