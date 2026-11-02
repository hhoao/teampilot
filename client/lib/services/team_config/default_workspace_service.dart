import 'package:collection/collection.dart';

import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/session_repository.dart';
import '../chat/launch/session/session_member_cli_locks.dart';
import '../storage/app_paths.dart';
import '../storage/home_storage.dart';
import '../storage/work_target_canonicalizer.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../expert_hub/expert_hub_catalog.dart';
import '../expert_hub/expert_member_materializer.dart';

/// First-launch bootstrap for the built-in workspace and starter sessions.
///
/// Workspaces and launch identities (team) are otherwise independent:
/// creating a team does not create a workspace.
abstract final class DefaultWorkspaceService {
  DefaultWorkspaceService._();

  static const defaultDisplay = 'Default';

  /// Built-in personal workspace folder.
  ///
  /// Local home: `<Documents>/TeamPilot`. SSH/WSL home: `$HOME/TeamPilot` on
  /// the bound home work plane ([HomeStorage.home]).
  static Future<String> resolvePrimaryPath({
    RuntimeTarget? home,
    required HomeStorage storage,
  }) async {
    final resolved = home ?? RuntimeTarget.local();
    if (resolved.kind == RuntimeKind.local) {
      return DefaultWorkspaceDirectory.resolveDefaultWorkspacePath();
    }
    final pathCtx = AppPaths.pathContextForDataRoot(storage.home);
    final path = pathCtx.join(storage.home, 'TeamPilot');
    await storage.fs.ensureDir(path);
    // SSH / WSL / Termux folder paths are POSIX even when the host is Windows
    // (tests and WSL-stub homes may still be `C:\...` directories).
    return normalizeWorkspacePath(path, usesPosixPaths: true);
  }

  /// Ensures the default workspace exists with Simple + team launch sessions.
  /// Returns whether storage was mutated. Pass [knownWorkspaces] when the index
  /// was just loaded to avoid a second full scan.
  static Future<bool> ensureDefault(
    SessionRepository repository, {
    required TeamProfile defaultTeam,
    required HomeStorage storage,
    List<Workspace>? knownWorkspaces,
    RuntimeTarget? home,
    ExpertHubCatalog? catalog,
  }) async {
    final primaryPath = await resolvePrimaryPath(home: home, storage: storage);
    final resolvedHome = home ?? RuntimeTarget.local();
    final folderTargetId = WorkTargetCanonicalizer.defaultFolderTargetId(
      resolvedHome,
    );
    final workspaces = knownWorkspaces ?? await repository.loadWorkspaces();
    var workspace = workspaces
        .where(
          (w) => workspacePathsEqual(
            w.firstFolderPath,
            primaryPath,
            usesPosixPaths: storage.usesPosixPaths,
          ),
        )
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
      final List<TeamMemberConfig> rosterMembers;
      if (defaultTeam.members.isNotEmpty) {
        rosterMembers = defaultTeam.members;
      } else if (catalog != null) {
        rosterMembers = ExpertMemberMaterializer.materializeTeam(
          defaultTeam,
          await catalog.snapshot(),
        ).members;
      } else {
        rosterMembers = const [];
      }
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
    required HomeStorage storage,
    RuntimeTarget? home,
    ExpertHubCatalog? catalog,
  }) async {
    final primaryPath = await resolvePrimaryPath(home: home, storage: storage);
    await ensureDefault(
      repository,
      defaultTeam: defaultTeam,
      storage: storage,
      home: home,
      catalog: catalog,
    );
    final workspaces = await repository.loadWorkspaces();
    return workspaces
        .where(
          (w) => workspacePathsEqual(
            w.firstFolderPath,
            primaryPath,
            usesPosixPaths: storage.usesPosixPaths,
          ),
        )
        .first;
  }
}
