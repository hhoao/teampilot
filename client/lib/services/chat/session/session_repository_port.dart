import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';

/// Persistence seam for the launch flow.
abstract interface class SessionRepositoryPort {
  SessionRepository? get sessionRepository;

  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  );

  Future<void> loadWorkspaceData(SessionRepository repo);

  Future<TeamProfile?> teamProfileById(String teamId);
}
