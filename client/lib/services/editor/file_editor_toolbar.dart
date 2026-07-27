import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../selection_ai/selection_ai_menu_specs.dart';
import '../selection_ai/selection_ask_ai.dart';
import 'file_editor_ai_context.dart';

/// Desktop/mobile context menu for [CodeEditor] (right-click / long-press).
class FileEditorContextMenuController implements SelectionToolbarController {
  const FileEditorContextMenuController({required this.onMenuOpenChanged});

  final ValueChanged<bool> onMenuOpenChanged;

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
    final workbench = context.read<WorkbenchCubit>();
    String? path;
    String? workspaceId;
    for (final entry in workbench.state.byWorkspace.entries) {
      final active = entry.value.activeTabId;
      if (active?.kind == WorkbenchTabKind.file) {
        path = active!.id;
        workspaceId = entry.key;
        break;
      }
    }
    final readOnly =
        path != null &&
        workspaceId != null &&
        editorCubit.isReadOnly(workspaceId, path);

    final specs = <TpActionMenuSpec>[
      if (!readOnly)
        TpActionMenuSpec.item(
          icon: Icons.content_cut,
          label: l10n.editorCut,
          onAction: controller.cut,
        ),
      TpActionMenuSpec.item(
        icon: Icons.content_copy,
        label: l10n.editorCopy,
        onAction: controller.copy,
      ),
      ...selectionAiMenuSpecs(
        l10n: l10n,
        enabled: path != null,
        onCopyAsAiContext: () {
          if (path != null) {
            Clipboard.setData(
              ClipboardData(
                text: formatEditorAiContext(
                  filePath: path,
                  controller: controller,
                ),
              ),
            );
          }
        },
        onAskAi: () {
          if (path == null || workspaceId == null) return;
          final workspace = context
              .read<ChatCubit>()
              .state
              .workspaces
              .firstWhere((candidate) => candidate.workspaceId == workspaceId);
          unawaited(
            SelectionAskAi.openComposeDialog(
              context,
              aiContext: formatEditorAiContext(
                filePath: path,
                controller: controller,
              ),
              workspace: workspace,
              tabScopeId: workspaceId,
            ),
          );
        },
      ),
      if (!readOnly)
        TpActionMenuSpec.item(
          icon: Icons.content_paste,
          label: l10n.editorPaste,
          onAction: controller.paste,
        ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        icon: Icons.select_all,
        label: l10n.editorSelectAll,
        onAction: controller.selectAll,
      ),
      if (!readOnly && controller.canUndo)
        TpActionMenuSpec.item(
          icon: Icons.undo,
          label: l10n.editorUndoEdit,
          onAction: controller.undo,
        ),
      if (!readOnly && controller.canRedo)
        TpActionMenuSpec.item(
          icon: Icons.redo,
          label: l10n.editorRedoEdit,
          onAction: controller.redo,
        ),
    ];

    unawaited(_showMenu(context, anchors.primaryAnchor, specs));
  }

  Future<void> _showMenu(
    BuildContext context,
    Offset globalPosition,
    List<TpActionMenuSpec> specs,
  ) async {
    onMenuOpenChanged(true);
    try {
      await showTpActionMenuFromSpecs<void>(
        context: context,
        globalPosition: globalPosition,
        specs: specs,
      );
    } finally {
      onMenuOpenChanged(false);
    }
  }
}
