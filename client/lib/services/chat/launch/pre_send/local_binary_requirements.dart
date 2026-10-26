import 'package:collection/collection.dart';

import '../../../../models/cli_binary_kind.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_topology.dart';
import '../../../cli/preset_resolver.dart';
import '../../../remote/remote_cli_requirements.dart';
import '../../../storage/work_target_canonicalizer.dart';
import '../session/member_acp_stamp.dart';

/// Settings seed: does this CLI default to ACP chat (personal + mixed members)?
typedef MemberAcpSeed = bool Function(CliTool cli);

/// One binary the current draft will spawn on a non-SSH (local) host.
///
/// Local binaries are resolved from user-configured paths / startup discovery
/// instead of an SSH probe, so this carries no target: there is exactly one
/// local host.
class LocalBinaryRequirement {
  const LocalBinaryRequirement(this.cli, {this.kind = CliBinaryKind.cli});

  final CliTool cli;
  final CliBinaryKind kind;

  /// Stable identity for dedupe / banner keys.
  String get key => '${kind.name}|${cli.value}';
}

/// Local binaries required by [placement] (members placed on local/WSL hosts).
///
/// [acpSeed] is the settings default ("this CLI uses ACP chat"); when a member
/// will run ACP chat and its CLI needs a separate adapter binary, an extra
/// `kind: adapter` requirement is added. Mixed teams only — native teams and
/// remote members always use the terminal (see `resolveMemberBindingAcp`).
List<LocalBinaryRequirement> localBinaryRequirementsForPlacement({
  required TeamProfile team,
  required MemberPlacementByTarget placement,
  required List<CliPreset> globalPresets,
  required RuntimeTarget home,
  MemberAcpSeed? acpSeed,
  bool? isAndroidOverride,
}) {
  final out = <LocalBinaryRequirement>[];
  final seen = <String>{};

  for (final entry in placement.entries) {
    final target = WorkTargetCanonicalizer.resolve(entry.key, home: home);
    if (usesSshTransport(target.kind)) continue;

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
      final cliRequirement = LocalBinaryRequirement(cli);
      if (seen.add(cliRequirement.key)) out.add(cliRequirement);

      final memberAcp = resolveMemberBindingAcp(
        cli: cli,
        teamMode: team.teamMode,
        targetId: entry.key,
        requested: acpSeed?.call(cli) ?? false,
        isAndroidOverride: isAndroidOverride,
      );
      if (!memberAcp || !cliUsesSeparateAcpAdapter(cli)) continue;
      final adapterRequirement = LocalBinaryRequirement(
        cli,
        kind: CliBinaryKind.adapter,
      );
      if (seen.add(adapterRequirement.key)) out.add(adapterRequirement);
    }
  }
  return out;
}

/// Local binaries required by a Simple (personal) launch.
///
/// When [requestedAcp] is true and the CLI needs a separate ACP adapter
/// (Claude / Codex / OpenCode), a second `kind: adapter` requirement is added.
List<LocalBinaryRequirement> localBinaryRequirementsForSimpleLaunch({
  required Workspace workspace,
  required String projectFolderPath,
  required CliTool cli,
  required bool requestedAcp,
  required RuntimeTarget home,
  required bool usesPosixPaths,
}) {
  final target = projectFolderTarget(
    workspace: workspace,
    projectFolderPath: projectFolderPath,
    home: home,
    usesPosixPaths: usesPosixPaths,
  );
  if (target == null || usesSshTransport(target.kind)) return const [];

  return [
    LocalBinaryRequirement(cli),
    if (requestedAcp && cliUsesSeparateAcpAdapter(cli))
      LocalBinaryRequirement(cli, kind: CliBinaryKind.adapter),
  ];
}
