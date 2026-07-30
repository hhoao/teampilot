import 'package:collection/collection.dart';

import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/session_repository.dart';
import '../../services/session/session_member_cli_locks.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/work_target_canonicalizer.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../expert_hub/expert_member_materializer.dart';

/// First-launch bootstrap for the built-in workspace and starter sessions.
///
/// Workspaces and launch identities (team) are otherwise independent:
/// creating a team does not create a workspace.
abstract final class DefaultWorkspaceService {
  DefaultWorkspaceService._();

  static const defaultDisplay = 'Default';

  /// Built-in personal workspace folder: `<Documents>/TeamPilot`.
  static Future<String> resolvePrimaryPath() =>
      DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();

  /// Ensures the default workspace exists with Simple + team launch sessions.
  /// Returns whether storage was mutated. Pass [knownWorkspaces] when the index
  /// was just loaded to avoid a second full scan.
  static Future<bool> ensureDefault(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    List<Workspace>? knownWorkspaces,
    RuntimeTarget? home,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    final resolvedHome = home ?? RuntimeTarget.local();
    final folderTargetId =
        WorkTargetCanonicalizer.defaultFolderTargetId(resolvedHome);
    final workspaces = knownWorkspaces ?? await repository.loadWorkspaces();
    var workspace = workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .firstOrNull;

    var mutated = false;
    if (workspace == null) {
      workspace = await repository.createWorkspace([
        WorkspaceFolder(path: primaryPath, targetId: folderTargetId),
      ], display: defaultDisplay);
      mutated = true;
    }

    final workspaceSessions = await repository.loadSessionsForWorkspace(
      workspace.workspaceId,
    );

    final hasSimple = workspaceSessions.any((s) => s.sessionTeam.isEmpty);
    if (!hasSimple) {
      await repository.createSession(workspace.workspaceId);
      mutated = true;
    }

    final hasTeam = workspaceSessions.any(
      (s) => s.sessionTeam.trim() == defaultTeam.id,
    );
    if (!hasTeam) {
      final rosterMembers = defaultTeam.members.isNotEmpty
          ? defaultTeam.members
          : await ExpertMemberMaterializer.materializeRosterAsync(
              team: defaultTeam,
            );
      await repository.createSession(
        workspace.workspaceId,
        sessionTeam: defaultTeam.id,
        rosterMembers: rosterMembers,
        memberClis: resolveSessionMemberCliLocks(
          team: defaultTeam,
          rosterMembers: rosterMembers,
        ),
      );
      mutated = true;
    }

    return mutated;
  }

  /// Idempotent — safe to call on every bootstrap.
  static Future<Workspace> seed(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    RuntimeTarget? home,
  }) async {
    final primaryPath = await resolvePrimaryPath();
    await ensureDefault(repository, defaultTeam: defaultTeam, home: home);
    final workspaces = await repository.loadWorkspaces();
    return workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primaryPath))
        .first;
  }
}
