import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../utils/team/team_member_naming.dart';

class PreparedMemberPlacementSave {
  const PreparedMemberPlacementSave({
    required this.team,
    required this.members,
    required this.targets,
    required this.leadValid,
    required this.markInitialized,
  });

  /// Team with [TeamProfile.roster] overrides updated from placement totals.
  final TeamProfile team;

  /// Runtime members with placement-driven [TeamMemberConfig.replicas].
  final List<TeamMemberConfig> members;
  final MemberTargetAssignments targets;
  final bool leadValid;
  final bool markInitialized;
}

/// Applies placement counts to runtime members **and** persisted roster slots.
PreparedMemberPlacementSave prepareMemberPlacementSave({
  required TeamProfile team,
  required List<WorkspaceFolder> folders,
  required MemberPlacementByTarget placement,
}) {
  final members = applyPlacementReplicasToMembers(
    members: team.members,
    placement: placement,
  );
  final targets = memberTargetsFromMemberPlacement(
    workspaceFolders: folders,
    members: members,
    placement: placement,
  );
  final roster = applyPlacementReplicasToRoster(
    roster: team.roster,
    members: members,
  );
  return PreparedMemberPlacementSave(
    team: team.copyWith(roster: roster, members: members),
    members: members,
    targets: targets,
    leadValid: leadPlacementValid(
      folders: folders,
      members: members,
      targets: targets,
    ),
    markInitialized: true,
  );
}

/// Copies placement-driven replica counts onto matching [roster] slot overrides.
List<TeamRosterSlot> applyPlacementReplicasToRoster({
  required List<TeamRosterSlot> roster,
  required List<TeamMemberConfig> members,
}) {
  if (roster.isEmpty) return roster;
  final byId = {for (final m in members) m.id: m};
  return [
    for (final slot in roster)
      slot.copyWith(
        overrides: slot.overrides.copyWith(
          replicas: TeamMemberNaming.isTeamLeadName(slot.id)
              ? 1
              : (byId[slot.id]?.replicas ?? slot.overrides.replicas),
        ),
      ),
  ];
}
