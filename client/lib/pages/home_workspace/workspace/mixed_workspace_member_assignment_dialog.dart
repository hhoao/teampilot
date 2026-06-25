import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';

/// Mixed workspaces require complete member→machine pins on the session snapshot
/// taken at creation. Assignment is configured on the workspace + team, not per
/// session after the fact.
Future<AppSession?> ensureMixedWorkspaceMemberAssignments(
  BuildContext context, {
  required Workspace workspace,
  required AppSession session,
  required TeamProfile team,
  required SessionRepository repository,
}) async {
  if (!workspaceTopologyRequiresMemberAssignment(workspace.folders)) {
    return _reloadSession(repository, session);
  }
  final current = await _reloadSession(repository, session);
  if (memberTargetsComplete(
    workspaceFolders: workspace.folders,
    members: team.members,
    targets: current.memberTargets,
  )) {
    return current;
  }
  if (!context.mounted) return null;
  AppToast.show(
    context,
    message: context.l10n.mixedWorkspaceSessionLaunchBlocked,
    variant: AppToastVariant.warning,
  );
  return null;
}

Future<AppSession> _reloadSession(
  SessionRepository repository,
  AppSession session,
) async {
  final fresh = (await repository.loadSessions())
      .where((s) => s.sessionId == session.sessionId)
      .firstOrNull;
  return fresh ?? session;
}

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