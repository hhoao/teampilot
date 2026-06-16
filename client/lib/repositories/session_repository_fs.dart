import 'dart:convert';

import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';

/// Local or remote file access for [SessionRepository].
///
/// Projects live at `workspace/projects/{projectId}/manifest.json`; each session
/// is `workspace/projects/{projectId}/sessions/{sessionId}/session.json`.
class SessionRepositoryFs {
  SessionRepositoryFs({
    required this.teampilotRoot,
    Filesystem? fs,
    WorkspaceLayout? layout,
  }) : fs = fs ?? AppStorage.fs,
       _layout =
           layout ?? WorkspaceLayout(teampilotRoot: teampilotRoot, fs: fs);

  final String teampilotRoot;
  final Filesystem fs;
  final WorkspaceLayout _layout;

  WorkspaceLayout get layout => _layout;

  String get projectsDir => _layout.projectsDir;

  String projectDir(String projectId) => _layout.projectDir(projectId);

  String manifestFile(String projectId) => _layout.manifestFile(projectId);

  String sessionsDir(String projectId) => _layout.sessionsDir(projectId);

  String sessionDir(String projectId, String sessionId) =>
      _layout.sessionDir(projectId, sessionId);

  String sessionFile(String projectId, String sessionId) =>
      _layout.sessionFile(projectId, sessionId);

  Future<String?> readText(String path) => fs.readString(path);

  Future<void> writeText(String path, String contents) =>
      fs.atomicWrite(path, contents);

  Future<bool> exists(String path) async => (await fs.stat(path)).exists;

  Future<void> ensureProjectDir(String projectId) =>
      fs.ensureDir(projectDir(projectId));

  Future<void> ensureSessionDir(String projectId, String sessionId) =>
      fs.ensureDir(sessionDir(projectId, sessionId));

  /// Recursively removes one project's entire directory.
  Future<void> deleteProjectDir(String projectId) async {
    try {
      await fs.removeRecursive(projectDir(projectId));
    } on Object {
      // best effort
    }
  }

  /// Recursively removes one session's entire directory (metadata + bus + runtime).
  Future<void> deleteSessionDir(String projectId, String sessionId) async {
    try {
      await fs.removeRecursive(sessionDir(projectId, sessionId));
    } on Object {
      // best effort
    }
  }

  Future<List<String>> listProjectIds() async {
    final ids = <String>[];
    final stat = await fs.stat(projectsDir);
    if (!stat.isDirectory) return ids;
    for (final entry in await fs.listDir(projectsDir)) {
      if (!entry.isDirectory) continue;
      final manifest = manifestFile(entry.name);
      if ((await fs.stat(manifest)).exists) {
        ids.add(entry.name);
      }
    }
    return ids;
  }

  Future<List<Map<String, Object?>>> listSessionJsonMapsForProject(
    String projectId,
  ) async {
    final maps = <Map<String, Object?>>[];
    final dir = sessionsDir(projectId);
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return maps;
    for (final entry in await fs.listDir(dir)) {
      if (!entry.isDirectory) continue;
      try {
        final text = await fs.readString(sessionFile(projectId, entry.name));
        if (text == null || text.isEmpty) continue;
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          maps.add(Map<String, Object?>.from(decoded));
        }
      } on Object {
        continue;
      }
    }
    return maps;
  }

  Future<List<Map<String, Object?>>> listAllSessionJsonMaps() async {
    final maps = <Map<String, Object?>>[];
    for (final projectId in await listProjectIds()) {
      maps.addAll(await listSessionJsonMapsForProject(projectId));
    }
    return maps;
  }

  Future<List<String>> listSessionIdsForProject(String projectId) async {
    final dated = <({String id, int createdAt})>[];
    final dir = sessionsDir(projectId);
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return const [];
    for (final entry in await fs.listDir(dir)) {
      if (!entry.isDirectory) continue;
      final file = sessionFile(projectId, entry.name);
      if (!(await fs.stat(file)).exists) continue;
      var createdAt = 0;
      try {
        final text = await fs.readString(file);
        if (text != null && text.isNotEmpty) {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            createdAt = decoded['createdAt'] as int? ?? 0;
          }
        }
      } on Object {
        // best effort — fall back to directory order
      }
      dated.add((id: entry.name, createdAt: createdAt));
    }
    dated.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [for (final e in dated) e.id];
  }
}
