import 'package:equatable/equatable.dart';

import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/project_icon_ref.dart';
import '../../models/team_config.dart' show CliTool, TeamMemberConfig;
import '../../repositories/project_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../utils/project_path_utils.dart';

class ChatDataSnapshot extends Equatable {
  const ChatDataSnapshot({
    required this.projects,
    required this.sessions,
    required this.visibleProjects,
    required this.visibleSessions,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final List<AppProject> visibleProjects;
  final List<AppSession> visibleSessions;

  @override
  List<Object?> get props =>
      [projects, sessions, visibleProjects, visibleSessions];
}

/// Owns team-scope flags and wraps SessionRepository. Returns snapshots;
/// ChatCubit emits them (single emit owner).
class SessionDataStore {
  bool _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;

  bool setScope({
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    final normalized = (selectedTeamId != null && selectedTeamId.isNotEmpty)
        ? selectedTeamId
        : null;
    if (_scopeSessionsToSelectedTeam == scopeSessionsToSelectedTeam &&
        _selectedTeamId == normalized) {
      return false;
    }
    _scopeSessionsToSelectedTeam = scopeSessionsToSelectedTeam;
    _selectedTeamId = normalized;
    return true;
  }

  List<AppSession> _computeVisibleSessions(List<AppSession> all) {
    if (!_scopeSessionsToSelectedTeam) return all;
    final tid = _selectedTeamId;
    if (tid == null || tid.isEmpty) {
      return all.where((s) => s.sessionTeam.isEmpty).toList();
    }
    return all.where((s) => s.sessionTeam == tid).toList();
  }

  List<AppProject> _computeVisibleProjects(List<AppProject> all) => all;

  ChatDataSnapshot deriveSnapshot({
    required List<AppProject> projects,
    required List<AppSession> sessions,
  }) {
    final visS = _computeVisibleSessions(sessions);
    final visP = _computeVisibleProjects(projects);
    return ChatDataSnapshot(
      projects: projects,
      sessions: sessions,
      visibleProjects: visP,
      visibleSessions: visS,
    );
  }

  Future<ChatDataSnapshot> loadProjectData(SessionRepository repo) async {
    final projects = await repo.loadProjects();
    final sessions = await repo.loadSessions();
    return deriveSnapshot(projects: projects, sessions: sessions);
  }

  Future<AppSession> createSession(
    String projectId,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
  }) {
    return repo.createSession(
      projectId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
      cli: cli,
    );
  }

  Future<({String projectId, ChatDataSnapshot snapshot})>
  createProjectWithFirstSession(
    String primaryPath,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    List<String> additionalPaths = const [],
    String display = '',
    ProjectProfileRepository? projectProfileRepository,
  }) async {
    final project = await repo.createProject(
      primaryPath,
      additionalPaths: additionalPaths,
      display: display,
    );
    if (projectProfileRepository != null) {
      final profile = await projectProfileRepository.createDefault(
        project.projectId,
      );
      await projectProfileRepository.save(profile);
    }
    await repo.createSession(
      project.projectId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
    );
    final snapshot = await loadProjectData(repo);
    return (projectId: project.projectId, snapshot: snapshot);
  }

  Future<ChatDataSnapshot?> addProjectDirectory(
    SessionRepository repo,
    AppProject project,
    String directoryPath,
  ) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) return null;
    if (projectPathsEqual(trimmed, project.primaryPath)) return null;
    if (projectPathsContains(project.additionalPaths, trimmed)) return null;
    await repo.createProject(
      project.primaryPath,
      additionalPaths: [trimmed],
    );
    return loadProjectData(repo);
  }

  Future<ChatDataSnapshot> updateProjectMetadata(
    SessionRepository repo,
    String projectId, {
    String? display,
    List<String>? additionalPaths,
  }) async {
    await repo.updateProjectMetadata(
      projectId,
      display: display,
      additionalPaths: additionalPaths,
    );
    return loadProjectData(repo);
  }

  Future<ChatDataSnapshot> applyProjectIcon(
    SessionRepository repo,
    String projectId,
    ProjectIconRef icon,
  ) async {
    await repo.applyProjectIcon(projectId, icon);
    return loadProjectData(repo);
  }

  Future<ChatDataSnapshot> importCustomProjectIcon(
    SessionRepository repo,
    String projectId,
    String localSourcePath,
  ) async {
    await repo.importCustomProjectIcon(projectId, localSourcePath);
    return loadProjectData(repo);
  }

  Future<ChatDataSnapshot> deleteSessionRecord(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.deleteSession(sessionId);
    return loadProjectData(repo);
  }

  Future<ChatDataSnapshot> deleteProjectRecord(
    SessionRepository repo,
    String projectId,
  ) async {
    await repo.deleteProject(projectId);
    return loadProjectData(repo);
  }

  Future<({AppProject project, ChatDataSnapshot snapshot})> cloneProject(
    SessionRepository repo,
    String sourceProjectId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final project = await repo.cloneProject(
      sourceProjectId,
      display: display,
      rosterMembers: rosterMembers,
    );
    final snapshot = await loadProjectData(repo);
    return (project: project, snapshot: snapshot);
  }
}
