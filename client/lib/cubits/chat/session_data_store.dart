import 'package:collection/collection.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_member_binding.dart';
import '../../models/workspace_icon_ref.dart';
import '../../models/team_config.dart' show CliTool, TeamMemberConfig, TeamProfile;
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/catalog/workspace_catalog.dart' show ChatDataSnapshot;
import '../../services/session/session_member_cli_locks.dart';
import '../../utils/logging/logger.dart';
import '../../utils/workspace/workspace_path_utils.dart';

export '../../services/catalog/workspace_catalog.dart' show ChatDataSnapshot;

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

  /// Stable createdAt-desc sort: equal createdAt keeps input order.
  static List<String> sortedSessionIdsByCreatedAt(
    Iterable<AppSession> sessions,
  ) {
    final indexed = <({AppSession session, int index})>[];
    var index = 0;
    for (final session in sessions) {
      indexed.add((session: session, index: index));
      index++;
    }
    indexed.sort((a, b) {
      final byCreated = b.session.createdAt.compareTo(a.session.createdAt);
      return byCreated != 0 ? byCreated : a.index.compareTo(b.index);
    });
    return [for (final e in indexed) e.session.sessionId];
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
    final normalizedWorkspaceId = workspaceId.trim();
    final ownedSessions = workspaceSessions
        .where((session) => session.workspaceId == normalizedWorkspaceId)
        .toList();
    _hydratedSessionWorkspaceIds.add(normalizedWorkspaceId);
    final others = [
      for (final session in current.sessions)
        if (session.workspaceId != normalizedWorkspaceId) session,
    ];
    final workspaces = [
      for (final workspace in current.workspaces)
        if (workspace.workspaceId == normalizedWorkspaceId)
          workspace.copyWith(
            sessionIds: sortedSessionIdsByCreatedAt(ownedSessions),
          )
        else
          workspace,
    ];
    return deriveSnapshot(
      workspaces: workspaces,
      sessions: [...others, ...ownedSessions],
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
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    CliTool? cli,
    String? workingDirectory,
    String? fixedSessionId,
    List<SessionMemberBinding>? members,
    Map<String, String>? memberTargets,
  }) async {
    return (await repo.createSession(
      workspaceId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: memberClis,
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
      members: members,
      memberTargets: memberTargets,
    ))
        .session;
  }

  ChatDataSnapshot appendSession(ChatDataSnapshot base, AppSession session) {
    final alreadyPresent =
        base.sessions.any((s) => s.sessionId == session.sessionId);
    return deriveSnapshot(
      workspaces: [
        for (final workspace in base.workspaces)
          if (workspace.workspaceId == session.workspaceId)
            _withInsertedSessionId(base, workspace, session)
          else
            workspace,
      ],
      sessions: alreadyPresent ? base.sessions : [...base.sessions, session],
    );
  }

  Workspace _withInsertedSessionId(
    ChatDataSnapshot base,
    Workspace workspace,
    AppSession session,
  ) {
    if (workspace.sessionIds.contains(session.sessionId)) return workspace;
    final workspaceSessions = [
      for (final s in base.sessions)
        if (s.workspaceId == workspace.workspaceId) s,
      session,
    ];
    return workspace.copyWith(
      sessionIds: sortedSessionIdsByCreatedAt(workspaceSessions),
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
      workspaces: [
        for (final workspace in base.workspaces)
          if (workspace.sessionIds.contains(sessionId))
            workspace.copyWith(
              sessionIds: [
                for (final id in workspace.sessionIds)
                  if (id != sessionId) id,
              ],
            )
          else
            workspace,
      ],
      sessions: [
        for (final s in base.sessions)
          if (s.sessionId != sessionId) s,
      ],
    );
  }

  /// Replaces [updated] in the snapshot; keeps the current snapshot's
  /// sessionIds (in-memory maintenance is the source of truth for order).
  ChatDataSnapshot snapshotWithWorkspace(
    ChatDataSnapshot base,
    Workspace updated,
  ) {
    final existing = base.workspaces
        .where((w) => w.workspaceId == updated.workspaceId)
        .firstOrNull;
    final withIds = existing != null
        ? updated.copyWith(sessionIds: existing.sessionIds)
        : updated;
    final replaced = existing == null
        ? [...base.workspaces, withIds]
        : [
            for (final w in base.workspaces)
              if (w.workspaceId == updated.workspaceId) withIds else w,
          ];
    return deriveSnapshot(workspaces: replaced, sessions: base.sessions);
  }

  /// Replaces [workspace] and every session it owns with [sessions];
  /// sessionIds are rebuilt from [sessions] (createdAt desc).
  ChatDataSnapshot snapshotWithWorkspaceAndSessions(
    ChatDataSnapshot base, {
    required Workspace workspace,
    required List<AppSession> sessions,
  }) {
    final withIds = workspace.copyWith(
      sessionIds: sortedSessionIdsByCreatedAt(
        sessions.where((s) => s.workspaceId == workspace.workspaceId),
      ),
    );
    final replaced = [
      for (final w in base.workspaces)
        if (w.workspaceId == workspace.workspaceId) withIds else w,
    ];
    if (!base.workspaces.any((w) => w.workspaceId == workspace.workspaceId)) {
      replaced.add(withIds);
    }
    return deriveSnapshot(
      workspaces: replaced,
      sessions: [
        for (final s in base.sessions)
          if (s.workspaceId != workspace.workspaceId) s,
        ...sessions,
      ],
    );
  }

  ChatDataSnapshot snapshotWithoutWorkspace(
    ChatDataSnapshot base,
    String workspaceId,
  ) {
    return deriveSnapshot(
      workspaces: [
        for (final w in base.workspaces)
          if (w.workspaceId != workspaceId) w,
      ],
      sessions: [
        for (final s in base.sessions)
          if (s.workspaceId != workspaceId) s,
      ],
    );
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})>
  createWorkspaceWithFirstSession(
    ChatDataSnapshot base,
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final workspace = await repo.createWorkspace(
      folders,
      display: display,
    );
    final trimmedTeam = sessionTeamId.trim();
    final resolvedClis = trimmedTeam.isEmpty
        ? const <String, CliTool>{}
        : memberClis.isNotEmpty
        ? memberClis
        : team != null
        ? resolveSessionMemberCliLocks(
            team: team,
            rosterMembers: rosterMembers,
            globalPresets: globalPresets,
          )
        : throw ArgumentError(
            'Team session create requires memberClis or team',
          );
    var snapshot = snapshotWithWorkspace(base, workspace);
    final created = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: resolvedClis,
    );
    snapshot = appendSession(snapshot, created.session);
    snapshot = snapshotWithWorkspace(snapshot, created.workspace);
    return (workspaceId: workspace.workspaceId, snapshot: snapshot);
  }

  Future<ChatDataSnapshot?> addWorkspaceDirectory(
    ChatDataSnapshot base,
    SessionRepository repo,
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    if (folder.path.trim().isEmpty) return null;
    if (workspacePathsEqual(folder.path, workspace.firstFolderPath)) {
      return null;
    }
    if (workspace.folders.any(
      (f) => workspacePathsEqual(f.path, folder.path),
    )) {
      return null;
    }
    final updated = await repo.updateWorkspaceFolders(workspace.workspaceId, [
      ...workspace.folders,
      folder.copyWith(path: normalizeWorkspacePath(folder.path)),
    ]);
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> updateWorkspaceMetadata(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
  }) async {
    final updated = await repo.updateWorkspaceMetadata(
      workspaceId,
      display: display,
      defaultProfileId: defaultProfileId,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn,
    );
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> applyWorkspaceIcon(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final updated = await repo.applyWorkspaceIcon(workspaceId, icon);
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> importCustomWorkspaceIcon(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    final updated = await repo.importCustomWorkspaceIcon(
      workspaceId,
      localSourcePath,
    );
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot> deleteSessionRecord(
    ChatDataSnapshot base,
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.deleteSession(sessionId);
    return removeSession(base, sessionId);
  }

  Future<ChatDataSnapshot> deleteWorkspaceRecord(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
  ) async {
    await repo.deleteWorkspace(workspaceId);
    return snapshotWithoutWorkspace(base, workspaceId);
  }

  Future<({Workspace workspace, ChatDataSnapshot snapshot})> cloneWorkspace(
    ChatDataSnapshot base,
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await repo.cloneWorkspace(
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    return (
      workspace: result.workspace,
      snapshot: snapshotWithWorkspaceAndSessions(
        base,
        workspace: result.workspace,
        sessions: result.sessions,
      ),
    );
  }
}
