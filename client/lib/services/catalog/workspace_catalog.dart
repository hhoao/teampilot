import 'package:equatable/equatable.dart';

import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../utils/logging/logger.dart';

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
  List<Object?> get props => [
    workspaces,
    sessions,
    visibleWorkspaces,
    visibleSessions,
  ];
}

/// In-memory workspace/session store with team-scope filtering, snapshot
/// derivation, and per-workspace session hydration on top of [SessionRepository].
class WorkspaceCatalog {
  WorkspaceCatalog(this.repo);

  final SessionRepository repo;

  List<Workspace> _workspaces = [];
  List<AppSession> _sessions = [];
  final Set<String> _hydratedWorkspaceIds = {};
  final Map<String, Future<void>> _hydrationsByWorkspace = {};
  bool _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  List<AppSession> get sessions => List.unmodifiable(_sessions);

  bool sessionsLoadedForWorkspace(String workspaceId) =>
      _hydratedWorkspaceIds.contains(workspaceId.trim());

  Workspace? workspaceById(String workspaceId) {
    final id = workspaceId.trim();
    for (final w in _workspaces) {
      if (w.workspaceId == id) return w;
    }
    return null;
  }

  AppSession? sessionById(String sessionId) {
    final id = sessionId.trim();
    for (final s in _sessions) {
      if (s.sessionId == id) return s;
    }
    return null;
  }

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

  ChatDataSnapshot deriveSnapshot() {
    final visS = _computeVisibleSessions(_sessions);
    final visP = _computeVisibleWorkspaces(_workspaces);
    return ChatDataSnapshot(
      workspaces: List.unmodifiable(_workspaces),
      sessions: List.unmodifiable(_sessions),
      visibleWorkspaces: visP,
      visibleSessions: visS,
    );
  }

  Future<ChatDataSnapshot> loadIndex() async {
    final sw = Stopwatch()..start();
    _hydratedWorkspaceIds.clear();
    _workspaces = List.of(await repo.loadWorkspacesIndex());
    _sessions = [];
    appLogger.i(
      '[catalog] loadIndex ${_workspaces.length} workspaces '
      '+${sw.elapsedMilliseconds}ms',
    );
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> reload() async {
    final sw = Stopwatch()..start();
    _workspaces = List.of(await repo.loadWorkspaces());
    _sessions = List.of(await repo.loadSessions());
    _hydratedWorkspaceIds
      ..clear()
      ..addAll(_workspaces.map((w) => w.workspaceId));
    appLogger.i(
      '[catalog] reload ${_workspaces.length} workspaces '
      '${_sessions.length} sessions +${sw.elapsedMilliseconds}ms',
    );
    return deriveSnapshot();
  }

  Future<List<AppSession>> loadAllSessions() => repo.loadSessions();

  Future<void> ensureSessionsForWorkspace(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty || _hydratedWorkspaceIds.contains(id)) return;
    final inflight = _hydrationsByWorkspace[id];
    if (inflight != null) {
      await inflight;
      return;
    }
    final load = () async {
      final sw = Stopwatch()..start();
      final loaded = await repo.loadSessionsForWorkspace(id);
      _hydratedWorkspaceIds.add(id);
      _sessions = [
        for (final s in _sessions)
          if (s.workspaceId != id) s,
        ...loaded,
      ];
      appLogger.i(
        '[catalog] ensureSessionsForWorkspace $id '
        '${loaded.length} sessions +${sw.elapsedMilliseconds}ms',
      );
    }();
    _hydrationsByWorkspace[id] = load;
    try {
      await load;
    } finally {
      _hydrationsByWorkspace.remove(id);
    }
  }

  Future<List<AppSession>> sessionsForWorkspace(String workspaceId) async {
    await ensureSessionsForWorkspace(workspaceId);
    return [
      for (final s in _sessions)
        if (s.workspaceId == workspaceId.trim()) s,
    ];
  }

  ChatDataSnapshot ingest({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) {
    _workspaces = List.of(workspaces);
    _sessions = List.of(sessions);
    _hydratedWorkspaceIds
      ..clear()
      ..addAll(_workspaces.map((w) => w.workspaceId));
    return deriveSnapshot();
  }

  ChatDataSnapshot patchWorkspace(Workspace updated) {
    final index = _workspaces.indexWhere(
      (w) => w.workspaceId == updated.workspaceId,
    );
    if (index == -1) {
      _workspaces = [..._workspaces, updated];
    } else {
      final next = List<Workspace>.of(_workspaces);
      next[index] = updated;
      _workspaces = next;
    }
    return deriveSnapshot();
  }

  ChatDataSnapshot appendSession(AppSession session) {
    _sessions = [..._sessions, session];
    return deriveSnapshot();
  }

  ChatDataSnapshot replaceSession(AppSession session) {
    final sessions = [..._sessions];
    final index = sessions.indexWhere((s) => s.sessionId == session.sessionId);
    if (index == -1) {
      sessions.add(session);
    } else {
      sessions[index] = session;
    }
    _sessions = sessions;
    return deriveSnapshot();
  }

  ChatDataSnapshot removeSession(String sessionId) {
    _sessions = [
      for (final s in _sessions)
        if (s.sessionId != sessionId) s,
    ];
    return deriveSnapshot();
  }
}
