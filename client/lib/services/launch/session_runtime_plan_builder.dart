import '../../models/config_bundle.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../expert_hub/expert_capability_pack.dart';
import '../expert_hub/expert_capability_resolver.dart';
import '../expert_hub/expert_landing_preflight.dart';
import 'layered_config_bundle.dart';
import 'session_runtime_plan.dart';

/// Maps a roster [TeamMemberConfig] to a [TeamRosterSlot] for plan building.
///
/// Prefers an existing [TeamProfile.roster] entry; otherwise synthesizes a slot
/// from member override fields only. [TeamRosterSlot.expertKey] is left empty so
/// [SessionRuntimePlanBuilder.buildTeamSeat] resolves the builtin default pack —
/// never use [TeamMemberConfig.id] (e.g. `team-lead`) as a catalog key.
TeamRosterSlot teamRosterSlotForMember(
  TeamProfile team,
  TeamMemberConfig member,
) {
  for (final slot in team.roster) {
    if (slot.id == member.id) return slot;
  }
  return TeamRosterSlot(
    id: member.id,
    expertKey: '',
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
  ///
  /// [identity] is the session-pinned launch identity. Expert packs do not own
  /// the Simple CLI/provider/model — without this override, staging falls back
  /// to Claude and Cursor/Codex resume breaks.
  Future<SessionRuntimePlan> buildSimple({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    SimpleLaunchIdentity? identity,
    String? expertKey,
  }) async {
    final resolvedKey = resolveLandingSessionExpertKey(
      identity?.expertKey.trim().isNotEmpty == true
          ? identity!.expertKey
          : expertKey,
    );
    final workspaceBundle = await _loadWorkspaceBundle(workspaceId);
    final pack = await _resolvePackOrThrow(resolvedKey);

    final runtimeBundle = LayeredConfigBundle.merge(
      expert: pack.bundle,
      workspace: workspaceBundle,
    );

    final member = identity?.applyToMember(pack.member) ?? pack.member;

    return SessionRuntimePlan(
      mode: SessionRuntimeMode.simple,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      expertKey: resolvedKey,
      presetId: identity?.presetId,
      runtimeBundle: runtimeBundle,
      member: member,
    );
  }

  /// One team roster seat: merge team > expert(slot) > workspace.
  ///
  /// Pack deps/bundle come from [slot.expertKey] (empty → builtin default).
  /// When [member] is provided (materialized connect seat), it becomes
  /// [SessionRuntimePlan.member] so role prompt / CLI come from the team
  /// member while the expert pack still supplies the runtime bundle layer.
  Future<SessionRuntimePlan> buildTeamSeat({
    required String workspaceId,
    required String sessionId,
    required TeamProfile team,
    required TeamRosterSlot slot,
    String? presetId,
    TeamMemberConfig? member,
  }) async {
    final resolvedKey = resolveLandingSessionExpertKey(slot.expertKey);
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
      member: member ?? pack.member,
    );
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
