import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';

/// Pre-flight checks before surfacing a session tab.
SessionOpenStatus? validateSessionOpenRequest({
  required SessionOpenRequest request,
  required AppSession session,
  required Workspace? Function(String workspaceId) workspaceById,
}) {
  if (request.isPersonal) {
    final workspace = request.workspace ?? workspaceById(session.workspaceId);
    if (workspace == null) return SessionOpenStatus.missingWorkspace;
  } else if (request.team == null || request.member == null) {
    return SessionOpenStatus.missingTeamMember;
  } else {
    final workspace = request.workspace ?? workspaceById(session.workspaceId);
    final team = request.team!;
    if (workspace != null &&
        workspaceTopologyRequiresMemberAssignment(workspace.folders) &&
        !memberTargetsComplete(
          workspaceFolders: workspace.folders,
          members: team.members.where((m) => m.isValid).toList(),
          targets: session.memberTargets,
        )) {
      return SessionOpenStatus.blockedMixedMemberTargets;
    }
  }
  return null;
}
