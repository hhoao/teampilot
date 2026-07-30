import 'package:uuid/uuid.dart';

import '../../models/member_instance.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../utils/team/team_member_naming.dart';

/// Placement + taskId allocation result for a team session create/stage path.
class TeamSessionMemberPlan {
  const TeamSessionMemberPlan({
    required this.members,
    required this.memberTargets,
    required this.persistTargets,
  });

  final List<SessionMemberBinding> members;
  final Map<String, String> memberTargets;
  final bool persistTargets;
}

/// Builds session member bindings and resolved machine pins for a team.
///
/// Heal → expand → resolve targets → include only pinned instances → allocate
/// unique [SessionMemberBinding.taskId]s (never [AppSession.sessionId]).
TeamSessionMemberPlan buildTeamSessionMemberPlan({
  required Workspace workspace,
  required String teamId,
  required List<TeamMemberConfig> rosterMembers,
  required Map<String, CliTool> memberClis,
  String Function()? allocateTaskId,
}) {
  final trimmedTeam = teamId.trim();
  final valid = rosterMembers.where((m) => m.isValid).toList();
  if (valid.isEmpty) {
    throw ArgumentError(
      'Team session requires at least one valid roster member',
    );
  }
  if (workspaceNeedsMixedPlacementInit(
    folders: workspace.folders,
    teamId: trimmedTeam,
    initializedByTeam: workspace.memberPlacementInitializedByTeam,
  )) {
    throw StateError('mixed_workspace_member_placement_uninitialized');
  }

  final remembered = rememberedMemberTargets(
    workspace.memberTargetsByTeam,
    trimmedTeam,
  );
  // Heal stale profile replicas when remembered pins imply more pods
  // (placement used to write targets without roster.overrides.replicas).
  final healed = healMemberReplicasFromTargets(
    members: valid,
    targets: remembered,
  );
  final instances = expandTeamRoster(healed);
  final resolved = resolveSessionMemberTargets(
    workspace: workspace,
    instances: instances,
    remembered: remembered,
  );

  final included = [
    for (final inst in instances)
      if (resolved.targets.containsKey(inst.instanceId)) inst,
  ];
  if (!leadPlacementValid(
        folders: workspace.folders,
        members: healed,
        targets: resolved.targets,
      ) ||
      !includedLeadWhenRequired(healed, included)) {
    throw StateError('lead_placement_invalid');
  }
  for (final inst in included) {
    if (!memberClis.containsKey(inst.type.id)) {
      throw ArgumentError('missing memberClis for ${inst.type.id}');
    }
  }

  final nextId = allocateTaskId ?? const Uuid().v4;
  return TeamSessionMemberPlan(
    members: [
      for (final inst in included)
        SessionMemberBinding(
          rosterMemberId: inst.instanceId,
          typeId: inst.type.id,
          taskId: nextId(),
          cli: memberClis[inst.type.id]!,
        ),
    ],
    memberTargets: {
      for (final inst in included)
        inst.instanceId: resolved.targets[inst.instanceId]!,
    },
    persistTargets: resolved.persistTargets,
  );
}

/// Resolves instance pins for session create / staging.
///
/// Single-host: fill every expanded instance to the sole host (persist when
/// empty/partial). Mixed: never invent pins; omit unresolvable instances.
({MemberTargetAssignments targets, bool persistTargets})
resolveSessionMemberTargets({
  required Workspace workspace,
  required List<MemberInstance> instances,
  required MemberTargetAssignments remembered,
}) {
  final folders = workspace.folders;
  final hostIds = workspaceTargetIds(folders);
  final topology = workspaceTopologyOf(folders);

  if (topology != WorkspaceTopology.mixed) {
    final host = hostIds.isEmpty
        ? WorkspaceFolder.localTargetId
        : hostIds.first;
    final pinned = <String, String>{};
    var filledGap = false;
    for (final inst in instances) {
      final existing = memberTargetForInstanceId(remembered, inst.instanceId);
      if (existing != null &&
          hostIds.contains(existing) &&
          folderPathsForTarget(folders, existing).isNotEmpty) {
        pinned[inst.instanceId] = existing;
      } else {
        pinned[inst.instanceId] = host;
        filledGap = true;
      }
    }
    return (targets: pinned, persistTargets: remembered.isEmpty || filledGap);
  }

  final pinned = <String, String>{};
  for (final inst in instances) {
    final existing = memberTargetForInstanceId(remembered, inst.instanceId);
    if (existing == null) continue;
    if (!hostIds.contains(existing)) continue;
    if (folderPathsForTarget(folders, existing).isEmpty) continue;
    pinned[inst.instanceId] = existing;
  }
  return (targets: pinned, persistTargets: false);
}

/// True when the roster has no lead, or the lead instance is among [included].
bool includedLeadWhenRequired(
  List<TeamMemberConfig> valid,
  List<MemberInstance> included,
) {
  final requiresLead = valid.any(TeamMemberNaming.isTeamLead);
  if (!requiresLead) return true;
  return included.any((inst) => TeamMemberNaming.isTeamLead(inst.type));
}
