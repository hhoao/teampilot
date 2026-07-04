import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../models/runtime_target.dart';
import '../../utils/workspace_display_name.dart';
import 'home_workspace_tab_scope.dart';
String workspaceTabDisplayLabel({
  required AppLocalizations l10n,
  required Workspace workspace,
}) {
  return workspace.localizedName(l10n);
}

String workspaceTopologyLabel(
  AppLocalizations l10n,
  WorkspaceTopology topology,
) {
  return switch (topology) {
    WorkspaceTopology.local => l10n.workspaceTopologyLocal,
    WorkspaceTopology.remote => l10n.workspaceTopologyRemote,
    WorkspaceTopology.mixed => l10n.workspaceTopologyMixed,
  };
}

@visibleForTesting
String? formatWorkspaceFolderTooltipLine(WorkspaceFolder folder) {
  final path = folder.path.trim();
  if (path.isEmpty) return null;
  return switch (runtimeKindOfId(folder.targetId)) {
    RuntimeKind.ssh => 'SSH: $path',
    RuntimeKind.wsl => 'WSL: $path',
    RuntimeKind.local => path,
  };
}

@visibleForTesting
List<String> workspaceTabTooltipFolderLines(List<WorkspaceFolder> folders) {
  return [
    for (final folder in folders)
      if (formatWorkspaceFolderTooltipLine(folder) case final line?) line,
  ];
}

String formatWorkspaceTabTooltip({
  required Workspace workspace,
  String? displayName,
  WorkspaceTopology topology = WorkspaceTopology.local,
  String? topologyLabel,
}) {
  final name = displayName ?? workspace.effectiveDisplay;
  final headlineParts = <String>[
    if (topology != WorkspaceTopology.local &&
        topologyLabel != null &&
        topologyLabel.isNotEmpty)
      topologyLabel,
    name,
  ];
  final headline = headlineParts.join(' · ');
  final pathLines = workspaceTabTooltipFolderLines(workspace.folders);
  if (pathLines.isEmpty) return headline;
  return '$headline\n${pathLines.join('\n')}';
}

/// Opens [workspace] in a title-bar tab and navigates directly.
Future<void> openWorkspace(BuildContext context, Workspace workspace) async {
  await context.read<ChatCubit>().ensureSessionsForWorkspace(workspace.workspaceId);
  if (!context.mounted) return;
  HomeTabScope.openInTab(context, workspace.workspaceId);
  context.go('/home-v2/workspace/${workspace.workspaceId}');
}
