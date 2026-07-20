import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../models/runtime_target.dart';
import '../../utils/workspace/workspace_display_name.dart';
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

/// Opens [workspace] in a title-bar tab and navigates immediately.
///
/// Session hydration is started by [HomeShell] prefetch / [WorkspacePage]
/// activation — do not await it here. The sidebar shows a skeleton until
/// [ChatCubit.sessionsLoadedForWorkspace] is true so chrome can paint first.
Future<void> openWorkspace(BuildContext context, Workspace workspace) async {
  HomeTabScope.openInTab(context, workspace.workspaceId);
}
