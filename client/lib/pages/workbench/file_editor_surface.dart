import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor/file_editor_toolbar.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

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
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dirty ? '$name •' : name,
                style: AppTextStyles.of(context).body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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

    return CodeEditor(
      key: editor.editorKeyFor(workspaceId, path) ?? ValueKey(path),
      controller: controller,
      readOnly: model.readOnly,
      toolbarController: const FileEditorContextMenuController(),
      style: codeEditorStyleFor(context, path),
      wordWrap: false,
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
        );
      },
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
