import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/io/system_folder_opener.dart';
import '../../services/io/system_terminal_opener.dart';
import '../../utils/debounce/debounce.dart';
import '../app_dialog.dart';
import '../menu/sidebar_action_menu.dart';

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
  }) async {
    final l10n = context.l10n;
    final ctx = cubit.fs.pathContext;
    final parentDir = isDirectory ? targetPath : ctx.dirname(targetPath);
    final canPaste = cubit.state.clipboard != null;
    final specs = <SidebarActionMenuSpec>[
      SidebarActionMenuSpec.item(
        value: 'new_file',
        icon: Icons.note_add_outlined,
        label: l10n.fileTreeNewFile,
      ),
      SidebarActionMenuSpec.item(
        value: 'new_folder',
        icon: Icons.create_new_folder_outlined,
        label: l10n.fileTreeNewFolder,
      ),
      const SidebarActionMenuSpec.divider(),
      SidebarActionMenuSpec.item(
        value: 'cut',
        icon: Icons.content_cut,
        label: l10n.fileTreeCut,
      ),
      SidebarActionMenuSpec.item(
        value: 'copy',
        icon: Icons.content_copy,
        label: l10n.fileTreeCopy,
      ),
      SidebarActionMenuSpec.item(
        value: 'paste',
        icon: Icons.content_paste,
        label: l10n.fileTreePaste,
        enabled: canPaste,
      ),
      const SidebarActionMenuSpec.divider(),
      SidebarActionMenuSpec.item(
        value: 'rename',
        icon: Icons.drive_file_rename_outline,
        label: l10n.fileTreeRename,
      ),
      SidebarActionMenuSpec.item(
        value: 'delete',
        icon: Icons.delete_outline,
        label: l10n.fileTreeDeleteItemTitle,
        destructive: true,
      ),
      const SidebarActionMenuSpec.divider(),
      if (!isDirectory)
        SidebarActionMenuSpec.item(
          value: 'external',
          icon: Icons.open_in_new,
          label: l10n.fileTreeOpenWithSystemApp,
        ),
      SidebarActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.fileTreeCopyPath,
      ),
      if (desktopShellActions) ...[
        SidebarActionMenuSpec.item(
          value: 'file_manager',
          icon: Icons.folder_open_outlined,
          label: l10n.fileTreeOpenInFileManager,
        ),
        SidebarActionMenuSpec.item(
          value: 'terminal',
          icon: Icons.terminal,
          label: l10n.fileTreeOpenInTerminal,
        ),
      ],
    ];

    final value = await showSidebarActionMenuFromSpecsAtTap<String>(
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
        );
      case 'new_folder':
        await _promptCreate(
          context,
          cubit: cubit,
          parentDir: parentDir,
          isFolder: true,
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
        if (!isDirectory) _openFileExternally(targetPath);
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: targetPath));
      case 'file_manager':
        await _openInFileManager(targetPath, isDirectory: isDirectory);
      case 'terminal':
        await _openInTerminal(context, targetPath, isDirectory: isDirectory);
    }
  }

  static Future<void> _promptCreate(
    BuildContext context, {
    required FileTreeCubit cubit,
    required String parentDir,
    required bool isFolder,
  }) async {
    final l10n = context.l10n;
    final name = await showAppTextPromptDialog(
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
              if (isEditorOpenableFilePath(created)) {
                unawaited(context.read<EditorCubit>().openFile(created));
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
    final name = await showAppTextPromptDialog(
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
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.fileTreeDeleteItemTitle),
            const SizedBox(height: 16),
            Text(l10n.fileTreeDeleteItemConfirm(targetName)),
            AppDialogActions(
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
        variant: AppToastVariant.success,
      );
    } on FileTreeOperationException catch (e) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: _mapError(context, e.message),
        variant: AppToastVariant.error,
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: e.toString(),
        variant: AppToastVariant.error,
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

  static void _openFileExternally(String filePath) {
    try {
      if (Platform.isLinux) {
        Process.run('xdg-open', [filePath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [filePath]);
      } else if (Platform.isWindows) {
        Process.run('start', [filePath], runInShell: true);
      }
    } catch (_) {}
  }

  static Future<void> _openInFileManager(
    String targetPath, {
    required bool isDirectory,
  }) async {
    final ctx = SystemFolderOpener();
    final path = isDirectory
        ? targetPath
        : SystemFolderOpener.revealPathForFile(targetPath);
    await ctx.reveal(path);
  }

  static Future<void> _openInTerminal(
    BuildContext context,
    String targetPath, {
    required bool isDirectory,
  }) async {
    final dir = isDirectory
        ? targetPath
        : SystemFolderOpener.revealPathForFile(targetPath);
    final ok = await SystemTerminalOpener().openAt(dir);
    if (!context.mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: context.l10n.fileTreeOpenInTerminalFailed,
        variant: AppToastVariant.error,
      );
    }
  }
}
