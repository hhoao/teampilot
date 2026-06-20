import '../../services/storage/launch_profile_provisioner.dart';
import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

/// Outcome of a member mutation: either an [team] to persist, or a
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

/// Pure roster/member transforms. No IO, no state, no emit — callers persist
/// and emit the returned values.
class TeamRosterEditor {
  const TeamRosterEditor();

  TeamProfile defaultTeam() {
    const name = 'Default Team';
    final now = DateTime.now().millisecondsSinceEpoch;
    return TeamProfile(
      id: LaunchProfileProvisioner.defaultTeamId,
      name: name,
      createdAt: now,
      members: TeamMemberNaming.defaultRoster(joinedAt: now),
    );
  }

  TeamMemberConfig defaultMember({int? now}) {
    final ts = now ?? DateTime.now().millisecondsSinceEpoch;
    return TeamMemberNaming.defaultRoster(joinedAt: ts).first;
  }

  /// Ensures the roster contains a team-lead, prepending a default one if not.
  TeamProfile normalizeTeam(TeamProfile team) {
    final hasLead = team.members.any(TeamMemberNaming.isTeamLead);
    if (hasLead) return team;
    final now = DateTime.now().millisecondsSinceEpoch;
    return team.copyWith(
      members: [
        defaultMember(now: now),
        ...team.members,
      ],
    );
  }

  TeamMemberConfig normalizeMember(TeamMemberConfig member) => member;

  String uniqueMemberSlug(TeamProfile team, String base) {
    final existing = team.members.map((m) => m.id).toSet();
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

  /// Appends a fresh default-worker member to [team].
  ({TeamProfile team, TeamMemberConfig added}) addMember(TeamProfile team) {
    final id = uniqueMemberSlug(team, TeamMemberNaming.defaultWorkerName);
    final now = DateTime.now().millisecondsSinceEpoch;
    final member = TeamMemberConfig(
      id: id,
      name: TeamMemberNaming.defaultWorkerName,
      joinedAt: now,
      activePresetId: TeamProfile.inheritPresetId,
    );
    return (
      team: team.copyWith(members: [...team.members, member]),
      added: member,
    );
  }

  /// Validates and applies an update to the member with [memberId].
  MemberMutation updateMember(
    TeamProfile team,
    String memberId,
    TeamMemberConfig updated,
  ) {
    final error = TeamMemberNaming.validateMemberName(updated.name);
    if (error != null) {
      return MemberMutation.reject(
        error == 'at_sign'
            ? 'Member name cannot contain @.'
            : 'Member name is required.',
      );
    }
    final normalized = normalizeMember(updated);
    return MemberMutation.update(
      team.copyWith(
        members: [
          for (final m in team.members)
            if (m.id == memberId) normalized else m,
        ],
      ),
    );
  }

  /// Validates and removes the member with [memberId] from [team].
  MemberMutation removeMember(TeamProfile team, String memberId) {
    TeamMemberConfig? target;
    for (final m in team.members) {
      if (m.id == memberId) {
        target = m;
        break;
      }
    }
    if (target != null && TeamMemberNaming.isTeamLead(target)) {
      return const MemberMutation.reject(
        'Cannot remove team-lead from the roster.',
      );
    }
    if (team.members.length == 1) {
      return const MemberMutation.reject('A team needs at least one member.');
    }
    final deleted = team.members.firstWhere((m) => m.id == memberId);
    return MemberMutation.update(
      team.copyWith(
        members: team.members
            .where((m) => m.id != memberId)
            .toList(growable: false),
      ),
      statusMessage: 'Deleted ${deleted.name}.',
    );
  }
}
