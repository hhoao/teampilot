import 'package:equatable/equatable.dart';

import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/workspace_icon_ref.dart';
import '../../models/team_config.dart' show CliTool, TeamMemberConfig;
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../utils/workspace_path_utils.dart';

class ChatDataSnapshot extends Equatable {
  const ChatDataSnapshot({
    required this.workspaces,
    required this.sessions,
    required this.visibleWorkspaces,
    required this.visibleSessions,
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final List<Workspace> visibleWorkspaces;
  final List<AppSession> visibleSessions;

  @override
  List<Object?> get props =>
      [workspaces, sessions, visibleWorkspaces, visibleSessions];
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

  List<Workspace> _computeVisibleWorkspaces(List<Workspace> all) => all;

  ChatDataSnapshot deriveSnapshot({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) {
    final visS = _computeVisibleSessions(sessions);
    final visP = _computeVisibleWorkspaces(workspaces);
    return ChatDataSnapshot(
      workspaces: workspaces,
      sessions: sessions,
      visibleWorkspaces: visP,
      visibleSessions: visS,
    );
  }

  Future<ChatDataSnapshot> loadWorkspaceData(SessionRepository repo) async {
    final workspaces = await repo.loadWorkspaces();
    final sessions = await repo.loadSessions();
    return deriveSnapshot(workspaces: workspaces, sessions: sessions);
  }

  Future<AppSession> createSession(
    String workspaceId,
    SessionRepository repo, {
    String sessionTeamId = '',
    String personalIdentityId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
  }) {
    return repo.createSession(
      workspaceId,
      sessionTeam: sessionTeamId,
      personalIdentityId: personalIdentityId,
      rosterMembers: rosterMembers,
      cli: cli,
    );
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})>
  createWorkspaceWithFirstSession(
    String primaryPath,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    List<String> additionalPaths = const [],
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final workspace = await repo.createWorkspace(
      primaryPath,
      additionalPaths: additionalPaths,
      display: display,
      allowDuplicate: allowDuplicate,
    );
    await repo.createSession(
      workspace.workspaceId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
    );
    final snapshot = await loadWorkspaceData(repo);
    return (workspaceId: workspace.workspaceId, snapshot: snapshot);
  }

  Future<ChatDataSnapshot?> addWorkspaceDirectory(
    SessionRepository repo,
    Workspace workspace,
    String directoryPath,
  ) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) return null;
    if (workspacePathsEqual(trimmed, workspace.primaryPath)) return null;
    if (workspacePathsContains(workspace.additionalPaths, trimmed)) return null;
    await repo.createWorkspace(
      workspace.primaryPath,
      additionalPaths: [trimmed],
    );
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    List<String>? additionalPaths,
  }) async {
    await repo.updateWorkspaceMetadata(
      workspaceId,
      display: display,
      defaultProfileId: defaultProfileId,
      additionalPaths: additionalPaths,
    );
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> applyWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    await repo.applyWorkspaceIcon(workspaceId, icon);
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> importCustomWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    await repo.importCustomWorkspaceIcon(workspaceId, localSourcePath);
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> deleteSessionRecord(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.deleteSession(sessionId);
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> deleteWorkspaceRecord(
    SessionRepository repo,
    String workspaceId,
  ) async {
    await repo.deleteWorkspace(workspaceId);
    return loadWorkspaceData(repo);
  }

  Future<({Workspace workspace, ChatDataSnapshot snapshot})> cloneWorkspace(
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final workspace = await repo.cloneWorkspace(
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    final snapshot = await loadWorkspaceData(repo);
    return (workspace: workspace, snapshot: snapshot);
  }
}
