import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Unsaved-change prompts and batch close helpers for editor tabs.
abstract final class FileEditorTabClose {
  FileEditorTabClose._();

  static Future<void> closeAt(BuildContext context, int index) async {
    if (!await _confirmCloseIfDirty(context, index)) return;
    if (!context.mounted) return;
    context.read<EditorCubit>().closeFile(index, force: true);
  }

  static Future<void> closeOthers(BuildContext context, int anchorIndex) async {
    final editor = context.read<EditorCubit>();
    final indices = <int>[
      for (var i = editor.state.openPaths.length - 1; i >= 0; i--)
        if (i != anchorIndex) i,
    ];
    await _closeIndices(context, indices);
  }

  static Future<void> closeRight(BuildContext context, int anchorIndex) async {
    final editor = context.read<EditorCubit>();
    final indices = <int>[
      for (var i = editor.state.openPaths.length - 1; i > anchorIndex; i--) i,
    ];
    await _closeIndices(context, indices);
  }

  static Future<void> _closeIndices(
    BuildContext context,
    List<int> indices,
  ) async {
    for (final index in indices) {
      if (!context.mounted) return;
      if (!await _confirmCloseIfDirty(context, index)) return;
      if (!context.mounted) return;
      context.read<EditorCubit>().closeFile(index, force: true);
    }
  }

  static Future<bool> _confirmCloseIfDirty(
    BuildContext context,
    int index,
  ) async {
    final editor = context.read<EditorCubit>();
    if (index < 0 || index >= editor.state.openPaths.length) return true;
    final path = editor.state.openPaths[index];
    if (!editor.state.isDirty(path)) return true;

    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editorUnsavedChangesTitle),
        content: Text(
          l10n.editorUnsavedChangesDiscardFile(editor.state.fileNameFor(path)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.editorDiscard),
          ),
        ],
      ),
    );
    return discard == true;
  }
}
