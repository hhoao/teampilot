import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';
import 'local_member_template_store.dart';

/// Resolves catalog experts into runtime [TeamMemberConfig] for connect/launch.
abstract final class ExpertMemberMaterializer {
  ExpertMemberMaterializer._();

  static TeamMemberConfig materializeRosterSlot({
    required TeamRosterSlot slot,
    required DiscoverableMember expert,
    required TeamProfile team,
    int? joinedAtOverride,
  }) {
    final joinedAt = joinedAtOverride ?? slot.joinedAt;
    final base = expert.toMemberConfig(
      joinedAt: joinedAt > 0 ? joinedAt : DateTime.now().millisecondsSinceEpoch,
      idOverride: slot.id,
    );
    var member = slot.overrides.applyTo(base);
    member = _applyTeamInheritance(member, team);
    return member;
  }

  static List<TeamMemberConfig> materializeRoster({
    required TeamProfile team,
    required Map<String, DiscoverableMember> expertsByKey,
  }) {
    return [
      for (final slot in team.roster)
        if (expertsByKey.containsKey(slot.expertKey.trim()))
          materializeRosterSlot(
            slot: slot,
            expert: expertsByKey[slot.expertKey.trim()]!,
            team: team,
          ),
    ];
  }

  static Future<List<TeamMemberConfig>> materializeRosterAsync({
    required TeamProfile team,
    CompositeExpertHubSource? source,
    LocalMemberTemplateStore? localStore,
  }) async {
    final out = <TeamMemberConfig>[];
    for (final slot in team.roster) {
      final key = slot.expertKey.trim();
      if (key.isEmpty) continue;
      final expert = await ExpertMemberResolver.resolveMember(
        key: key,
        source: source,
        localStore: localStore,
      );
      if (expert == null) continue;
      out.add(
        materializeRosterSlot(slot: slot, expert: expert, team: team),
      );
    }
    return out;
  }

  static TeamMemberConfig _applyTeamInheritance(
    TeamMemberConfig member,
    TeamProfile team,
  ) {
    final inheritsTeamPreset =
        member.activePresetId == null ||
        member.activePresetId!.isEmpty ||
        member.activePresetId == TeamProfile.inheritPresetId;

    if (inheritsTeamPreset) {
      var next = member;
      if (next.provider.trim().isNotEmpty ||
          next.model.trim().isNotEmpty ||
          next.effort.trim().isNotEmpty) {
        next = next.copyWith(provider: '', model: '', effort: '', updateEffort: true);
      }
      if (next.activePresetId == null || next.activePresetId!.isEmpty) {
        next = next.copyWith(
          activePresetId: TeamProfile.inheritPresetId,
          updateActivePresetId: true,
        );
      }
      return next;
    }

    final cli = member.cli ?? team.cli;
    var next = member;
    if (next.provider.trim().isEmpty) {
      final p = team.providerForCli(cli);
      if (p.isNotEmpty) next = next.copyWith(provider: p);
    }
    if (next.model.trim().isEmpty) {
      final m = team.modelForCli(cli);
      if (m.isNotEmpty) next = next.copyWith(model: m);
    }
    if (next.effort.trim().isEmpty) {
      final e = team.effortForCli(cli);
      if (e.isNotEmpty) next = next.copyWith(effort: e, updateEffort: true);
    }
    return next;
  }

  /// Re-applies team launch inheritance on already-materialized members without
  /// re-fetching Expert Hub (used for launch-config-only profile edits).
  static TeamProfile reapplyLaunchInheritance(TeamProfile team) {
    if (team.members.isEmpty) return team;
    return team.copyWith(
      members: [
        for (final member in team.members)
          _applyTeamInheritance(member, team),
      ],
    );
  }

  static Future<TeamProfile> attachMaterializedMembers(
    TeamProfile team, {
    CompositeExpertHubSource? source,
    LocalMemberTemplateStore? localStore,
  }) async {
    final members = await materializeRosterAsync(
      team: team,
      source: source,
      localStore: localStore,
    );
    return team.copyWith(members: members);
  }

  static Future<List<TeamProfile>> attachMaterializedMembersAll(
    Iterable<TeamProfile> teams, {
    CompositeExpertHubSource? source,
    LocalMemberTemplateStore? localStore,
  }) async {
    final out = <TeamProfile>[];
    for (final team in teams) {
      out.add(
        await attachMaterializedMembers(
          team,
          source: source,
          localStore: localStore,
        ),
      );
    }
    return out;
  }
}
