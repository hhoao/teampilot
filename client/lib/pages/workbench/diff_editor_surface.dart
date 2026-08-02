import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/diff/diff_model.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/diff/diff_toolbar.dart';
import '../../widgets/diff/diff_viewer.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';

/// Center-pane git diff for one path + staged|unstaged|changes.
class DiffEditorSurface extends StatefulWidget {
  const DiffEditorSurface({
    required this.workspaceId,
    required this.diffKey,
    super.key,
  });

  final String workspaceId;
  final String diffKey;

  @override
  State<DiffEditorSurface> createState() => _DiffEditorSurfaceState();
}

class _DiffEditorSurfaceState extends State<DiffEditorSurface> {
  String? _boundDiffText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWritableBind());
  }

  @override
  void didUpdateWidget(DiffEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diffKey != widget.diffKey ||
        oldWidget.workspaceId != widget.workspaceId) {
      _boundDiffText = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncWritableBind());
    }
  }

  Future<void> _syncWritableBind() async {
    if (!mounted) return;
    final editor = context.read<EditorCubit>();
    final tab = editor.state.bucket(widget.workspaceId).openDiffs[widget.diffKey];
    if (tab == null || tab.source != WorkbenchDiffSource.unstaged) return;

    final diskText = await editor.readWorkingTreeText(tab.absolutePath);
    if (!mounted) return;

    await editor.bindWritableDiff(
      workspaceId: widget.workspaceId,
      diffKey: widget.diffKey,
      absolutePath: tab.absolutePath,
      lastLoadedCanonical: diskText,
      onWorkingTreeWritten: editor.onWorkingTreeWrittenFor(widget.diffKey),
    );
    if (!mounted) return;
    setState(() => _boundDiffText = tab.diffText);
  }

  void _scheduleWritableBindIfNeeded(DiffTabState tab) {
    if (tab.source != WorkbenchDiffSource.unstaged) return;
    if (tab.diffText == _boundDiffText) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWritableBind());
  }

  Future<void> _applyHunk(DiffResult result, DiffBlock block) async {
    final editor = context.read<EditorCubit>();
    var discardDirty = false;
    if (editor.isDiffDirty(widget.diffKey)) {
      final confirmed = await _confirmDiscardDiffEdits(context);
      if (!confirmed || !mounted) return;
      discardDirty = true;
    }
    await editor.applyDiffHunk(
      workspaceId: widget.workspaceId,
      diffKey: widget.diffKey,
      result: result,
      block: block,
      discardDirtyIfNeeded: discardDirty,
    );
  }

  void _onDiffEditorSnackbar(String? code) {
    if (code == null || !mounted) return;
    final l10n = context.l10n;
    final message = l10n.diffEditorSnackbarMessage(code);
    if (message == null) return;

    final editor = context.read<EditorCubit>();
    if (code == 'diffReloadAfterSaveFailed') {
      AppToast.show(
        context,
        message: message,
        variant: TpToastVariant.warning,
        action: TpToastAction(
          label: l10n.sessionHistoryRetry,
          onPressed: () => unawaited(
            editor.retryDiffReload(widget.workspaceId, widget.diffKey),
          ),
        ),
      );
    } else {
      AppToast.show(context, message: message);
    }
    editor.clearSnackbarMessage();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (previous, next) =>
          previous.snackbarMessage != next.snackbarMessage &&
          next.snackbarMessage != null &&
          isDiffEditorSurfaceSnackbar(next.snackbarMessage!),
      listener: (context, state) =>
          _onDiffEditorSnackbar(state.snackbarMessage),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tab = context.select<EditorCubit, DiffTabState?>(
      (c) => c.state.bucket(widget.workspaceId).openDiffs[widget.diffKey],
    );
    final cs = Theme.of(context).colorScheme;
    if (tab == null) {
      return ColoredBox(
        // Same plane as file preview / floating chrome ([ColorScheme.surface]).
        color: cs.workspaceCardChrome(WorkspacePageChrome.workspace),
        child: Center(child: Text(context.l10n.diffNoChanges)),
      );
    }

    _scheduleWritableBindIfNeeded(tab);

    final stagedLabel = tab.source == WorkbenchDiffSource.staged
        ? ' (staged)'
        : '';
    final reload = context.read<EditorCubit>().diffReloadFor(widget.diffKey);
    final isWritable = tab.source == WorkbenchDiffSource.unstaged;
    final canonicalText = context.select<EditorCubit, String?>(
      (c) => c.diffCanonicalFor(widget.diffKey),
    );
    final isDirty = context.select<EditorCubit, bool>(
      (c) => c.isDiffDirty(widget.diffKey),
    );

    return ColoredBox(
      color: cs.workspaceCardChrome(WorkspacePageChrome.workspace),
      child: DiffViewer.fromUnifiedDiff(
        key: ValueKey(Object.hash(widget.diffKey, tab.diffText, tab.title)),
        title: '${tab.title}$stagedLabel',
        diffText: tab.diffText,
        filePath: tab.absolutePath,
        initialMode: isWritable ? DiffViewMode.sideBySide : DiffViewMode.unified,
        writable: isWritable,
        canonicalText: canonicalText ?? '',
        isDirty: isWritable && isDirty,
        onSave: isWritable
            ? () => unawaited(
                context.read<EditorCubit>().saveDiffWorkingTree(
                  widget.workspaceId,
                  widget.diffKey,
                ),
              )
            : null,
        onCanonicalChanged: isWritable
            ? (text) => context.read<EditorCubit>().updateDiffCanonical(
                widget.diffKey,
                text,
              )
            : null,
        onApplyHunk: isWritable ? _applyHunk : null,
        reloadDiff: reload == null
            ? null
            : (ignoreWhitespace, fullContext) async {
                final editor = context.read<EditorCubit>();
                final next = await reload(ignoreWhitespace, fullContext);
                if (next == null || !context.mounted) return next;
                editor.updateDiffText(widget.workspaceId, widget.diffKey, next);
                return next;
              },
        onSwitchToFile: () {
          unawaited(
            switchFileDiffSurface(
              context: context,
              workspaceId: widget.workspaceId,
              absolutePath: tab.absolutePath,
              target: FileDiffSurfaceMode.file,
            ),
          );
        },
      ),
    );
  }
}

Future<bool> _confirmDiscardDiffEdits(BuildContext context) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TpDialog(
      maxWidth: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.diffDiscardEditsApplyTitle),
          const SizedBox(height: 12),
          Text(l10n.diffDiscardEditsApplyBody),
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
