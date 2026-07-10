import '../../models/config_bundle.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../expert_hub/builtin_member_templates.dart';
import '../expert_hub/expert_capability_pack.dart';
import '../expert_hub/expert_capability_resolver.dart';
import 'layered_config_bundle.dart';
import 'session_runtime_plan.dart';

/// Maps a roster [TeamMemberConfig] to a [TeamRosterSlot] for plan building.
///
/// Prefers an existing [TeamProfile.roster] entry; otherwise synthesizes a slot
/// from member agent/override fields (preview / legacy roster shapes).
TeamRosterSlot teamRosterSlotForMember(
  TeamProfile team,
  TeamMemberConfig member,
) {
  for (final slot in team.roster) {
    if (slot.id == member.id) return slot;
  }
  return TeamRosterSlot(
    id: member.id,
    expertKey: member.agentType.trim().isNotEmpty
        ? member.agentType
        : (member.agent.trim().isNotEmpty ? member.agent : member.id),
    overrides: TeamRosterSlotOverrides(
      provider: member.provider,
      model: member.model,
      effort: member.effort,
      extraArgs: member.extraArgs,
      cli: member.cli,
      replicas: member.replicas,
      capabilities: member.capabilities,
      activePresetId: member.activePresetId,
    ),
    joinedAt: member.joinedAt,
  );
}

/// Builds a per-seat [SessionRuntimePlan] from workspace + expert (+ team).
///
/// Unknown expert keys throw [StateError] (hard fail). Soft dep install
/// failures stay inside the resolved pack and do not abort the plan.
class SessionRuntimePlanBuilder {
  SessionRuntimePlanBuilder({
    required ExpertCapabilityResolver expertResolver,
    Future<ConfigBundle> Function(String workspaceId)? loadWorkspaceBundle,
    WorkspaceProjectConfigRepository? workspaceProjectConfig,
  }) : _expertResolver = expertResolver,
       _loadWorkspaceBundle =
           loadWorkspaceBundle ??
           ((workspaceId) async {
             final repo = workspaceProjectConfig;
             if (repo == null) {
               throw StateError(
                 'SessionRuntimePlanBuilder requires loadWorkspaceBundle '
                 'or workspaceProjectConfig',
               );
             }
             final config = await repo.load(workspaceId);
             return config.bundle;
           });

  final ExpertCapabilityResolver _expertResolver;
  final Future<ConfigBundle> Function(String workspaceId) _loadWorkspaceBundle;

  /// Simple (unteamed) seat. Empty [expertKey] → [kBuiltinDefaultExpertKey].
  Future<SessionRuntimePlan> buildSimple({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    String? expertKey,
    String? presetId,
  }) async {
    final resolvedKey = _normalizeExpertKey(expertKey);
    final workspaceBundle = await _loadWorkspaceBundle(workspaceId);
    final pack = await _resolvePackOrThrow(resolvedKey);

    final runtimeBundle = LayeredConfigBundle.merge(
      expert: pack.bundle,
      workspace: workspaceBundle,
    );

    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      expertKey: resolvedKey,
      presetId: presetId,
      runtimeBundle: runtimeBundle,
      member: pack.member,
    );
  }

  /// One team roster seat: merge team > expert(slot) > workspace.
  Future<SessionRuntimePlan> buildTeamSeat({
    required String workspaceId,
    required String sessionId,
    required TeamProfile team,
    required TeamRosterSlot slot,
    String? presetId,
  }) async {
    final resolvedKey = _normalizeExpertKey(slot.expertKey);
    final workspaceBundle = await _loadWorkspaceBundle(workspaceId);
    final pack = await _resolvePackOrThrow(
      resolvedKey,
      overrides: slot.overrides,
      team: team,
      slotId: slot.id,
      joinedAt: slot.joinedAt == 0 ? null : slot.joinedAt,
    );

    final runtimeBundle = LayeredConfigBundle.merge(
      team: team.bundle,
      expert: pack.bundle,
      workspace: workspaceBundle,
    );

    return SessionRuntimePlan(
      mode: SessionRuntimeMode.team,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: slot.id,
      expertKey: resolvedKey,
      teamId: team.id,
      presetId: presetId,
      runtimeBundle: runtimeBundle,
      member: pack.member,
    );
  }

  String _normalizeExpertKey(String? expertKey) {
    final trimmed = expertKey?.trim() ?? '';
    return trimmed.isEmpty ? kBuiltinDefaultExpertKey : trimmed;
  }

  Future<ExpertCapabilityPack> _resolvePackOrThrow(
    String expertKey, {
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) async {
    final pack = await _expertResolver.resolveKey(
      expertKey,
      overrides: overrides,
      team: team,
      slotId: slotId,
      joinedAt: joinedAt,
    );
    if (pack == null) {
      throw StateError('Unknown expert key: $expertKey');
    }
    return pack;
  }
}
