import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/workbench/workbench_shell_launcher.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../widgets/workspace_terminal/workspace_terminal_new_session_menu.dart';

/// Opens the same shell-launch catalog as the session-strip "+" → New terminal
/// path, always creating a new floating terminal tab (never focus-existing).
Future<void> showFloatingNewTerminalMenu({
  required BuildContext context,
  required Offset globalPosition,
}) async {
  if (!context.mounted) return;
  final chat = context.read<ChatCubit>();
  final workspaceId = chat.tabStore.activeWorkspaceId.trim();
  if (workspaceId.isEmpty) return;

  final workspace = chat.state.workspaces
      .where((w) => w.workspaceId == workspaceId)
      .firstOrNull;
  final cwd = workspace?.firstFolderPath.trim() ?? '';
  if (cwd.isEmpty) return;

  final folders =
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ??
      workspace?.folders ??
      const [];
  final connector = context.read<WorkspaceShellConnector>();
  final launcher = context.read<WorkbenchShellLauncher>();
  final sshFailed = context.l10n.workspaceTerminalSshConnectFailed;

  await showWorkspaceTerminalLaunchMenu(
    context: context,
    globalPosition: globalPosition,
    folders: folders,
    connector: connector,
    onSessionSelected: (spec) {
      unawaited(
        launcher.openAndSelect(
          workspaceId: workspaceId,
          tabScopeId: workspaceId,
          cwd: cwd,
          spec: spec,
          sshConnectFailedMessage: sshFailed,
          folders: folders,
          onStateChanged: () {},
          mounted: () => context.mounted,
        ),
      );
    },
  );
}
