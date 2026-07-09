import '../../models/team_config.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';

class PreparedMemberPlacementSave {
  const PreparedMemberPlacementSave({
    required this.members,
    required this.targets,
    required this.leadValid,
    required this.markInitialized,
  });

  final List<TeamMemberConfig> members;
  final MemberTargetAssignments targets;
  final bool leadValid;
  final bool markInitialized;
}

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
  return PreparedMemberPlacementSave(
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
