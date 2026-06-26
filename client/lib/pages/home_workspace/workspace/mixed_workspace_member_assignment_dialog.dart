import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';

/// Throws [StateError] when a team session cannot be created yet.
void assertMixedWorkspaceTeamTargetsReady({
  required Workspace workspace,
  required String teamId,
  required List<TeamMemberConfig> rosterMembers,
}) {
  if (!workspaceTopologyRequiresMemberAssignment(workspace.folders)) return;
  final trimmedTeam = teamId.trim();
  if (trimmedTeam.isEmpty) return;
  final targets = rememberedMemberTargets(
    workspace.memberTargetsByTeam,
    trimmedTeam,
  );
  if (!memberTargetsComplete(
    workspaceFolders: workspace.folders,
    members: rosterMembers,
    targets: targets,
  )) {
    throw StateError('mixed_workspace_member_targets_incomplete');
  }
}