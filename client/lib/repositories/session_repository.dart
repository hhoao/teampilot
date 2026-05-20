import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/app_session.dart';
import '../services/app_storage.dart';
import '../services/flashskyai_storage_roots.dart';
import '../services/session_lifecycle_service.dart';
import 'session_repository_fs.dart';

class _AsyncLock {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() fn) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    return previous.then((_) => fn()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }
}

class SessionRepository {
  SessionRepository({
    String? rootDir,
    FlashskyaiStorageRoots? storageRoots,
    SessionLifecycleService? lifecycleService,
  }) : _rootOverride = rootDir,
       _storageRoots = storageRoots,
       _lifecycleService = lifecycleService;

  final String? _rootOverride;
  final FlashskyaiStorageRoots? _storageRoots;
  final SessionLifecycleService? _lifecycleService;
  final Map<String, _AsyncLock> _sessionFileLocks = {};

  Future<T> _withSessionFile<T>(String sessionId, Future<T> Function() fn) {
    final lock = _sessionFileLocks.putIfAbsent(sessionId, () => _AsyncLock());
    return lock.synchronized(fn);
  }

  Future<SessionRepositoryFs> _fs() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      return SessionRepositoryFs(
        projectsFile: p.join(snap.appProjectsDir, 'projects.json'),
        sessionsDir: p.join(snap.appProjectsDir, 'sessions'),
        fs: snap.fs,
      );
    }
    final root = _rootOverride ?? AppPathsBootstrapper.current.appProjectsDir;
    return SessionRepositoryFs(
      projectsFile: p.join(root, 'projects.json'),
      sessionsDir: p.join(root, 'sessions'),
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
    final trimmed = primaryPath.trim();
    final index = await _loadIndex(fs);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < index.projects.length; i++) {
      final existing = index.projects[i];
      if (existing.primaryPath != trimmed) continue;
      final newAdd = additionalPaths
          .map((e) => e.trim())
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
        additionalPaths.map((e) => e.trim()).where((e) => e.isNotEmpty),
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
        primaryPath: primaryPath.trim(),
        additionalPaths: List<String>.from(
          additionalPaths.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ),
        updatedAt: now,
      );
    }).toList();
    await _saveIndex(
      fs,
      AppProjectsIndex(schemaVersion: index.schemaVersion, projects: projects),
    );
  }

  Future<AppSession> createSession(
    String projectId, {
    String sessionTeam = '',
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
    final sessionId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = AppSession(
      sessionId: sessionId,
      projectId: projectId,
      primaryPath: project.primaryPath,
      additionalPaths: List<String>.from(project.additionalPaths),
      display: '',
      sessionTeam: sessionTeam,
      launchTeam: '',
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await fs.ensureSessionsDir();
    await fs.writeText(fs.sessionFile(sessionId), jsonEncode(session.toJson()));

    final nextProjects = index.projects.map((p) {
      if (p.projectId != projectId) return p;
      return p.copyWith(
        sessionIds: [...p.sessionIds, sessionId],
        updatedAt: now,
      );
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

  /// Single read/write after the PTY process is up: persists [launchTeam] (when
  /// non-empty) and [AppSessionLaunchState.started] together without overwriting
  /// [AppSession.sessionTeam] (stable UI team id).
  Future<void> markSessionLaunched(
    String sessionId, {
    required String launchTeam,
  }) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _readSession(fs, sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final trimmed = launchTeam.trim();
      var next = existing.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
      if (trimmed.isNotEmpty) {
        next = next.copyWith(launchTeam: trimmed, updatedAt: now);
      }
      if (next == existing) return;
      await _writeSession(fs, next);
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
              launchTeam: '',
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
          runtimeSessionId: existing?.effectiveCliTeamDirectory,
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
