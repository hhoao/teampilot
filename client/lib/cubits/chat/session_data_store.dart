import 'package:equatable/equatable.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/workspace_icon_ref.dart';
import '../../models/team_config.dart' show CliTool, TeamMemberConfig;
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../utils/logger.dart';
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
  final Set<String> _hydratedSessionWorkspaceIds = {};

  void _resetSessionHydration() => _hydratedSessionWorkspaceIds.clear();

  void _markAllWorkspacesHydrated(Iterable<String> workspaceIds) {
    _hydratedSessionWorkspaceIds
      ..clear()
      ..addAll(workspaceIds);
  }

  void markWorkspacesSessionsHydrated(Iterable<String> workspaceIds) {
    _hydratedSessionWorkspaceIds.addAll(
      workspaceIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    );
  }

  bool sessionsLoadedForWorkspace(String workspaceId) =>
      _hydratedSessionWorkspaceIds.contains(workspaceId.trim());

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

  Future<ChatDataSnapshot> loadWorkspaceIndex(SessionRepository repo) async {
    final sw = Stopwatch()..start();
    _resetSessionHydration();
    final workspaces = await repo.loadWorkspacesIndex();
    appLogger.i(
      '[boot] SessionDataStore.loadWorkspaceIndex '
      '${workspaces.length} workspaces +${sw.elapsedMilliseconds}ms',
    );
    return deriveSnapshot(workspaces: workspaces, sessions: const []);
  }

  Future<List<AppSession>> loadSessionsForWorkspace(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final sw = Stopwatch()..start();
    final sessions = await repo.loadSessionsForWorkspace(workspaceId);
    appLogger.i(
      '[boot] SessionDataStore.loadSessionsForWorkspace $workspaceId '
      '${sessions.length} sessions +${sw.elapsedMilliseconds}ms',
    );
    return sessions;
  }

  ChatDataSnapshot mergeWorkspaceSessions({
    required ChatDataSnapshot current,
    required String workspaceId,
    required List<AppSession> workspaceSessions,
  }) {
    _hydratedSessionWorkspaceIds.add(workspaceId.trim());
    final others = [
      for (final session in current.sessions)
        if (session.workspaceId != workspaceId) session,
    ];
    return deriveSnapshot(
      workspaces: current.workspaces,
      sessions: [...others, ...workspaceSessions],
    );
  }

  Future<List<AppSession>> loadSessions(SessionRepository repo) async {
    final sw = Stopwatch()..start();
    final sessions = await repo.loadSessions();
    appLogger.i(
      '[boot] SessionDataStore.loadSessions '
      '${sessions.length} sessions +${sw.elapsedMilliseconds}ms',
    );
    return sessions;
  }

  Future<ChatDataSnapshot> loadWorkspaceData(SessionRepository repo) async {
    final sw = Stopwatch()..start();
    final workspaces = await repo.loadWorkspaces();
    final workspacesMs = sw.elapsedMilliseconds;
    final sessions = await repo.loadSessions();
    _markAllWorkspacesHydrated(workspaces.map((w) => w.workspaceId));
    appLogger.i(
      '[boot] SessionDataStore.loadWorkspaceData '
      '${workspaces.length} workspaces (+${workspacesMs}ms) '
      '${sessions.length} sessions (+${sw.elapsedMilliseconds - workspacesMs}ms) '
      'total=${sw.elapsedMilliseconds}ms',
    );
    return deriveSnapshot(workspaces: workspaces, sessions: sessions);
  }

  Future<AppSession> createSession(
    String workspaceId,
    SessionRepository repo, {
    String sessionTeamId = '',
    String personalIdentityId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
    String? workingDirectory,
    String? fixedSessionId,
  }) {
    return repo.createSession(
      workspaceId,
      sessionTeam: sessionTeamId,
      personalIdentityId: personalIdentityId,
      rosterMembers: rosterMembers,
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
    );
  }

  ChatDataSnapshot appendSession(ChatDataSnapshot base, AppSession session) {
    return deriveSnapshot(
      workspaces: base.workspaces,
      sessions: [...base.sessions, session],
    );
  }

  ChatDataSnapshot replaceSession(ChatDataSnapshot base, AppSession session) {
    final sessions = [...base.sessions];
    final index = sessions.indexWhere((s) => s.sessionId == session.sessionId);
    if (index == -1) {
      sessions.add(session);
    } else {
      sessions[index] = session;
    }
    return deriveSnapshot(workspaces: base.workspaces, sessions: sessions);
  }

  ChatDataSnapshot removeSession(ChatDataSnapshot base, String sessionId) {
    return deriveSnapshot(
      workspaces: base.workspaces,
      sessions: [
        for (final s in base.sessions)
          if (s.sessionId != sessionId) s,
      ],
    );
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})>
  createWorkspaceWithFirstSession(
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final workspace = await repo.createWorkspace(
      folders,
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
    WorkspaceFolder folder,
  ) async {
    if (folder.path.trim().isEmpty) return null;
    if (workspacePathsEqual(folder.path, workspace.firstFolderPath)) return null;
    if (workspace.folders.any((f) => workspacePathsEqual(f.path, folder.path))) {
      return null;
    }
    await repo.updateWorkspaceFolders(workspace.workspaceId, [
      ...workspace.folders,
      folder.copyWith(path: normalizeWorkspacePath(folder.path)),
    ]);
    return loadWorkspaceData(repo);
  }

  Future<ChatDataSnapshot> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
  }) async {
    await repo.updateWorkspaceMetadata(
      workspaceId,
      display: display,
      defaultProfileId: defaultProfileId,
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
