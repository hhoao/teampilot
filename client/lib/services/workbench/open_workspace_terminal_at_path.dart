import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../l10n/l10n_extensions.dart';
import '../workspace/workspace_tools_scope.dart';
import 'workbench_shell_launcher.dart';

/// Opens a TeamPilot floating workspace shell at [targetPath] (file → parent dir).
Future<bool> openWorkspaceTerminalAtPath({
  required BuildContext context,
  required String workspaceId,
  required String targetPath,
  required bool isDirectory,
}) async {
  final trimmedWorkspaceId = workspaceId.trim();
  if (trimmedWorkspaceId.isEmpty || !context.mounted) return false;

  final folders =
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ?? const [];
  final launcher = context.read<WorkbenchShellLauncher>();
  final sshFailed = context.l10n.workspaceTerminalSshConnectFailed;

  return launcher.openAtPath(
    workspaceId: trimmedWorkspaceId,
    targetPath: targetPath,
    isDirectory: isDirectory,
    folders: folders,
    sshConnectFailedMessage: sshFailed,
    mounted: () => context.mounted,
  );
}
