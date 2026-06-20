import 'package:collection/collection.dart';

import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../utils/workspace_path_utils.dart';

/// First-launch bootstrap for the built-in workspace and starter sessions.
///
/// Workspaces and launch identities (personal / team) are otherwise independent:
/// creating a team does not create a workspace.
abstract final class DefaultWorkspaceService {
  DefaultWorkspaceService._();

  static const defaultDisplay = 'Default';

  /// Built-in personal workspace folder: `<Documents>/TeamPilot`.
  static Future<String> resolvePrimaryPath() =>
      DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();

  /// Ensures the default workspace exists with personal + team launch sessions.
  /// Idempotent — safe to call on every bootstrap.
  static Future<Workspace> seed(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    String personalIdentityId = LaunchProfileProvisioner.defaultPersonalId,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    final workspaces = await repository.loadWorkspaces();
    var workspace = workspaces
        .where((w) => workspacePathsEqual(w.primaryPath, primaryPath))
        .firstOrNull;

    workspace ??= await repository.createWorkspace(
      primaryPath,
      display: defaultDisplay,
    );

    final trimmedPersonalId = personalIdentityId.trim();
    if (trimmedPersonalId.isNotEmpty &&
        workspace.defaultProfileId.trim().isEmpty) {
      await repository.updateWorkspaceMetadata(
        workspace.workspaceId,
        defaultProfileId: trimmedPersonalId,
      );
      workspace = workspace.copyWith(defaultProfileId: trimmedPersonalId);
    }

    final sessions = await repository.loadSessions();
    final workspaceSessions = sessions
        .where((s) => s.workspaceId == workspace!.workspaceId)
        .toList();

    final hasPersonal = workspaceSessions.any((s) => s.sessionTeam.isEmpty);
    if (!hasPersonal) {
      await repository.createSession(
        workspace.workspaceId,
        personalIdentityId: trimmedPersonalId,
      );
    }

    final hasTeam = workspaceSessions.any(
      (s) => s.sessionTeam.trim() == defaultTeam.id,
    );
    if (!hasTeam) {
      await repository.createSession(
        workspace.workspaceId,
        sessionTeam: defaultTeam.id,
        rosterMembers: defaultTeam.members,
      );
    }

    return workspace;
  }
}
