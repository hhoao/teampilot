import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/session_member_binding.dart';
import '../models/team_config.dart';
import '../services/cli/cli_data_layout.dart';
import '../services/io/filesystem.dart';
import '../services/session/session_team_counter.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/storage_resolver.dart';
import '../services/session/session_lifecycle_service.dart';
import '../utils/lock_pool.dart';
import '../utils/project_path_utils.dart';
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
      final pathCtx = AppPaths.pathContextForDataRoot(snap.appProjectsDir);
      return SessionRepositoryFs(
        projectsFile: pathCtx.join(snap.appProjectsDir, 'projects.json'),
        sessionsDir: pathCtx.join(snap.appProjectsDir, 'sessions'),
        fs: snap.fs,
      );
    }
    final root = _rootOverride ?? AppStorage.paths.appProjectsDir;
    final pathCtx = AppPaths.pathContextForDataRoot(root);
    return SessionRepositoryFs(
      projectsFile: pathCtx.join(root, 'projects.json'),
      sessionsDir: pathCtx.join(root, 'sessions'),
    );
  }

  Future<AppProjectsIndex> _loadIndex(SessionRepositoryFs fs) async {
    final raw = await fs.readText(fs.projectsFile);
    if (raw == null || raw.isEmpty) {
      return const AppProjectsIndex();
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return AppProjectsIndex.fromJson(json);
      }
    } on Object {
      // ignore
    }
    return const AppProjectsIndex();
  }

  Future<void> _saveIndex(
    SessionRepositoryFs fs,
    AppProjectsIndex index,
  ) async {
    await fs.writeText(fs.projectsFile, jsonEncode(index.toJson()));
  }

  Future<List<AppProject>> loadProjects() async {
    final fs = await _fs();
    final index = await _loadIndex(fs);
    return List<AppProject>.from(index.projects);
  }

  Future<List<AppSession>> loadSessions() async {
    final fs = await _fs();
    final sessions = <AppSession>[];
    for (final json in await fs.listSessionJsonMaps()) {
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

  /// Returns an existing project for [primaryPath] if present, otherwise creates one.
  ///
  /// When a project already exists for [primaryPath], merges non-empty
  /// [additionalPaths] (union, stable order) and non-empty [display] into the index.
  Future<AppProject> createProject(
    String primaryPath, {
    List<String> additionalPaths = const [],
    String display = '',
  }) async {
    final fs = await _fs();
    final trimmed = normalizeProjectPath(primaryPath);
    final index = await _loadIndex(fs);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < index.projects.length; i++) {
      final existing = index.projects[i];
      if (!projectPathsEqual(existing.primaryPath, trimmed)) continue;
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
      final next = AppProjectsIndex(
        schemaVersion: index.schemaVersion,
        projects: [
          for (var j = 0; j < index.projects.length; j++)
            j == i ? updated : index.projects[j],
        ],
      );
      await _saveIndex(fs, next);
      return updated;
    }
    final project = AppProject(
      projectId: const Uuid().v4(),
      primaryPath: trimmed,
      additionalPaths: List<String>.from(
        additionalPaths.map(normalizeProjectPath).where((e) => e.isNotEmpty),
      ),
      display: display.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final next = AppProjectsIndex(
      schemaVersion: index.schemaVersion,
      projects: [...index.projects, project],
    );
    await _saveIndex(fs, next);
    return project;
  }

  Future<void> updateProjectMetadata(
    String projectId, {
    String? display,
    List<String>? additionalPaths,
  }) async {
    final fs = await _fs();
    final index = await _loadIndex(fs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = index.projects.map((proj) {
      if (proj.projectId != projectId) return proj;
      return proj.copyWith(
        display: display != null ? display.trim() : proj.display,
        additionalPaths: additionalPaths != null
            ? List<String>.from(
                additionalPaths
                    .map(normalizeProjectPath)
                    .where((e) => e.isNotEmpty),
              )
            : proj.additionalPaths,
        updatedAt: now,
      );
    }).toList();
    await _saveIndex(
      fs,
      AppProjectsIndex(schemaVersion: index.schemaVersion, projects: projects),
    );
  }

  Future<void> updateProjectPaths(
    String projectId,
    String primaryPath,
    List<String> additionalPaths,
  ) async {
    final fs = await _fs();
    final index = await _loadIndex(fs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final projects = index.projects.map((proj) {
      if (proj.projectId != projectId) return proj;
      return proj.copyWith(
        primaryPath: normalizeProjectPath(primaryPath),
        additionalPaths: List<String>.from(
          additionalPaths.map(normalizeProjectPath).where((e) => e.isNotEmpty),
        ),
        updatedAt: now,
      );
    }).toList();
    await _saveIndex(
      fs,
      AppProjectsIndex(schemaVersion: index.schemaVersion, projects: projects),
    );
  }

  Future<({Filesystem fs, CliDataLayout layout})> _counterContext() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return (fs: snap.fs, layout: snap.layout);
    }
    final teampilotRoot = _rootOverride ?? AppStorage.paths.basePath;
    final fs = AppStorage.fs;
    return (
      fs: fs,
      layout: CliDataLayout(teampilotRoot: teampilotRoot, fs: fs),
    );
  }

  Future<AppSession> createSession(
    String projectId, {
    String sessionTeam = '',
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final fs = await _fs();
    final index = await _loadIndex(fs);
    AppProject? project;
    for (final p in index.projects) {
      if (p.projectId == projectId) {
        project = p;
        break;
      }
    }
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
        for (final m in valid)
          SessionMemberBinding(rosterMemberId: m.id, taskId: const Uuid().v4()),
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
      members: members,
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionsDir();
    await fs.writeText(fs.sessionFile(sessionId), jsonEncode(session.toJson()));

    final nextProjects = index.projects.map((p) {
      if (p.projectId != projectId) return p;
      return p.copyWith(sessionIds: [sessionId, ...p.sessionIds]);
    }).toList();
    await _saveIndex(
      fs,
      AppProjectsIndex(
        schemaVersion: index.schemaVersion,
        projects: nextProjects,
      ),
    );
    return session;
  }

  Future<AppSession?> _readSession(
    SessionRepositoryFs fs,
    String sessionId,
  ) async {
    final raw = await fs.readText(fs.sessionFile(sessionId));
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

  Future<void> _writeSession(SessionRepositoryFs fs, AppSession session) async {
    await fs.writeText(
      fs.sessionFile(session.sessionId),
      jsonEncode(session.toJson()),
    );
  }

  /// Persists [AppSessionLaunchState.started] after the PTY process is up.
  Future<void> markSessionLaunched(String sessionId) {
    return markSessionStarted(sessionId);
  }

  Future<SessionMemberBinding> ensureMemberBinding(
    String sessionId,
    String rosterMemberId,
  ) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _readSession(fs, sessionId);
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
      final existing = await _readSession(fs, sessionId);
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
      final existing = await _readSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(display: newName, updatedAt: now),
      );
    });
  }

  /// Persists stable UI team id ([AppSession.sessionTeam], [TeamConfig.id]).
  Future<void> updateSessionTeam(String sessionId, String sessionTeam) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _readSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        fs,
        existing.copyWith(sessionTeam: sessionTeam, updatedAt: now),
      );
    });
  }

  Future<void> clearAllSessionTeams() async {
    final fs = await _fs();
    for (final json in await fs.listSessionJsonMaps()) {
      try {
        final session = AppSession.fromJson(json);
        await _withSessionFile(session.sessionId, () async {
          final innerFs = await _fs();
          final fresh = await _readSession(innerFs, session.sessionId);
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
      final existing = await _readSession(fs, sessionId);
      final teamId = existing?.sessionTeam.trim() ?? '';
      if (teamId.isNotEmpty) {
        await _lifecycleService?.destroyCliState(
          teamId: teamId,
          sessionId: sessionId,
          runtimeSessionId: existing?.cliTeamName,
        );
      }
      final index = await _loadIndex(fs);
      final now = DateTime.now().millisecondsSinceEpoch;
      final projects = index.projects.map((p) {
        if (!p.sessionIds.contains(sessionId)) return p;
        return p.copyWith(
          sessionIds: p.sessionIds.where((id) => id != sessionId).toList(),
          updatedAt: now,
        );
      }).toList();
      await _saveIndex(
        fs,
        AppProjectsIndex(
          schemaVersion: index.schemaVersion,
          projects: projects,
        ),
      );
      await fs.deleteFile(fs.sessionFile(sessionId));
    });
  }

  Future<void> deleteProject(String projectId) async {
    final fs = await _fs();
    final index = await _loadIndex(fs);
    AppProject? project;
    for (final p in index.projects) {
      if (p.projectId == projectId) {
        project = p;
        break;
      }
    }
    if (project == null) return;

    for (final sid in project.sessionIds.toList()) {
      await deleteSession(sid);
    }

    final latestFs = await _fs();
    final latestIndex = await _loadIndex(latestFs);
    final next = latestIndex.projects
        .where((p) => p.projectId != projectId)
        .toList();
    await _saveIndex(
      latestFs,
      AppProjectsIndex(schemaVersion: index.schemaVersion, projects: next),
    );
  }
}
