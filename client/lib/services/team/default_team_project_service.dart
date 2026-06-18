import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../utils/project_path_utils.dart';
import '../storage/app_storage.dart';

/// Persists the default project + first session for a newly created team.
abstract final class DefaultTeamProjectService {
  DefaultTeamProjectService._();

  /// Team-scoped folder: `{cwd}/{teamId}`.
  static String primaryPathForTeam(String teamId) {
    final root = AppStorage.cwd.trim();
    return normalizeProjectPath(p.join(root, teamId));
  }

  static Future<void> seed(
    SessionRepository repository,
    TeamIdentity team,
  ) async {
    final root = AppStorage.cwd.trim();
    if (root.isEmpty) {
      throw StateError('AppStorage.cwd is empty');
    }

    final primaryPath = primaryPathForTeam(team.id);
    await Directory(primaryPath).create(recursive: true);
    final project = await repository.createProject(
      primaryPath,
      display: team.name,
    );
    await repository.createSession(
      project.projectId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
  }
}
