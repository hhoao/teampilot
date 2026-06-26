import 'package:collection/collection.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';

/// Returns a fresh session snapshot when launch may proceed, or `null` when
/// mixed-workspace member targets are incomplete.
Future<AppSession?> ensureSessionLaunchReady({
  required Workspace workspace,
  required AppSession session,
  required TeamProfile team,
  required SessionRepository repository,
}) async {
  if (!workspaceTopologyRequiresMemberAssignment(workspace.folders)) {
    // Remote / local / pure-SSH workspaces: in-memory session is authoritative.
    return session;
  }
  if (memberTargetsComplete(
    workspaceFolders: workspace.folders,
    members: team.members,
    targets: session.memberTargets,
  )) {
    return session;
  }
  // Mixed topology with stale sidebar snapshot — reload once from disk.
  final current = await _reloadSession(repository, session);
  if (memberTargetsComplete(
    workspaceFolders: workspace.folders,
    members: team.members,
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
