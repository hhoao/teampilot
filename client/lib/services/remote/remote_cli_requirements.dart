import 'package:collection/collection.dart';

import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../cli/preset_resolver.dart';

/// One required remote CLI for an SSH machine used by the current placement.
class RemoteCliRequirement {
  const RemoteCliRequirement({
    required this.target,
    required this.cli,
    required this.hostLabel,
  });

  final RuntimeTarget target;
  final CliTool cli;
  final String hostLabel;

  String get cacheKey => '${target.id}|${cli.value}';
}

/// Collects distinct (SSH target × CLI) pairs required by [placement].
List<RemoteCliRequirement> remoteCliRequirementsForPlacement({
  required Workspace workspace,
  required TeamProfile team,
  required MemberPlacementByTarget placement,
  required List<CliPreset> globalPresets,
  required List<RuntimeTarget> selectableTargets,
}) {
  final byId = {
    for (final t in selectableTargets) t.id: t,
  };
  final out = <String, RemoteCliRequirement>{};

  for (final entry in placement.entries) {
    final targetId = entry.key;
    final target = byId[targetId];
    if (target == null || target.kind != RuntimeKind.ssh) continue;

    for (final memberEntry in entry.value.entries) {
      if (memberEntry.value <= 0) continue;
      final member = team.members.where((m) => m.id == memberEntry.key).firstOrNull;
      if (member == null || !member.isValid) continue;
      final cli = memberLaunchCli(
        team: team,
        member: member,
        globalPresets: globalPresets,
      );
      final key = '$targetId|${cli.value}';
      out.putIfAbsent(
        key,
        () => RemoteCliRequirement(
          target: target,
          cli: cli,
          hostLabel: target.label.trim().isNotEmpty
              ? target.label
              : target.id,
        ),
      );
    }
  }
  return out.values.toList();
}

/// SSH target for [projectFolderPath] when that folder is on a remote machine.
RuntimeTarget? sshTargetForProjectFolder({
  required Workspace workspace,
  required String projectFolderPath,
  required List<RuntimeTarget> selectableTargets,
}) {
  final normalized = normalizeWorkspacePath(projectFolderPath);
  WorkspaceFolder? folder;
  for (final candidate in workspace.folders) {
    if (workspacePathsEqual(candidate.path, normalized)) {
      folder = candidate;
      break;
    }
  }
  folder ??= workspace.folders.firstOrNull;
  if (folder == null) return null;

  final targetId = folder.targetId.trim();
  if (targetId.isEmpty || targetId == WorkspaceFolder.localTargetId) {
    return null;
  }
  return selectableTargets
      .where((t) => t.id == targetId && t.kind == RuntimeKind.ssh)
      .firstOrNull;
}

/// Required remote CLI for Simple (personal) launch on an SSH project folder.
List<RemoteCliRequirement> remoteCliRequirementsForSimpleLaunch({
  required Workspace workspace,
  required String projectFolderPath,
  required CliTool cli,
  required List<RuntimeTarget> selectableTargets,
}) {
  final target = sshTargetForProjectFolder(
    workspace: workspace,
    projectFolderPath: projectFolderPath,
    selectableTargets: selectableTargets,
  );
  if (target == null) return const [];

  return [
    RemoteCliRequirement(
      target: target,
      cli: cli,
      hostLabel: target.label.trim().isNotEmpty ? target.label : target.id,
    ),
  ];
}
