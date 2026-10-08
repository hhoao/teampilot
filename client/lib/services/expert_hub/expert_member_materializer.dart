import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import 'expert_hub_catalog.dart';

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

  /// Materializes every team's roster from a single pre-loaded catalog
  /// [snapshot] — no per-slot fetch. Sync: the snapshot already holds every
  /// resolvable expert.
  static List<TeamProfile> materializeAll(
    List<TeamProfile> teams,
    MemberCatalogSnapshot snapshot,
  ) => [for (final team in teams) materializeTeam(team, snapshot)];

  /// Attaches materialized members to a single [team] from [snapshot],
  /// dropping roster slots whose expertKey is not in the catalog.
  static TeamProfile materializeTeam(
    TeamProfile team,
    MemberCatalogSnapshot snapshot,
  ) => team.copyWith(
    members: [
      for (final slot in team.roster)
        if (snapshot.lookup(slot.expertKey) case final expert?)
          materializeRosterSlot(slot: slot, expert: expert, team: team),
    ],
  );

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
        next = next.copyWith(
          provider: '',
          model: '',
          effort: '',
          updateEffort: true,
        );
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
        for (final member in team.members) _applyTeamInheritance(member, team),
      ],
    );
  }
}
