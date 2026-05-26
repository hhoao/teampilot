import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/context_menu_position.dart';
import 'file_editor_ai_context.dart';

/// Desktop/mobile context menu for [CodeEditor] (right-click / long-press).
class FileEditorContextMenuController implements SelectionToolbarController {
  const FileEditorContextMenuController();

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final l10n = context.l10n;
    final editorCubit = context.read<EditorCubit>();
    final path = editorCubit.state.activePath;
    final readOnly = path != null && editorCubit.isReadOnly(path);

    final position = contextMenuPositionForGlobal(
      context,
      anchors.primaryAnchor,
    );

    final items = <PopupMenuEntry<void>>[
      if (!readOnly)
        PopupMenuItem(
          onTap: () => controller.cut(),
          child: Text(l10n.editorCut),
        ),
      PopupMenuItem(
        onTap: () => controller.copy(),
        child: Text(l10n.editorCopy),
      ),
      if (path != null)
        PopupMenuItem(
          onTap: () {
            Clipboard.setData(
              ClipboardData(
                text: formatEditorAiContext(
                  filePath: path,
                  controller: controller,
                ),
              ),
            );
          },
          child: Text(l10n.editorCopyAsAiContext),
        ),
      if (!readOnly)
        PopupMenuItem(
          onTap: () => controller.paste(),
          child: Text(l10n.editorPaste),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: controller.selectAll,
        child: Text(l10n.editorSelectAll),
      ),
      if (!readOnly && controller.canUndo)
        PopupMenuItem(
          onTap: controller.undo,
          child: Text(l10n.editorUndoEdit),
        ),
      if (!readOnly && controller.canRedo)
        PopupMenuItem(
          onTap: controller.redo,
          child: Text(l10n.editorRedoEdit),
        ),
    ];

    showMenu<void>(
      context: context,
      position: position,
      items: items,
      useRootNavigator: true,
    );
  }
}
