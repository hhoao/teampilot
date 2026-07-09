import 'package:collection/collection.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';

/// Returns a fresh session snapshot when launch may proceed, or `null` when
/// mixed placement is uninitialized or lead host placement is invalid.
Future<AppSession?> ensureSessionLaunchReady({
  required Workspace workspace,
  required AppSession session,
  required TeamProfile team,
  required SessionRepository repository,
}) async {
  if (workspaceNeedsMixedPlacementInit(
    folders: workspace.folders,
    teamId: team.id,
    initializedByTeam: workspace.memberPlacementInitializedByTeam,
  )) {
    return null;
  }

  final validMembers = team.members.where((m) => m.isValid).toList();
  final mustValidateLead =
      session.memberTargets.isNotEmpty ||
      workspaceTopologyOf(workspace.folders) == WorkspaceTopology.mixed;
  if (!mustValidateLead) {
    return session;
  }
  if (leadPlacementValid(
    folders: workspace.folders,
    members: validMembers,
    targets: session.memberTargets,
  )) {
    return session;
  }
  // Mixed / pinned topology with stale sidebar snapshot — reload once from disk.
  final current = await _reloadSession(repository, session);
  if (leadPlacementValid(
    folders: workspace.folders,
    members: validMembers,
    targets: current.memberTargets,
  )) {
    return current;
  }
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
