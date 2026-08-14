import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:synchronized/synchronized.dart';

import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_icon_ref.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/workspace_index_store.dart';
import '../../services/session/session_member_cli_locks.dart';
import '../../services/workspace/target_liveness.dart';
import '../../utils/lock_pool.dart';
import '../../utils/logging/logger.dart';
import '../../utils/workspace/workspace_path_utils.dart';

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
  final LockPool _sessionLocks = LockPool();
  final Lock _mutationLock = Lock();
  final Map<String, Future<void>> _trustByWorkspace = {};
  Timer? _indexDebounce;
  bool _indexDirty = false;
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
      visibleWorkspaces: List.unmodifiable(visP),
      visibleSessions: List.unmodifiable(visS),
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
    final id = updated.workspaceId.trim();
    final index = _workspaces.indexWhere((w) => w.workspaceId == id);
    if (index != -1) {
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
        if (s.sessionId != sessionId.trim()) s,
    ];
    return deriveSnapshot();
  }

  void _replaceSessionInMemory(AppSession updated) {
    final id = updated.sessionId.trim();
    _sessions = [
      for (final s in _sessions)
        if (s.sessionId == id) updated else s,
    ];
  }

  void _markIndexDirty() {
    _indexDirty = true;
    _indexDebounce ??= Timer(const Duration(milliseconds: 300), () {
      _indexDebounce = null;
      if (!_indexDirty) return;
      _indexDirty = false;
      unawaited(_flushIndex());
    });
  }

  Future<void> _flushIndex() async {
    try {
      await _mutationLock.synchronized(() async {
        await WorkspaceIndexStore(await repo.fs()).writeAll(_workspaces);
      });
      _indexDirty = false;
    } on Object catch (error, stackTrace) {
      appLogger.e('[catalog] index flush failed', error: error, stackTrace: stackTrace);
    }
  }

  Future<T> _withSession<T>(
    String sessionId,
    Future<T> Function(AppSession current) fn,
  ) {
    return _sessionLocks.synchronized(sessionId, () async {
      final current = sessionById(sessionId);
      if (current == null) throw StateError('Unknown sessionId: $sessionId');
      return fn(current);
    });
  }

  Future<void> provisionTrust(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty) return Future.value();
    final existing = _trustByWorkspace[id];
    if (existing != null) return existing;
    final future = () async {
      try {
        final ws = workspaceById(id);
        if (ws == null) return;
        await repo.provisionWorkspaceTrust(ws);
      } on Object catch (error, stackTrace) {
        appLogger.e('[catalog] trust provision failed workspace=$id',
            error: error, stackTrace: stackTrace);
      } finally {
        _trustByWorkspace.remove(id);
      }
    }();
    _trustByWorkspace[id] = future;
    return future;
  }

  Future<void> trustProvisioningFor(String workspaceId) {
    final id = workspaceId.trim();
    if (id.isEmpty) return Future.value();
    return _trustByWorkspace[id] ?? provisionTrust(id);
  }

  /// Public dedup-aware workspace create: reuses/merges an in-memory workspace
  /// with the same primary path, otherwise creates a fresh one via the repo.
  Future<Workspace> createWorkspace(
    List<WorkspaceFolder> folders, {
    String display = '',
  }) async {
    final normalized = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    if (normalized.isEmpty) {
      throw ArgumentError('createWorkspace requires at least one folder path');
    }
    final primary = normalized.first.path;
    final existing = _workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primary))
        .firstOrNull;
    if (existing != null) {
      final merged = List<WorkspaceFolder>.from(existing.folders);
      for (final f in normalized.skip(1)) {
        if (!merged.any((e) => workspacePathsEqual(e.path, f.path))) {
          merged.add(f);
        }
      }
      final trimmed = display.trim();
      final displayOut = trimmed.isNotEmpty ? trimmed : existing.display;
      if (listEquals(merged, existing.folders) && displayOut == existing.display) {
        return existing;
      }
      final foldersUpdated = await repo.updateWorkspaceFolders(
        existing.workspaceId,
        merged,
      );
      final metaUpdated = await repo.updateWorkspaceMetadata(
        existing.workspaceId,
        display: displayOut,
      );
      final updated = metaUpdated ?? foldersUpdated;
      if (updated != null) {
        patchWorkspace(updated);
        _markIndexDirty();
        provisionTrust(existing.workspaceId);
        await _flushIndex();
        return updated;
      }
      return existing;
    }
    final workspace = await repo.createWorkspace(normalized, display: display);
    _workspaces = [..._workspaces, workspace];
    _hydratedWorkspaceIds.add(workspace.workspaceId);
    _markIndexDirty();
    provisionTrust(workspace.workspaceId);
    await _flushIndex();
    return workspace;
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})>
  createWorkspaceWithFirstSession(
    List<WorkspaceFolder> folders, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
    String display = '',
    bool allowDuplicate = false,
  }) async {
    final normalized = [
      for (final f in folders)
        if (f.path.trim().isNotEmpty)
          f.copyWith(path: normalizeWorkspacePath(f.path)),
    ];
    if (normalized.isEmpty) {
      throw ArgumentError('createWorkspace requires at least one folder path');
    }
    final primary = normalized.first.path;
    if (!allowDuplicate) {
      final existing = _workspaces
          .where((w) => workspacePathsEqual(w.firstFolderPath, primary))
          .firstOrNull;
      if (existing != null) {
        final merged = List<WorkspaceFolder>.from(existing.folders);
        for (final f in normalized.skip(1)) {
          if (!merged.any((e) => workspacePathsEqual(e.path, f.path))) {
            merged.add(f);
          }
        }
        final trimmed = display.trim();
        final displayOut = trimmed.isNotEmpty ? trimmed : existing.display;
        if (listEquals(merged, existing.folders) && displayOut == existing.display) {
          return (workspaceId: existing.workspaceId, snapshot: deriveSnapshot());
        }
        final foldersUpdated = await repo.updateWorkspaceFolders(
          existing.workspaceId,
          merged,
        );
        final metaUpdated = await repo.updateWorkspaceMetadata(
          existing.workspaceId,
          display: displayOut,
        );
        final updated = metaUpdated ?? foldersUpdated;
        if (updated != null) {
          patchWorkspace(updated);
          _markIndexDirty();
          provisionTrust(existing.workspaceId);
          await _flushIndex();
        }
        return (workspaceId: existing.workspaceId, snapshot: deriveSnapshot());
      }
    }
    final workspace = await repo.createWorkspace(normalized, display: display);
    _workspaces = [..._workspaces, workspace];
    _hydratedWorkspaceIds.add(workspace.workspaceId);
    final trimmedTeam = sessionTeamId.trim();
    final resolvedClis = trimmedTeam.isEmpty
        ? const <String, CliTool>{}
        : memberClis.isNotEmpty
        ? memberClis
        : team != null
        ? resolveSessionMemberCliLocks(team: team, rosterMembers: rosterMembers, globalPresets: globalPresets)
        : throw ArgumentError('Team session create requires memberClis or team');
    final created = await repo.createSession(workspace.workspaceId,
        sessionTeam: sessionTeamId, rosterMembers: rosterMembers, memberClis: resolvedClis,
        knownWorkspace: workspace);
    _sessions = [..._sessions, created.session];
    patchWorkspace(created.workspace.copyWith(
      sessionIds: [...created.workspace.sessionIds, created.session.sessionId],
    ));
    _markIndexDirty();
    provisionTrust(workspace.workspaceId);
    await _flushIndex();
    return (workspaceId: workspace.workspaceId, snapshot: deriveSnapshot());
  }

  Future<({AppSession session, ChatDataSnapshot snapshot})> createSession(
    String workspaceId, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    String? workingDirectory,
    String? fixedSessionId,
    String? expertKey,
    SessionContinueOverrides? continueOverrides,
    List<SessionMemberBinding>? members,
    Map<String, String>? memberTargets,
  }) async {
    final ws = workspaceById(workspaceId);
    final result = await repo.createSession(
      workspaceId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: memberClis,
      cli: cli,
      provider: provider,
      model: model,
      effort: effort,
      presetId: presetId,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
      expertKey: expertKey,
      continueOverrides: continueOverrides,
      members: members,
      memberTargets: memberTargets,
      knownWorkspace: ws,
    );
    _sessions = [..._sessions, result.session];
    patchWorkspace(result.workspace.copyWith(
      sessionIds: [...result.workspace.sessionIds, result.session.sessionId],
    ));
    _markIndexDirty();
    return (session: result.session, snapshot: deriveSnapshot());
  }

  Future<ChatDataSnapshot> renameSession(String sessionId, String newName) async {
    await _withSession(sessionId, (current) async {
      await repo.renameSession(sessionId, newName);
      _replaceSessionInMemory(current.copyWith(
        display: newName,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> markSessionStarted(String sessionId) async {
    await _withSession(sessionId, (current) async {
      if (current.launchState == AppSessionLaunchState.started) return;
      await repo.markSessionStarted(sessionId);
      _replaceSessionInMemory(current.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> touchSession(String sessionId) async {
    await _withSession(sessionId, (current) async {
      await repo.touchSession(sessionId);
      _replaceSessionInMemory(current.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> toggleSessionPin(String sessionId) async {
    await _withSession(sessionId, (current) async {
      await repo.toggleSessionPin(sessionId);
      _replaceSessionInMemory(current.copyWith(
        pinned: !current.pinned,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateSessionTeam(String sessionId, String sessionTeam) async {
    await _withSession(sessionId, (current) async {
      await repo.updateSessionTeam(sessionId, sessionTeam);
      _replaceSessionInMemory(current.copyWith(
        sessionTeam: sessionTeam,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateContinueOverrides(
    String sessionId,
    SessionContinueOverrides overrides,
  ) async {
    await _withSession(sessionId, (current) async {
      await repo.updateContinueOverrides(sessionId, overrides);
      _replaceSessionInMemory(current.copyWith(
        continueOverrides: overrides,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateSimpleLaunchIdentity(
    String sessionId, {
    String? presetId,
    String? provider,
    String? model,
    String? effort,
  }) async {
    await _withSession(sessionId, (current) async {
      await repo.updateSimpleLaunchIdentity(
        sessionId,
        presetId: presetId,
        provider: provider,
        model: model,
        effort: effort,
      );
      _replaceSessionInMemory(current.copyWith(
        presetId: presetId != null ? presetId.trim() : current.presetId,
        provider: provider != null ? provider.trim() : current.provider,
        model: model != null ? model.trim() : current.model,
        effort: effort != null ? effort.trim() : current.effort,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> recordNativeSessionId(
    String sessionId, {
    required String tool,
    required String nativeId,
    String? rosterMemberId,
  }) async {
    await _withSession(sessionId, (current) async {
      await repo.recordNativeSessionId(
        sessionId,
        tool: tool,
        nativeId: nativeId,
        rosterMemberId: rosterMemberId,
      );
      final memberId = rosterMemberId?.trim() ?? '';
      final patched = memberId.isNotEmpty
          ? _patchMemberNativeSessionId(current, memberId, tool, nativeId)
          : current.withNativeSessionId(tool, nativeId);
      if (!identical(patched, current)) {
        _replaceSessionInMemory(patched.copyWith(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  static AppSession _patchMemberNativeSessionId(
    AppSession session,
    String memberId,
    String tool,
    String nativeId,
  ) {
    final binding = session.bindingFor(memberId);
    if (binding == null) return session;
    final next = binding.withNativeSessionId(tool, nativeId);
    if (identical(next, binding)) return session;
    return session.copyWith(members: [
      for (final m in session.members)
        if (m.rosterMemberId == memberId) next else m,
    ]);
  }

  Future<({SessionMemberBinding binding, ChatDataSnapshot snapshot})>
  ensureMemberBinding(
    String sessionId,
    String rosterMemberId, {
    required CliTool cli,
    String? typeId,
  }) async {
    final binding = await _withSession(sessionId, (current) async {
      final result = await repo.ensureMemberBinding(
        sessionId,
        rosterMemberId,
        cli: cli,
        typeId: typeId,
      );
      if (current.bindingFor(rosterMemberId.trim()) == null) {
        _replaceSessionInMemory(current.copyWith(
          members: [...current.members, result],
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      return result;
    });
    _markIndexDirty();
    return (binding: binding, snapshot: deriveSnapshot());
  }

  Future<ChatDataSnapshot> reorderSessions(List<String> orderedSessionIds) async {
    for (var i = 0; i < orderedSessionIds.length; i++) {
      final sessionId = orderedSessionIds[i];
      final order = i + 1;
      await _sessionLocks.synchronized(sessionId, () async {
        final current = sessionById(sessionId);
        if (current == null) return;
        await repo.reorderSessions([sessionId]);
        if (current.sortOrder == order) return;
        _replaceSessionInMemory(current.copyWith(sortOrder: order));
      });
    }
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> addWorkspaceDirectory(
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    if (folder.path.trim().isEmpty) return deriveSnapshot();
    if (workspacePathsEqual(folder.path, workspace.firstFolderPath)) {
      return deriveSnapshot();
    }
    if (workspace.folders.any(
      (f) => workspacePathsEqual(f.path, folder.path),
    )) {
      return deriveSnapshot();
    }
    final updated = await repo.updateWorkspaceFolders(workspace.workspaceId, [
      ...workspace.folders,
      folder.copyWith(path: normalizeWorkspacePath(folder.path)),
    ]);
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateWorkspaceMetadata(
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
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> applyWorkspaceIcon(
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final updated = await repo.applyWorkspaceIcon(workspaceId, icon);
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> importCustomWorkspaceIcon(
    String workspaceId,
    String localSourcePath,
  ) async {
    final updated = await repo.importCustomWorkspaceIcon(
      workspaceId,
      localSourcePath,
    );
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateWorkspaceMemberTargets(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    final updated = await repo.updateWorkspaceMemberTargets(
      workspaceId,
      teamId,
      targets: targets,
    );
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async {
    final updated = await repo.updateWorkspaceMemberPlacement(
      workspaceId,
      teamId,
      targets: targets,
    );
    if (updated != null) {
      patchWorkspace(updated);
      _markIndexDirty();
    }
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> remapWorkspaceTarget(
    String workspaceId, {
    required String fromTargetId,
    required String toTargetId,
    required TargetLiveness liveness,
  }) async {
    final result = await repo.remapWorkspaceTarget(
      workspaceId,
      fromTargetId: fromTargetId,
      toTargetId: toTargetId,
      liveness: liveness,
    );
    patchWorkspace(result.workspace);
    for (final session in result.sessions) {
      _replaceSessionInMemory(session);
    }
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> deleteSession(String sessionId) async {
    await _withSession(sessionId, (current) async {
      await repo.deleteSession(sessionId);
      final workspaceId = current.workspaceId;
      removeSession(sessionId);
      final ws = workspaceById(workspaceId);
      if (ws != null) {
        patchWorkspace(ws.copyWith(
          sessionIds: [
            for (final id in ws.sessionIds)
              if (id != sessionId) id,
          ],
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
    _markIndexDirty();
    return deriveSnapshot();
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})> cloneWorkspace(
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await repo.cloneWorkspace(
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    _workspaces = [..._workspaces, result.workspace];
    _hydratedWorkspaceIds.add(result.workspace.workspaceId);
    _sessions = [..._sessions, ...result.sessions];
    _markIndexDirty();
    provisionTrust(result.workspace.workspaceId);
    return (workspaceId: result.workspace.workspaceId, snapshot: deriveSnapshot());
  }

  Future<ChatDataSnapshot> deleteWorkspace(String workspaceId) async {
    await repo.deleteWorkspace(workspaceId);
    final id = workspaceId.trim();
    _workspaces = [
      for (final w in _workspaces)
        if (w.workspaceId != id) w,
    ];
    _sessions = [
      for (final s in _sessions)
        if (s.workspaceId != id) s,
    ];
    _hydratedWorkspaceIds.remove(id);
    _markIndexDirty();
    return deriveSnapshot();
  }
}
