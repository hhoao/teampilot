import 'package:collection/collection.dart';

import '../../models/cli_binary_kind.dart';
import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/acp_settings_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/work_target_canonicalizer.dart';

/// One required remote binary (a CLI, or a separate ACP adapter) for an SSH
/// machine used by the current placement.
class RemoteCliRequirement {
  const RemoteCliRequirement({
    required this.target,
    required this.cli,
    required this.hostLabel,
    this.kind = CliBinaryKind.cli,
  });

  final RuntimeTarget target;
  final CliTool cli;
  final String hostLabel;
  final CliBinaryKind kind;

  String get cacheKey => '${target.id}|${kind.name}|${cli.value}';
}

/// True when [cli]'s ACP mode needs a separate adapter binary.
bool _cliUsesSeparateAcpAdapter(CliTool cli) {
  final settings = CliToolRegistry.builtIn()
      .capability<AcpSettingsCapability>(cli);
  return settings?.usesSeparateAdapter == true;
}

/// Collects distinct (SSH target × CLI) pairs required by [placement].
List<RemoteCliRequirement> remoteCliRequirementsForPlacement({
  required Workspace workspace,
  required TeamProfile team,
  required MemberPlacementByTarget placement,
  required List<CliPreset> globalPresets,
  required List<RuntimeTarget> selectableTargets,
}) {
  final byId = {for (final t in selectableTargets) t.id: t};
  final out = <String, RemoteCliRequirement>{};

  for (final entry in placement.entries) {
    final targetId = entry.key;
    final target = byId[targetId];
    if (target == null || !usesSshTransport(target.kind)) continue;

    for (final memberEntry in entry.value.entries) {
      if (memberEntry.value <= 0) continue;
      final member = team.members
          .where((m) => m.id == memberEntry.key)
          .firstOrNull;
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
          hostLabel: target.label.trim().isNotEmpty ? target.label : target.id,
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
  required RuntimeTarget home,
  required bool usesPosixPaths,
}) {
  final normalized = normalizeWorkspacePath(
    projectFolderPath,
    usesPosixPaths: usesPosixPaths,
  );
  WorkspaceFolder? folder;
  for (final candidate in workspace.folders) {
    if (workspacePathsEqual(
      candidate.path,
      normalized,
      usesPosixPaths: usesPosixPaths,
    )) {
      folder = candidate;
      break;
    }
  }
  folder ??= workspace.folders.firstOrNull;
  if (folder == null) return null;

  final resolved = WorkTargetCanonicalizer.resolve(folder.targetId, home: home);
  if (!usesSshTransport(resolved.kind)) return null;

  return selectableTargets
          .where((t) => t.id == resolved.id && usesSshTransport(t.kind))
          .firstOrNull ??
      resolved;
}

/// Required remote binaries for a Simple (personal) launch on an SSH folder.
///
/// When [requestedAcp] is true and the CLI needs a separate ACP adapter
/// (Claude / Codex), a second `kind: adapter` requirement is appended.
List<RemoteCliRequirement> remoteCliRequirementsForSimpleLaunch({
  required Workspace workspace,
  required String projectFolderPath,
  required CliTool cli,
  required List<RuntimeTarget> selectableTargets,
  required RuntimeTarget home,
  required bool usesPosixPaths,
  bool requestedAcp = false,
}) {
  final target = sshTargetForProjectFolder(
    workspace: workspace,
    projectFolderPath: projectFolderPath,
    selectableTargets: selectableTargets,
    home: home,
    usesPosixPaths: usesPosixPaths,
  );
  if (target == null) return const [];

  final hostLabel = target.label.trim().isNotEmpty ? target.label : target.id;
  return [
    RemoteCliRequirement(target: target, cli: cli, hostLabel: hostLabel),
    if (requestedAcp && _cliUsesSeparateAcpAdapter(cli))
      RemoteCliRequirement(
        target: target,
        cli: cli,
        hostLabel: hostLabel,
        kind: CliBinaryKind.adapter,
      ),
  ];
}
