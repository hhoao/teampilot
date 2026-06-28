import 'package:collection/collection.dart';

import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
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
  /// Returns whether storage was mutated. Pass [knownWorkspaces] when the index
  /// was just loaded to avoid a second full scan.
  static Future<bool> ensureDefault(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    String personalIdentityId = LaunchProfileProvisioner.defaultPersonalId,
    List<Workspace>? knownWorkspaces,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    final workspaces = knownWorkspaces ?? await repository.loadWorkspaces();
    var workspace = workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .firstOrNull;

    var mutated = false;
    if (workspace == null) {
      workspace = await repository.createWorkspace(
        [WorkspaceFolder(path: primaryPath)],
        display: defaultDisplay,
      );
      mutated = true;
    }

    final trimmedPersonalId = personalIdentityId.trim();
    if (trimmedPersonalId.isNotEmpty &&
        workspace.defaultProfileId.trim().isEmpty) {
      await repository.updateWorkspaceMetadata(
        workspace.workspaceId,
        defaultProfileId: trimmedPersonalId,
      );
      workspace = workspace.copyWith(defaultProfileId: trimmedPersonalId);
      mutated = true;
    }

    final workspaceSessions = await repository.loadSessionsForWorkspace(
      workspace.workspaceId,
    );

    final hasPersonal = workspaceSessions.any((s) => s.sessionTeam.isEmpty);
    if (!hasPersonal) {
      await repository.createSession(
        workspace.workspaceId,
        personalIdentityId: trimmedPersonalId,
      );
      mutated = true;
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
      mutated = true;
    }

    return mutated;
  }

  /// Idempotent — safe to call on every bootstrap.
  static Future<Workspace> seed(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    String personalIdentityId = LaunchProfileProvisioner.defaultPersonalId,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    await ensureDefault(
      repository,
      defaultTeam: defaultTeam,
      personalIdentityId: personalIdentityId,
    );
    final workspaces = await repository.loadWorkspaces();
    return workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .first;
  }
}
