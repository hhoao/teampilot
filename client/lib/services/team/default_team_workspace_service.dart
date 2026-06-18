import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../utils/workspace_path_utils.dart';
import '../storage/app_storage.dart';

/// Persists the default workspace + first session for a newly created team.
abstract final class DefaultTeamWorkspaceService {
  DefaultTeamWorkspaceService._();

  /// Team-scoped folder: `{cwd}/{teamId}`.
  static String primaryPathForTeam(String teamId) {
    final root = AppStorage.cwd.trim();
    return normalizeWorkspacePath(p.join(root, teamId));
  }

  static Future<void> seed(
    SessionRepository repository,
    TeamProfile team,
  ) async {
    final root = AppStorage.cwd.trim();
    if (root.isEmpty) {
      throw StateError('AppStorage.cwd is empty');
    }

    final primaryPath = primaryPathForTeam(team.id);
    await Directory(primaryPath).create(recursive: true);
    final workspace = await repository.createWorkspace(
      primaryPath,
      display: team.name,
    );
    await repository.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
  }
}
