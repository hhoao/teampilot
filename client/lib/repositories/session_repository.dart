import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/workspace.dart';
import '../models/app_session.dart';
import '../models/member_instance.dart';
import '../models/session_member_binding.dart';
import '../models/team_config.dart';
import '../services/storage/runtime_layout.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_team_counter.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';
import '../models/workspace_icon_ref.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/provider/workspace_trust_provisioner.dart';
import '../utils/lock_pool.dart';
import '../utils/workspace_path_utils.dart';
import '../utils/workspace_sessions.dart';
import 'session_repository_fs.dart';

class SessionRepository {
  SessionRepository({
    String? rootDir,
    StorageRoots? storageRoots,
    SessionLifecycleService? lifecycleService,
  }) : _rootOverride = rootDir,
       _storageRoots = storageRoots,
       _lifecycleService = lifecycleService;

  final String? _rootOverride;
  final StorageRoots? _storageRoots;
  final SessionLifecycleService? _lifecycleService;
  final _sessionFileLocks = LockPool();

  Future<T> _withSessionFile<T>(String sessionId, Future<T> Function() fn) {
    return _sessionFileLocks.synchronized(sessionId, fn);
  }

  Future<SessionRepositoryFs> _fs() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return SessionRepositoryFs(
        teampilotRoot: snap.teampilotRoot,
        fs: snap.fs,
        layout: snap.workspace,
      );
    }
    final root = _rootOverride ?? AppStorage.paths.basePath;
    return SessionRepositoryFs(teampilotRoot: root);
  }

  Future<Workspace?> _readManifest(SessionRepositoryFs fs, String workspaceId) async {
    final raw = await fs.readText(fs.manifestFile(workspaceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        final workspace = Workspace.fromJson(json);
        final sessionIds = await fs.listSessionIdsForWorkspace(workspaceId);
        return workspace.copyWith(sessionIds: sessionIds);
      }
    } on Object {
      // ignore
    }
    return null;
  }

  Future<void> _writeManifest(SessionRepositoryFs fs, Workspace workspace) async {
    await fs.ensureWorkspaceDir(workspace.workspaceId);
    final withoutSessions = workspace.copyWith(sessionIds: const []);
    await fs.writeText(
      fs.manifestFile(workspace.workspaceId),
      const JsonEncoder.withIndent('  ').convert(withoutSessions.toJson()),
    );
  }

  Future<List<Workspace>> loadWorkspaces() async {
    final fs = await _fs();
    final workspaces = <Workspace>[];
    for (final workspaceId in await fs.listWorkspaceIds()) {
      final workspace = await _readManifest(fs, workspaceId);
      if (workspace != null) {
        workspaces.add(workspace);
      }
    }
    return workspaces;
  }

  Future<List<AppSession>> loadSessions() async {
    final fs = await _fs();
    final sessions = <AppSession>[];
    for (final json in await fs.listAllSessionJsonMaps()) {
      try {
        sessions.add(AppSession.fromJson(json));
      } on Object {
        continue;
      }
    }
    sessions.sort((a, b) {
      final au = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bu = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bu.compareTo(au);
    });
    return sessions;
  }

  bool _pathsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Creates a workspace for [primaryPath].
  ///
  /// By default, an existing workspace with the same normalized [primaryPath]
  /// is reused: its [additionalPaths]/[display] are merged and it is returned
  /// instead of creating a duplicate. This keeps folder-merge
  /// ([SessionDataStore.addWorkspaceDirectory]) and bootstrap seeding
  /// idempotent. Pass [allowDuplicate] to skip reuse and always create a new,
  /// independent workspace on the same directory (the explicit "New Workspace"
  /// action) — multiple workspaces may then point at one directory.
  Future<Workspace> createWorkspace(
    String primaryPath, {
    List<String> additionalPaths = const [],
    String display = '',
    bool allowDuplicate = false,
  }) async {
    final fs = await _fs();
    final trimmed = normalizeWorkspacePath(primaryPath);
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaces = await loadWorkspaces();
    for (final existing in allowDuplicate ? const <Workspace>[] : workspaces) {
      if (!workspacePathsEqual(existing.primaryPath, trimmed)) {
        continue;
      }
      final newAdd = additionalPaths
          .map(normalizeWorkspacePath)
          .where((e) => e.isNotEmpty)
          .toList();
      final mergedPaths = List<String>.from(existing.additionalPaths);
      for (final p in newAdd) {
        if (!mergedPaths.contains(p)) mergedPaths.add(p);
      }
      final trimmedDisplay = display.trim();
      final displayOut = trimmedDisplay.isNotEmpty
          ? trimmedDisplay
          : existing.display;
      if (_pathsEqual(mergedPaths, existing.additionalPaths) &&
          displayOut == existing.display) {
        return existing;
      }
      final updated = existing.copyWith(
        additionalPaths: mergedPaths,
        display: displayOut,
        updatedAt: now,
      );
      await _writeManifest(fs, updated);
      return updated;
    }
    final workspace = Workspace(
      workspaceId: const Uuid().v4(),
      primaryPath: trimmed,
      additionalPaths: List<String>.from(
        additionalPaths.map(normalizeWorkspacePath).where((e) => e.isNotEmpty),
      ),
      display: display.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, workspace);
    await _provisionWorkspaceTrust(fs, workspace);
    return workspace;
  }

  Future<void> updateWorkspaceMetadata(
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    List<String>? additionalPaths,
  }) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      display: display != null ? display.trim() : existing.display,
      defaultProfileId: defaultProfileId != null
          ? defaultProfileId.trim()
          : existing.defaultProfileId,
      additionalPaths: additionalPaths != null
          ? List<String>.from(
              additionalPaths
                  .map(normalizeWorkspacePath)
                  .where((e) => e.isNotEmpty),
            )
          : existing.additionalPaths,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
  }

  Future<void> applyWorkspaceIcon(String workspaceId, WorkspaceIconRef icon) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: icon,
    );
    await _writeManifest(
      fs,
      existing.copyWith(icon: icon, updatedAt: now),
    );
  }

  Future<void> importCustomWorkspaceIcon(
    String workspaceId,
    String localSourcePath,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final workspaceDir = fs.workspaceDir(workspaceId);
    final iconService = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    );
    final customIcon = await iconService.importCustomFromLocalFile(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      localSourcePath: localSourcePath,
    );
    await iconService.deleteCustomFilesForTransition(
      workspaceDir: workspaceDir,
      workspaceId: workspaceId,
      previous: existing.icon,
      next: customIcon,
    );
    await _writeManifest(
      fs,
      existing.copyWith(icon: customIcon, updatedAt: now),
    );
  }

  Future<void> updateWorkspacePaths(
    String workspaceId,
    String primaryPath,
    List<String> additionalPaths,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, workspaceId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      primaryPath: normalizeWorkspacePath(primaryPath),
      additionalPaths: List<String>.from(
        additionalPaths.map(normalizeWorkspacePath).where((e) => e.isNotEmpty),
      ),
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
    await _provisionWorkspaceTrust(fs, updated);
  }

  Future<void> _provisionWorkspaceTrust(
    SessionRepositoryFs fs,
    Workspace workspace,
  ) async {
    final layout = RuntimeLayout(teampilotRoot: fs.teampilotRoot, fs: fs.fs);
    await WorkspaceTrustProvisioner(layout: layout, fs: fs.fs).provisionWorkspace(
      workspaceId: workspace.workspaceId,
      directories: [
        workspace.primaryPath,
        ...workspace.additionalPaths,
      ],
    );
  }

  Future<({Filesystem fs, RuntimeLayout layout})> _counterContext() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return (fs: snap.fs, layout: snap.layout);
    }
    final teampilotRoot = _rootOverride ?? AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    return (
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: teampilotRoot, fs: fs),
    );
  }

  Future<AppSession> createSession(
    String workspaceId, {
    String sessionTeam = '',
    String personalIdentityId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
    String? workingDirectory,
  }) async {
    final fs = await _fs();
    final workspace = await _readManifest(fs, workspaceId);
    if (workspace == null) {
      throw StateError('Unknown workspaceId: $workspaceId');
    }
    final trimmedTeam = sessionTeam.trim();
    var cliTeamName = '';
    var members = const <SessionMemberBinding>[];
    if (trimmedTeam.isNotEmpty) {
      final valid = rosterMembers.where((m) => m.isValid).toList();
      if (valid.isEmpty) {
        throw ArgumentError(
          'Team session requires at least one valid roster member',
        );
      }
      final counterCtx = await _counterContext();
      final counter = SessionTeamCounter(
        fs: counterCtx.fs,
        layout: counterCtx.layout,
      );
      cliTeamName = await counter.nextCliTeamName(trimmedTeam);
      members = [
        for (final inst in expandTeamRoster(valid))
          SessionMemberBinding(
            rosterMemberId: inst.instanceId,
            typeId: inst.type.id,
            taskId: const Uuid().v4(),
          ),
      ];
    }

    final sessionId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: workspaceId,
      primaryPath: (workingDirectory != null && workingDirectory.trim().isNotEmpty)
          ? normalizeWorkspacePath(workingDirectory)
          : workspace.primaryPath,
      additionalPaths: List<String>.from(workspace.additionalPaths),
      display: '',
      sessionTeam: sessionTeam,
      profileId: trimmedTeam.isEmpty ? personalIdentityId.trim() : '',
      cliTeamName: cliTeamName,
      cli: trimmedTeam.isEmpty ? cli : null,
      members: members,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionDir(workspaceId, sessionId);
    await fs.writeText(
      fs.sessionFile(workspaceId, sessionId),
      jsonEncode(session.toJson()),
    );
    return session;
  }

  Future<AppSession?> _readSession(
    SessionRepositoryFs fs,
    String workspaceId,
    String sessionId,
  ) async {
    final raw = await fs.readText(fs.sessionFile(workspaceId, sessionId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return AppSession.fromJson(json);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<AppSession?> _findSession(SessionRepositoryFs fs, String sessionId) async {
    for (final workspaceId in await fs.listWorkspaceIds()) {
      final session = await _readSession(fs, workspaceId, sessionId);
      if (session != null) return session;
    }
    return null;
  }

  Future<void> _writeSession(
    SessionRepositoryFs fs,
    AppSession session,
  ) async {
    final workspaceId = session.workspaceId.trim();
    if (workspaceId.isEmpty) {
      throw StateError('Session ${session.sessionId} missing workspaceId');
    }
    await fs.writeText(
      fs.sessionFile(workspaceId, session.sessionId),
      jsonEncode(session.toJson()),
    );
  }

  Future<void> markSessionLaunched(String sessionId) {
    return markSessionStarted(sessionId);
  }

  Future<SessionMemberBinding> ensureMemberBinding(
    String sessionId,
    String rosterMemberId, {
    String? typeId,
  }) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) {
        throw StateError('Unknown sessionId: $sessionId');
      }
      final trimmedMemberId = rosterMemberId.trim();
      if (trimmedMemberId.isEmpty) {
        throw ArgumentError.value(
          rosterMemberId,
          'rosterMemberId',
          'must not be empty',
        );
      }
      final found = existing.bindingFor(trimmedMemberId);
      if (found != null) return found;

      final now = DateTime.now().millisecondsSinceEpoch;
      final binding = SessionMemberBinding(
        rosterMemberId: trimmedMemberId,
        typeId: (typeId ?? trimmedMemberId).trim(),
        taskId: const Uuid().v4(),
      );
      await _writeSession(
        fs,
        existing.copyWith(
          members: [...existing.members, binding],
          updatedAt: now,
        ),
      );
      return binding;
    });
  }

  /// Records a CLI-native resume id for [sessionId]. Team sessions store it on
  /// the matching member binding ([rosterMemberId]); personal sessions store it
  /// at the session level. No-op when already equal. See
  /// `docs/session-resume-architecture.md`.
  Future<void> recordNativeSessionId(
    String sessionId, {
    required String tool,
    required String nativeId,
    String? rosterMemberId,
  }) {
    final trimmedTool = tool.trim();
    final trimmedId = nativeId.trim();
    if (trimmedTool.isEmpty || trimmedId.isEmpty) return Future.value();
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final memberId = rosterMemberId?.trim() ?? '';
      AppSession updated;
      if (memberId.isNotEmpty) {
        final binding = existing.bindingFor(memberId);
        if (binding == null) return;
        final next = binding.withNativeSessionId(trimmedTool, trimmedId);
        if (identical(next, binding)) return;
        updated = existing.copyWith(
          members: [
            for (final m in existing.members)
              if (m.rosterMemberId == memberId) next else m,
          ],
        );
      } else {
        final next = existing.withNativeSessionId(trimmedTool, trimmedId);
        if (identical(next, existing)) return;
        updated = next;
      }
      await _writeSession(
        fs,
        updated.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
      );
    });
  }

  Future<void> markSessionStarted(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      if (existing.launchState == AppSessionLaunchState.started) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(
          launchState: AppSessionLaunchState.started,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> renameSession(String sessionId, String newName) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(display: newName, updatedAt: now),
      );
    });
  }

  Future<void> touchSession(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(fs, existing.copyWith(updatedAt: now));
    });
  }

  Future<void> toggleSessionPin(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(pinned: !existing.pinned, updatedAt: now),
      );
    });
  }

  Future<void> updateSessionTeam(String sessionId, String sessionTeam) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(sessionTeam: sessionTeam, updatedAt: now),
      );
    });
  }

  /// Persists a manual arrangement: stamps each session's [AppSession.sortOrder]
  /// to its position in [orderedSessionIds] (1-based, so untouched sessions at
  /// the default `0` keep sorting first). Sessions absent from disk are skipped.
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    for (var i = 0; i < orderedSessionIds.length; i++) {
      final sessionId = orderedSessionIds[i];
      final order = i + 1;
      await _withSessionFile(sessionId, () async {
        final fs = await _fs();
        final existing = await _findSession(fs, sessionId);
        if (existing == null || existing.sortOrder == order) return;
        await _writeSession(fs, existing.copyWith(sortOrder: order));
      });
    }
  }

  Future<void> clearAllSessionTeams() async {
    final fs = await _fs();
    for (final json in await fs.listAllSessionJsonMaps()) {
      try {
        final session = AppSession.fromJson(json);
        await _withSessionFile(session.sessionId, () async {
          final innerFs = await _fs();
          final fresh = await _findSession(innerFs, session.sessionId);
          if (fresh == null) return;
          await _writeSession(
            innerFs,
            fresh.copyWith(
              sessionTeam: '',
              cliTeamName: '',
              members: const [],
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        });
      } on Object {
        continue;
      }
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return;
      final workspaceId = existing.workspaceId.trim();
      final teamId = existing.sessionTeam.trim();
      if (teamId.isNotEmpty) {
        await _lifecycleService?.destroyCliState(
          workspaceId: workspaceId,
          teamId: teamId,
          sessionId: sessionId,
        );
      } else if (workspaceId.isNotEmpty) {
        await _lifecycleService?.destroyStandaloneCliState(
          workspaceId: workspaceId,
          sessionId: sessionId,
        );
      }
      await fs.deleteSessionDir(workspaceId, sessionId);
      final workspace = await _readManifest(fs, workspaceId);
      if (workspace != null) {
        await _writeManifest(
          fs,
          workspace.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
        );
      }
    });
  }

  Future<Workspace> cloneWorkspace(
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final fs = await _fs();
    final source = await _readManifest(fs, sourceWorkspaceId);
    if (source == null) {
      throw StateError('Unknown workspaceId: $sourceWorkspaceId');
    }

    final sourceSessions = sessionsForWorkspace(source, await loadSessions());
    final now = DateTime.now().millisecondsSinceEpoch;
    final newWorkspaceId = const Uuid().v4();
    final newWorkspace = Workspace(
      workspaceId: newWorkspaceId,
      primaryPath: source.primaryPath,
      additionalPaths: List<String>.from(source.additionalPaths),
      display: (display ?? source.display).trim(),
      icon: source.icon,
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, newWorkspace);

    for (final old in sourceSessions) {
      await _cloneSessionRecord(
        fs,
        old,
        newWorkspaceId,
        rosterMembers: rosterMembers,
      );
    }

    return (await _readManifest(fs, newWorkspaceId)) ?? newWorkspace;
  }

  Future<AppSession> _cloneSessionRecord(
    SessionRepositoryFs fs,
    AppSession source,
    String targetWorkspaceId, {
    required List<TeamMemberConfig> rosterMembers,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var cliTeamName = '';
    var members = const <SessionMemberBinding>[];
    final trimmedTeam = source.sessionTeam.trim();
    if (trimmedTeam.isNotEmpty) {
      final valid = rosterMembers.where((m) => m.isValid).toList();
      if (valid.isNotEmpty) {
        final counterCtx = await _counterContext();
        final counter = SessionTeamCounter(
          fs: counterCtx.fs,
          layout: counterCtx.layout,
        );
        cliTeamName = await counter.nextCliTeamName(trimmedTeam);
        members = [
          for (final inst in expandTeamRoster(valid))
            SessionMemberBinding(
              rosterMemberId: inst.instanceId,
              typeId: inst.type.id,
              taskId: const Uuid().v4(),
            ),
        ];
      }
    }

    final sessionId = const Uuid().v4();
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: targetWorkspaceId,
      primaryPath: source.primaryPath,
      additionalPaths: List<String>.from(source.additionalPaths),
      display: source.display,
      sessionTeam: source.sessionTeam,
      cliTeamName: cliTeamName,
      members: members,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionDir(targetWorkspaceId, sessionId);
    await _writeSession(fs, session);
    return session;
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final fs = await _fs();
    final workspace = await _readManifest(fs, workspaceId);
    if (workspace == null) return;

    final sessions = sessionsForWorkspace(workspace, await loadSessions());
    for (final session in sessions) {
      await deleteSession(session.sessionId);
    }

    await WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: fs.fs),
    ).deleteAllCustomFilesForWorkspace(
      workspaceDir: fs.workspaceDir(workspaceId),
      workspaceId: workspaceId,
      icon: workspace.icon,
    );

    await fs.deleteWorkspaceDir(workspaceId);
  }
}
