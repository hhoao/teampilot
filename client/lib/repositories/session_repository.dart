import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/member_instance.dart';
import '../models/session_member_binding.dart';
import '../models/team_config.dart';
import '../services/storage/runtime_layout.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_team_counter.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';
import '../models/project_icon_ref.dart';
import '../services/project/project_icon_service.dart';
import '../services/project/project_icon_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../utils/lock_pool.dart';
import '../utils/project_path_utils.dart';
import '../utils/project_sessions.dart';
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

  Future<AppProject?> _readManifest(SessionRepositoryFs fs, String projectId) async {
    final raw = await fs.readText(fs.manifestFile(projectId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        final project = AppProject.fromJson(json);
        final sessionIds = await fs.listSessionIdsForProject(projectId);
        return project.copyWith(sessionIds: sessionIds);
      }
    } on Object {
      // ignore
    }
    return null;
  }

  Future<void> _writeManifest(SessionRepositoryFs fs, AppProject project) async {
    await fs.ensureProjectDir(project.projectId);
    final withoutSessions = project.copyWith(sessionIds: const []);
    await fs.writeText(
      fs.manifestFile(project.projectId),
      const JsonEncoder.withIndent('  ').convert(withoutSessions.toJson()),
    );
  }

  Future<List<AppProject>> loadProjects() async {
    final fs = await _fs();
    final projects = <AppProject>[];
    for (final projectId in await fs.listProjectIds()) {
      final project = await _readManifest(fs, projectId);
      if (project != null) {
        projects.add(project);
      }
    }
    return projects;
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

  Future<AppProject> ensureDefaultPersonalProject(String primaryPath) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, AppProject.defaultPersonalId);
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = AppProject(
      projectId: AppProject.defaultPersonalId,
      primaryPath: normalizeProjectPath(primaryPath),
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, project);
    return project;
  }

  Future<AppProject> createProject(
    String primaryPath, {
    required String teamId,
    List<String> additionalPaths = const [],
    String display = '',
  }) async {
    final fs = await _fs();
    final trimmed = normalizeProjectPath(primaryPath);
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = await loadProjects();
    for (final existing in projects) {
      if (existing.teamId != teamId ||
          !projectPathsEqual(existing.primaryPath, trimmed)) {
        continue;
      }
      final newAdd = additionalPaths
          .map(normalizeProjectPath)
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
    final project = AppProject(
      projectId: const Uuid().v4(),
      primaryPath: trimmed,
      teamId: teamId,
      additionalPaths: List<String>.from(
        additionalPaths.map(normalizeProjectPath).where((e) => e.isNotEmpty),
      ),
      display: display.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, project);
    return project;
  }

  Future<void> updateProjectMetadata(
    String projectId, {
    String? display,
    List<String>? additionalPaths,
  }) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, projectId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      display: display != null ? display.trim() : existing.display,
      additionalPaths: additionalPaths != null
          ? List<String>.from(
              additionalPaths
                  .map(normalizeProjectPath)
                  .where((e) => e.isNotEmpty),
            )
          : existing.additionalPaths,
      updatedAt: now,
    );
    await _writeManifest(fs, updated);
  }

  Future<void> applyProjectIcon(String projectId, ProjectIconRef icon) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, projectId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final projectDir = fs.projectDir(projectId);
    final iconService = ProjectIconService(
      storage: ProjectIconStorage(filesystem: fs.fs),
    );
    await iconService.deleteCustomFilesForTransition(
      projectDir: projectDir,
      projectId: projectId,
      previous: existing.icon,
      next: icon,
    );
    await _writeManifest(
      fs,
      existing.copyWith(icon: icon, updatedAt: now),
    );
  }

  Future<void> importCustomProjectIcon(
    String projectId,
    String localSourcePath,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, projectId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final projectDir = fs.projectDir(projectId);
    final iconService = ProjectIconService(
      storage: ProjectIconStorage(filesystem: fs.fs),
    );
    final customIcon = await iconService.importCustomFromLocalFile(
      projectDir: projectDir,
      projectId: projectId,
      localSourcePath: localSourcePath,
    );
    await iconService.deleteCustomFilesForTransition(
      projectDir: projectDir,
      projectId: projectId,
      previous: existing.icon,
      next: customIcon,
    );
    await _writeManifest(
      fs,
      existing.copyWith(icon: customIcon, updatedAt: now),
    );
  }

  Future<void> updateProjectPaths(
    String projectId,
    String primaryPath,
    List<String> additionalPaths,
  ) async {
    final fs = await _fs();
    final existing = await _readManifest(fs, projectId);
    if (existing == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _writeManifest(
      fs,
      existing.copyWith(
        primaryPath: normalizeProjectPath(primaryPath),
        additionalPaths: List<String>.from(
          additionalPaths.map(normalizeProjectPath).where((e) => e.isNotEmpty),
        ),
        updatedAt: now,
      ),
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
    String projectId, {
    String sessionTeam = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
  }) async {
    final fs = await _fs();
    final project = await _readManifest(fs, projectId);
    if (project == null) {
      throw StateError('Unknown projectId: $projectId');
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
      projectId: projectId,
      primaryPath: project.primaryPath,
      additionalPaths: List<String>.from(project.additionalPaths),
      display: '',
      sessionTeam: sessionTeam,
      cliTeamName: cliTeamName,
      cli: trimmedTeam.isEmpty ? cli : null,
      members: members,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionDir(projectId, sessionId);
    await fs.writeText(
      fs.sessionFile(projectId, sessionId),
      jsonEncode(session.toJson()),
    );
    return session;
  }

  Future<AppSession?> _readSession(
    SessionRepositoryFs fs,
    String projectId,
    String sessionId,
  ) async {
    final raw = await fs.readText(fs.sessionFile(projectId, sessionId));
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
    for (final projectId in await fs.listProjectIds()) {
      final session = await _readSession(fs, projectId, sessionId);
      if (session != null) return session;
    }
    return null;
  }

  Future<void> _writeSession(
    SessionRepositoryFs fs,
    AppSession session,
  ) async {
    final projectId = session.projectId.trim();
    if (projectId.isEmpty) {
      throw StateError('Session ${session.sessionId} missing projectId');
    }
    await fs.writeText(
      fs.sessionFile(projectId, session.sessionId),
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
      final projectId = existing.projectId.trim();
      final teamId = existing.sessionTeam.trim();
      if (teamId.isNotEmpty) {
        await _lifecycleService?.destroyCliState(
          projectId: projectId,
          teamId: teamId,
          sessionId: sessionId,
        );
      } else if (projectId.isNotEmpty) {
        await _lifecycleService?.destroyStandaloneCliState(
          projectId: projectId,
          sessionId: sessionId,
        );
      }
      await fs.deleteSessionDir(projectId, sessionId);
      final project = await _readManifest(fs, projectId);
      if (project != null) {
        await _writeManifest(
          fs,
          project.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
        );
      }
    });
  }

  Future<AppProject> cloneProject(
    String sourceProjectId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final fs = await _fs();
    final source = await _readManifest(fs, sourceProjectId);
    if (source == null) {
      throw StateError('Unknown projectId: $sourceProjectId');
    }

    final sourceSessions = sessionsForProject(source, await loadSessions());
    final now = DateTime.now().millisecondsSinceEpoch;
    final newProjectId = const Uuid().v4();
    final newProject = AppProject(
      projectId: newProjectId,
      primaryPath: source.primaryPath,
      teamId: source.teamId,
      additionalPaths: List<String>.from(source.additionalPaths),
      display: (display ?? source.display).trim(),
      icon: source.icon,
      createdAt: now,
      updatedAt: now,
    );
    await _writeManifest(fs, newProject);

    for (final old in sourceSessions) {
      await _cloneSessionRecord(
        fs,
        old,
        newProjectId,
        rosterMembers: rosterMembers,
      );
    }

    return (await _readManifest(fs, newProjectId)) ?? newProject;
  }

  Future<AppSession> _cloneSessionRecord(
    SessionRepositoryFs fs,
    AppSession source,
    String targetProjectId, {
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
      projectId: targetProjectId,
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
    await fs.ensureSessionDir(targetProjectId, sessionId);
    await _writeSession(fs, session);
    return session;
  }

  Future<void> deleteProject(String projectId) async {
    if (projectId == AppProject.defaultPersonalId) return;
    final fs = await _fs();
    final project = await _readManifest(fs, projectId);
    if (project == null) return;

    final sessions = sessionsForProject(project, await loadSessions());
    for (final session in sessions) {
      await deleteSession(session.sessionId);
    }

    await ProjectIconService(
      storage: ProjectIconStorage(filesystem: fs.fs),
    ).deleteAllCustomFilesForProject(
      projectDir: fs.projectDir(projectId),
      projectId: projectId,
      icon: project.icon,
    );

    await fs.deleteProjectDir(projectId);
  }
}
