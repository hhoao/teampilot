import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/app_session.dart';
import '../services/app_storage.dart';

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
  SessionRepository({String? rootDir})
      : _root = rootDir ?? AppStorage.appProjectsDir;

  final String _root;
  final Map<String, _AsyncLock> _sessionFileLocks = {};

  Future<T> _withSessionFile<T>(String sessionId, Future<T> Function() fn) {
    final lock = _sessionFileLocks.putIfAbsent(sessionId, () => _AsyncLock());
    return lock.synchronized(fn);
  }

  String get _projectsFile => p.join(_root, 'projects.json');

  String get _sessionsDir => p.join(_root, 'sessions');

  Future<void> _atomicWriteFile(File target, String contents) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(contents);
    await tmp.rename(target.path);
  }

  Future<AppProjectsIndex> _loadIndex() async {
    final file = File(_projectsFile);
    if (!await file.exists()) {
      return const AppProjectsIndex();
    }
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        return AppProjectsIndex.fromJson(json);
      }
    } on Object {
      // ignore
    }
    return const AppProjectsIndex();
  }

  Future<void> _saveIndex(AppProjectsIndex index) async {
    final file = File(_projectsFile);
    await _atomicWriteFile(file, jsonEncode(index.toJson()));
  }

  Future<List<AppProject>> loadProjects() async {
    final index = await _loadIndex();
    return List<AppProject>.from(index.projects);
  }

  Future<List<AppSession>> loadSessions() async {
    final dir = Directory(_sessionsDir);
    if (!await dir.exists()) {
      return [];
    }
    final sessions = <AppSession>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content);
          if (json is Map<String, Object?>) {
            sessions.add(AppSession.fromJson(json));
          }
        } on Object {
          // skip
        }
      }
    } on Object {
      return sessions;
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
    final trimmed = primaryPath.trim();
    final index = await _loadIndex();
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
      final displayOut =
          trimmedDisplay.isNotEmpty ? trimmedDisplay : existing.display;
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
      await _saveIndex(next);
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
    await _saveIndex(next);
    return project;
  }

  Future<void> updateProjectPaths(
    String projectId,
    String primaryPath,
    List<String> additionalPaths,
  ) async {
    final index = await _loadIndex();
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
    await _saveIndex(AppProjectsIndex(schemaVersion: index.schemaVersion, projects: projects));
  }

  Future<AppSession> createSession(
    String projectId, {
    String sessionTeam = '',
  }) async {
    final index = await _loadIndex();
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
      launchState: AppSessionLaunchState.created,
      createdAt: now,
      updatedAt: now,
    );
    await Directory(_sessionsDir).create(recursive: true);
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    await _atomicWriteFile(file, jsonEncode(session.toJson()));

    final nextProjects = index.projects.map((p) {
      if (p.projectId != projectId) return p;
      return p.copyWith(
        sessionIds: [...p.sessionIds, sessionId],
        updatedAt: now,
      );
    }).toList();
    await _saveIndex(AppProjectsIndex(schemaVersion: index.schemaVersion, projects: nextProjects));
    return session;
  }

  Future<AppSession?> _readSession(String sessionId) async {
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        return AppSession.fromJson(json);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<void> _writeSession(AppSession session) async {
    final file = File(p.join(_sessionsDir, '${session.sessionId}.json'));
    await _atomicWriteFile(file, jsonEncode(session.toJson()));
  }

  /// Single read/write after the PTY process is up: persists [sessionTeam] (when
  /// non-empty) and [AppSessionLaunchState.started] together to avoid lost updates
  /// vs separate [updateSessionTeam] + [markSessionStarted] races.
  Future<void> markSessionLaunched(
    String sessionId, {
    required String sessionTeam,
  }) {
    return _withSessionFile(sessionId, () async {
      final existing = await _readSession(sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final trimmedTeam = sessionTeam.trim();
      var next = existing.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
      if (trimmedTeam.isNotEmpty) {
        next = next.copyWith(sessionTeam: trimmedTeam, updatedAt: now);
      }
      if (next == existing) return;
      await _writeSession(next);
    });
  }

  Future<void> markSessionStarted(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final existing = await _readSession(sessionId);
      if (existing == null) return;
      if (existing.launchState == AppSessionLaunchState.started) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        existing.copyWith(
          launchState: AppSessionLaunchState.started,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> renameSession(String sessionId, String newName) {
    return _withSessionFile(sessionId, () async {
      final existing = await _readSession(sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        existing.copyWith(display: newName, updatedAt: now),
      );
    });
  }

  Future<void> updateSessionTeam(String sessionId, String sessionTeam) {
    return _withSessionFile(sessionId, () async {
      final existing = await _readSession(sessionId);
      if (existing == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _writeSession(
        existing.copyWith(sessionTeam: sessionTeam, updatedAt: now),
      );
    });
  }

  Future<void> clearAllSessionTeams() async {
    final dir = Directory(_sessionsDir);
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content);
          if (json is! Map<String, Object?>) continue;
          final session = AppSession.fromJson(json);
          await _withSessionFile(session.sessionId, () async {
            final fresh = await _readSession(session.sessionId);
            if (fresh == null) return;
            await _writeSession(
              fresh.copyWith(
                sessionTeam: '',
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          });
        } on Object {
          // per file
        }
      }
    } on Object {
      // directory
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _withSessionFile(sessionId, () async {
      final index = await _loadIndex();
      final now = DateTime.now().millisecondsSinceEpoch;
      final projects = index.projects.map((p) {
        if (!p.sessionIds.contains(sessionId)) return p;
        return p.copyWith(
          sessionIds: p.sessionIds.where((id) => id != sessionId).toList(),
          updatedAt: now,
        );
      }).toList();
      await _saveIndex(AppProjectsIndex(schemaVersion: index.schemaVersion, projects: projects));

      final file = File(p.join(_sessionsDir, '$sessionId.json'));
      if (await file.exists()) {
        try {
          await file.delete();
        } on Object {
          // best effort
        }
      }
    });
  }

  Future<void> deleteProject(String projectId) async {
    final index = await _loadIndex();
    AppProject? project;
    for (final p in index.projects) {
      if (p.projectId == projectId) {
        project = p;
        break;
      }
    }
    if (project == null) return;

    for (final sid in project.sessionIds) {
      await _withSessionFile(sid, () async {
        final file = File(p.join(_sessionsDir, '$sid.json'));
        if (await file.exists()) {
          try {
            await file.delete();
          } on Object {
            // best effort
          }
        }
      });
    }

    final next = index.projects.where((p) => p.projectId != projectId).toList();
    await _saveIndex(AppProjectsIndex(schemaVersion: index.schemaVersion, projects: next));
  }
}

