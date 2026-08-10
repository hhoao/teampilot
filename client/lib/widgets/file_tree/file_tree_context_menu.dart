import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../app_toast/app_toast.dart';

import '../../cubits/file_tree_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/io/file_path_actions.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/debounce/debounce.dart';
/// Right-click menu for a file-tree row.
abstract final class FileTreeContextMenu {
  static Future<void> show({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required FileTreeCubit cubit,
    required String targetPath,
    required String targetName,
    required bool isDirectory,
    required bool desktopShellActions,
    required String workspaceId,
    String? workspaceRoot,
    bool remoteFileManagerActions = false,
    required RuntimeContext workContext,
  }) async {
    final l10n = context.l10n;
    final ctx = cubit.fs.pathContext;
    final parentDir = isDirectory ? targetPath : ctx.dirname(targetPath);
    final canPaste = cubit.state.clipboard != null;
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: 'new_file',
        icon: Icons.note_add_outlined,
        label: l10n.fileTreeNewFile,
      ),
      TpActionMenuSpec.item(
        value: 'new_folder',
        icon: Icons.create_new_folder_outlined,
        label: l10n.fileTreeNewFolder,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'cut',
        icon: Icons.content_cut,
        label: l10n.fileTreeCut,
      ),
      TpActionMenuSpec.item(
        value: 'copy',
        icon: Icons.content_copy,
        label: l10n.fileTreeCopy,
      ),
      TpActionMenuSpec.item(
        value: 'paste',
        icon: Icons.content_paste,
        label: l10n.fileTreePaste,
        enabled: canPaste,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'rename',
        icon: Icons.drive_file_rename_outline,
        label: l10n.fileTreeRename,
      ),
      TpActionMenuSpec.item(
        value: 'delete',
        icon: Icons.delete_outline,
        label: l10n.fileTreeDeleteItemTitle,
        destructive: true,
      ),
      const TpActionMenuSpec.divider(),
      if (!isDirectory && desktopShellActions)
        TpActionMenuSpec.item(
          value: 'external',
          icon: Icons.open_in_new,
          label: l10n.fileTreeOpenWithSystemApp,
        ),
      TpActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.fileTreeCopyPath,
      ),
      TpActionMenuSpec.item(
        value: 'copy_relative_path',
        icon: Icons.copy_outlined,
        label: l10n.fileTreeCopyRelativePath,
        enabled:
            tryRelativeWorkspacePath(
              absolutePath: targetPath,
              workspaceRoot: workspaceRoot,
              pathContext: ctx,
            ) !=
            null,
      ),
      if (desktopShellActions) ...[
        TpActionMenuSpec.item(
          value: 'file_manager',
          icon: Icons.folder_open_outlined,
          label: l10n.fileTreeOpenInFileManager,
        ),
        TpActionMenuSpec.item(
          value: 'terminal',
          icon: Icons.terminal,
          label: l10n.fileTreeOpenInTerminal,
        ),
      ] else if (remoteFileManagerActions)
        TpActionMenuSpec.item(
          value: 'file_manager',
          icon: Icons.folder_open_outlined,
          label: l10n.fileTreeOpenInFileManager,
        ),
    ];

    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;

    switch (value) {
      case 'new_file':
        await _promptCreate(
          context,
          cubit: cubit,
          parentDir: parentDir,
          isFolder: false,
          workspaceId: workspaceId,
        );
      case 'new_folder':
        await _promptCreate(
          context,
          cubit: cubit,
          parentDir: parentDir,
          isFolder: true,
          workspaceId: workspaceId,
        );
      case 'cut':
        cubit.cutItem(targetPath);
      case 'copy':
        cubit.copyItem(targetPath);
      case 'paste':
        await _runOp(
          context,
          () => cubit.pasteInto(parentDir),
          success: l10n.fileTreePasteDone,
        );
      case 'rename':
        await _promptRename(
          context,
          cubit: cubit,
          path: targetPath,
          currentName: targetName,
        );
      case 'delete':
        await _confirmDelete(
          context,
          cubit: cubit,
          targetPath: targetPath,
          targetName: targetName,
        );
      case 'external':
        if (!isDirectory) FilePathActions.openWithSystemApp(targetPath);
      case 'copy_path':
        await FilePathActions.copyAbsolutePath(targetPath);
      case 'copy_relative_path':
        await FilePathActions.copyRelativePath(
          absolutePath: targetPath,
          workspaceRoot: workspaceRoot,
          pathContext: cubit.fs.pathContext,
        );
      case 'file_manager':
        await FilePathActions.revealInFileManager(
          targetPath: targetPath,
          isDirectory: isDirectory,
          remoteFileManagerActions: remoteFileManagerActions,
          workContext: workContext,
        );
      case 'terminal':
        final ok = await FilePathActions.openInTerminal(
          targetPath: targetPath,
          isDirectory: isDirectory,
        );
        if (!context.mounted) return;
        if (!ok) {
          AppToast.show(
            context,
            message: l10n.fileTreeOpenInTerminalFailed,
            variant: TpToastVariant.error,
          );
        }
    }
  }

  static Future<void> _promptCreate(
    BuildContext context, {
    required FileTreeCubit cubit,
    required String parentDir,
    required bool isFolder,
    required String workspaceId,
  }) async {
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: isFolder ? l10n.fileTreeNewFolder : l10n.fileTreeNewFile,
      hintText: l10n.fileTreeCreateNameHint,
      confirmLabel: l10n.create,
    );
    if (!context.mounted || name == null || name.trim().isEmpty) return;

    await _runOp(
      context,
      () => isFolder
          ? cubit.createFolder(parentDir, name)
          : cubit.createFile(parentDir, name),
      success: isFolder ? l10n.fileTreeFolderCreated : l10n.fileTreeFileCreated,
      onSuccess: isFolder
          ? null
          : () {
              final created = cubit.fs.pathContext.join(parentDir, name.trim());
              if (isWorkbenchOpenableFilePath(created)) {
                unawaited(
                  context.read<WorkbenchEditorOpener>().openFile(
                    workspaceId,
                    created,
                    fs: cubit.fs,
                    preview: false,
                  ),
                );
              }
            },
    );
  }

  static Future<void> _promptRename(
    BuildContext context, {
    required FileTreeCubit cubit,
    required String path,
    required String currentName,
  }) async {
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.fileTreeRenameTitle,
      initialText: currentName,
      hintText: l10n.fileTreeCreateNameHint,
      confirmLabel: l10n.fileTreeRename,
    );
    if (!context.mounted || name == null || name.trim().isEmpty) return;

    await _runOp(
      context,
      () => cubit.renameItem(path, name),
      success: l10n.fileTreeRenameDone,
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context, {
    required FileTreeCubit cubit,
    required String targetPath,
    required String targetName,
  }) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.fileTreeDeleteItemTitle),
            const SizedBox(height: 16),
            Text(l10n.fileTreeDeleteItemConfirm(targetName)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: throttledOnPressed('file_tree_delete', () {
                    Navigator.pop(ctx, true);
                  }),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _runOp(
      context,
      () => cubit.deletePath(targetPath),
      success: l10n.fileTreeDeleteDone,
    );
  }

  static Future<void> _runOp(
    BuildContext context,
    Future<void> Function() action, {
    required String success,
    VoidCallback? onSuccess,
  }) async {
    try {
      await action();
      if (!context.mounted) return;
      onSuccess?.call();
      AppToast.show(
        context,
        message: success,
        variant: TpToastVariant.success,
      );
    } on FileTreeOperationException catch (e) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: _mapError(context, e.message),
        variant: TpToastVariant.error,
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: e.toString(),
        variant: TpToastVariant.error,
      );
    }
  }

  static String _mapError(BuildContext context, String key) {
    final l10n = context.l10n;
    return switch (key) {
      'invalid name' => l10n.fileTreeInvalidName,
      'target already exists' => l10n.fileTreeItemExists,
      'source missing' => l10n.fileTreeSourceMissing,
      'invalid paste target' => l10n.fileTreeInvalidPasteTarget,
      _ => key,
    };
  }

}
