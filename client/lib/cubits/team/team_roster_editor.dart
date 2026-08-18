import '../../models/default_team_roster.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../utils/team/team_member_naming.dart';

/// Outcome of a roster mutation: either an [team] to persist, or a
/// [statusMessage] explaining why the mutation was rejected. Exactly one of
/// the two is non-null.
class MemberMutation {
  const MemberMutation.update(this.team, {this.statusMessage})
    : assert(team != null);
  const MemberMutation.reject(this.statusMessage) : team = null;

  final TeamProfile? team;
  final String? statusMessage;

  bool get isRejected => team == null;
}

/// Pure roster transforms. No IO, no state, no emit — callers persist
/// and emit the returned values.
class TeamRosterEditor {
  const TeamRosterEditor();

  TeamProfile defaultNativeTeam() => _defaultBuiltInTeam(
    id: LaunchProfileProvisioner.defaultNativeTeamId,
    name: 'Default Native Team',
    teamMode: TeamMode.native,
    sortOrder: 1,
  );

  TeamProfile defaultMixedTeam() => _defaultBuiltInTeam(
    id: LaunchProfileProvisioner.defaultMixedTeamId,
    name: 'Default Mixed Team',
    teamMode: TeamMode.mixed,
    sortOrder: 2,
  );

  TeamProfile _defaultBuiltInTeam({
    required String id,
    required String name,
    required TeamMode teamMode,
    required int sortOrder,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TeamProfile(
      id: id,
      name: name,
      teamMode: teamMode,
      sortOrder: sortOrder,
      createdAt: now,
      roster: TeamMemberNaming.defaultRoster(joinedAt: now),
    );
  }

  TeamRosterSlot defaultSlot({int? now}) {
    final ts = now ?? DateTime.now().millisecondsSinceEpoch;
    return TeamMemberNaming.defaultRoster(joinedAt: ts).first;
  }

  /// Ensures the roster contains a team-lead, prepending a default one if not.
  TeamProfile normalizeTeam(TeamProfile team) {
    final hasLead = team.roster.any(TeamMemberNaming.isTeamLeadSlot);
    if (hasLead) return team;
    final now = DateTime.now().millisecondsSinceEpoch;
    return team.copyWith(
      roster: [
        defaultSlot(now: now),
        ...team.roster,
      ],
    );
  }

  String uniqueMemberSlug(TeamProfile team, String base) {
    final existing = team.roster.map((s) => s.id).toSet();
    final first = TeamMemberNaming.slugMemberName(base);
    if (!existing.contains(first)) return first;
    var i = 2;
    while (true) {
      final candidate = TeamMemberNaming.slugMemberName('$base-$i');
      if (!existing.contains(candidate)) return candidate;
      i++;
    }
  }

  /// Auto-suffixes [base] so it does not collide with [existingNames].
  String uniqueDisplayName(String base, Set<String> existingNames) {
    var displayName = base;
    var n = 2;
    while (existingNames.contains(displayName)) {
      displayName = '$base ($n)';
      n++;
    }
    return displayName;
  }

  /// Appends an expert reference to [team], uniquifying slot id.
  ({TeamProfile team, TeamRosterSlot added}) addExpertToTeam(
    TeamProfile team,
    String expertKey, {
    TeamRosterSlotOverrides? overrides,
    String? slotIdHint,
  }) {
    final key = expertKey.trim();
    final id = uniqueMemberSlug(
      team,
      slotIdHint?.trim().isNotEmpty == true
          ? slotIdHint!.trim()
          : DefaultTeamRoster.developerMemberId,
    );
    final added = TeamRosterSlot(
      id: id,
      expertKey: key,
      overrides: overrides ?? const TeamRosterSlotOverrides(),
      joinedAt: DateTime.now().millisecondsSinceEpoch,
    );
    return (team: team.copyWith(roster: [...team.roster, added]), added: added);
  }

  TeamRosterSlot? slotById(TeamProfile team, String memberId) {
    for (final slot in team.roster) {
      if (slot.id == memberId) return slot;
    }
    return null;
  }

  /// Applies launch overrides from a materialized [member] view onto the slot.
  MemberMutation updateMemberOverrides(
    TeamProfile team,
    String memberId,
    TeamMemberConfig member,
  ) {
    final slot = slotById(team, memberId);
    if (slot == null) {
      return const MemberMutation.reject('Member not found.');
    }
    final overrides = TeamRosterSlotOverrides(
      provider: member.provider,
      model: member.model,
      effort: member.effort,
      extraArgs: member.extraArgs,
      cli: member.cli,
      replicas: member.replicas,
      capabilities: member.capabilities,
      activePresetId: member.activePresetId,
      launchSecurityPolicy: member.launchSecurityPolicy,
    );
    return MemberMutation.update(
      team.copyWith(
        roster: [
          for (final s in team.roster)
            if (s.id == memberId) s.copyWith(overrides: overrides) else s,
        ],
      ),
    );
  }

  /// Updates slot id or expert key (not persona text).
  MemberMutation updateSlot(
    TeamProfile team,
    String memberId,
    TeamRosterSlot updated,
  ) {
    if (slotById(team, memberId) == null) {
      return const MemberMutation.reject('Member not found.');
    }
    return MemberMutation.update(
      team.copyWith(
        roster: [
          for (final s in team.roster)
            if (s.id == memberId) updated else s,
        ],
      ),
    );
  }

  /// Validates and removes the slot with [memberId] from [team].
  MemberMutation removeMember(TeamProfile team, String memberId) {
    TeamRosterSlot? target;
    for (final s in team.roster) {
      if (s.id == memberId) {
        target = s;
        break;
      }
    }
    if (target != null && TeamMemberNaming.isTeamLeadSlot(target)) {
      return const MemberMutation.reject(
        'Cannot remove team-lead from the roster.',
      );
    }
    if (team.roster.length == 1) {
      return const MemberMutation.reject('A team needs at least one member.');
    }
    return MemberMutation.update(
      team.copyWith(
        roster: team.roster
            .where((s) => s.id != memberId)
            .toList(growable: false),
      ),
      statusMessage: 'Deleted $memberId.',
    );
  }
}
