import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../cubits/chat_cubit.dart';
import '../../../../widgets/app_toast/app_toast.dart';

import '../../../io/file_path_actions.dart';
import '../../open_workspace_terminal_at_path.dart';
import '../workbench_tab_menu_context.dart';
import '../workbench_tab_menu_source.dart';

/// File-path clipboard and opener actions for file and diff tabs.
class FilePathTabMenuSource implements WorkbenchTabMenuSource {
  const FilePathTabMenuSource();

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) {
    final path = ctx.filePath;
    if (path == null) return const [];

    final l10n = ctx.l10n;
    final pathContext = ctx.workContext?.fs.pathContext;
    final relativeEnabled = tryRelativeWorkspacePath(
          absolutePath: path,
          workspaceRoot: ctx.workspaceRoot,
          pathContext: pathContext,
        ) !=
        null;
    final showReveal =
        ctx.desktopShellActions || ctx.remoteFileManagerActions;

    final items = <WorkbenchTabMenuItem>[
      WorkbenchTabMenuItem(
        id: 'file.copy_path',
        icon: Icons.copy,
        label: l10n.fileTreeCopyPath,
        onAction: () {
          unawaited(FilePathActions.copyAbsolutePath(path));
        },
      ),
      WorkbenchTabMenuItem(
        id: 'file.copy_relative_path',
        icon: Icons.copy_outlined,
        label: l10n.fileTreeCopyRelativePath,
        enabled: relativeEnabled,
        onAction: () {
          unawaited(
            FilePathActions.copyRelativePath(
              absolutePath: path,
              workspaceRoot: ctx.workspaceRoot,
              pathContext: pathContext,
            ),
          );
        },
      ),
    ];

    if (showReveal) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'file.reveal',
          icon: Icons.folder_open_outlined,
          label: l10n.fileTreeOpenInFileManager,
          onAction: () {
            unawaited(
              FilePathActions.revealInFileManager(
                targetPath: path,
                isDirectory: false,
                remoteFileManagerActions: ctx.remoteFileManagerActions,
                workContext: ctx.workContext,
              ),
            );
          },
        ),
      );
    }

    if (ctx.desktopShellActions) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'file.open_terminal',
          icon: Icons.terminal,
          label: l10n.fileTreeOpenInTerminal,
          onAction: () {
            unawaited(_openInTerminal(ctx, path));
          },
        ),
      );
      items.add(
        WorkbenchTabMenuItem(
          id: 'file.open_external',
          icon: Icons.open_in_new,
          label: l10n.fileTreeOpenWithSystemApp,
          onAction: () => FilePathActions.openWithSystemApp(path),
        ),
      );
    }

    return items;
  }

  Future<void> _openInTerminal(WorkbenchTabMenuContext ctx, String path) async {
    final buildContext = ctx.buildContext;
    if (buildContext == null) return;
    final workspaceId = buildContext.read<ChatCubit>().tabStore.activeWorkspaceId;
    final ok = await openWorkspaceTerminalAtPath(
      context: buildContext,
      workspaceId: workspaceId,
      targetPath: path,
      isDirectory: false,
    );
    if (!buildContext.mounted) return;
    if (!ok) {
      AppToast.show(
        buildContext,
        message: ctx.l10n.fileTreeOpenInTerminalFailed,
        variant: TpToastVariant.error,
      );
    }
  }
}
