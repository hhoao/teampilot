import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../utils/workspace_path_utils.dart';

/// Read-only workspace/session lookups for the launch flow.
class SessionLaunchWorkspaceIndex {
  SessionLaunchWorkspaceIndex({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) : _workspaces = workspaces,
       _sessions = sessions;

  final List<Workspace> _workspaces;
  final List<AppSession> _sessions;

  Workspace? byId(String workspaceId) {
    for (final workspace in _workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  Workspace? matchingPath(String primaryPath) {
    for (final workspace in _workspaces) {
      if (workspacePathsEqual(workspace.firstFolderPath, primaryPath)) {
        return workspace;
      }
    }
    return null;
  }

  AppSession? firstForWorkspaceAndTeam(String workspaceId, String teamId) {
    for (final session in _sessions) {
      if (session.workspaceId != workspaceId) continue;
      if (session.sessionTeam.trim() != teamId) continue;
      return session;
    }
    return null;
  }

  AppSession? firstForPersonalWorkspace(String workspaceId) =>
      firstForWorkspaceAndTeam(workspaceId, '');

  AppSession? existingTeamSessionForMaterialize({
    required TeamProfile team,
    String? workspaceCwd,
  }) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      final workspace = matchingPath(workspaceCwd);
      if (workspace != null) {
        final session = firstForWorkspaceAndTeam(workspace.workspaceId, team.id);
        if (session != null) return session;
      }
    }
    for (final session in _sessions) {
      if (session.sessionTeam.trim() != team.id) continue;
      return session;
    }
    return null;
  }

  /// Legacy tab keys appended `\x1e<launchProfileId>`; strip suffix if present.
  static String workspaceIdFromBucketKey(String bucketKey) {
    const sep = '\x1e';
    final idx = bucketKey.indexOf(sep);
    if (idx < 0) return bucketKey;
    return bucketKey.substring(0, idx);
  }

  static String? resolveWorkspaceCwd({
    String? explicitCwd,
    required String activeBucketKey,
    required SessionLaunchWorkspaceIndex index,
  }) {
    final explicit = explicitCwd?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final bucketKey = activeBucketKey.trim();
    if (bucketKey.isEmpty) return null;
    final workspaceId = workspaceIdFromBucketKey(bucketKey);
    return index.byId(workspaceId)?.firstFolderPath;
  }
}
