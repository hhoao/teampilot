import 'dart:convert';

import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';
import 'session_snapshot_isolate.dart';

/// Local or remote file access for [SessionRepository].
///
/// Workspaces live at `workspace/workspaces/{workspaceId}/manifest.json`; each session
/// is `workspace/workspaces/{workspaceId}/sessions/{sessionId}/session.json`.
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

  String get workspacesDir => _layout.workspacesDir;

  String workspaceDir(String workspaceId) => _layout.workspaceDir(workspaceId);

  String manifestFile(String workspaceId) => _layout.manifestFile(workspaceId);

  String sessionsDir(String workspaceId) => _layout.sessionsDir(workspaceId);

  String sessionDir(String workspaceId, String sessionId) =>
      _layout.sessionDir(workspaceId, sessionId);

  String sessionFile(String workspaceId, String sessionId) =>
      _layout.sessionFile(workspaceId, sessionId);

  Future<String?> readText(String path) => fs.readString(path);

  Future<void> writeText(String path, String contents) =>
      fs.atomicWrite(path, contents);

  Future<bool> exists(String path) async => (await fs.stat(path)).exists;

  Future<void> ensureWorkspaceDir(String workspaceId) =>
      fs.ensureDir(workspaceDir(workspaceId));

  Future<void> ensureSessionDir(String workspaceId, String sessionId) =>
      fs.ensureDir(sessionDir(workspaceId, sessionId));

  /// Recursively removes one workspace's entire directory.
  Future<void> deleteWorkspaceDir(String workspaceId) async {
    try {
      await fs.removeRecursive(workspaceDir(workspaceId));
    } on Object {
      // best effort
    }
  }

  /// Recursively removes one session's entire directory (metadata + bus + runtime).
  Future<void> deleteSessionDir(String workspaceId, String sessionId) async {
    try {
      await fs.removeRecursive(sessionDir(workspaceId, sessionId));
    } on Object {
      // best effort
    }
  }

  Future<List<String>> listWorkspaceIds() async {
    final stat = await fs.stat(workspacesDir);
    if (!stat.isDirectory) return const [];
    final entries = await fs.listDir(workspacesDir);
    final ids = await Future.wait(
      entries.where((e) => e.isDirectory).map((entry) async {
        final manifest = manifestFile(entry.name);
        if ((await fs.stat(manifest)).exists) return entry.name;
        return null;
      }),
    );
    return [for (final id in ids) if (id != null) id];
  }

  /// Caps concurrent `session.json` reads so a workspace with many sessions
  /// does not open one SFTP request per session at once (which can stall the
  /// single SSH channel). 16 keeps local disk and remote SFTP both busy.
  static const int _sessionReadConcurrency = 16;

  Future<List<Map<String, Object?>>> listSessionJsonMapsForWorkspace(
    String workspaceId,
  ) async {
    final dir = sessionsDir(workspaceId);
    // Native: walk + read + decode off the UI isolate so a workspace with many
    // (or large) sessions never freezes the app while switching tabs. SFTP/WSL
    // hold non-sendable handles, so they fall through to the async path below.
    if (fs is LocalFilesystem) {
      try {
        return await SessionSnapshotIsolate.readSessionMaps(dir);
      } on Object {
        // Fall back to the filesystem abstraction below.
      }
    }
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return const [];
    final sessionIds = [
      for (final entry in await fs.listDir(dir))
        if (entry.isDirectory) entry.name,
    ];
    if (sessionIds.isEmpty) return const [];

    // Read sessions concurrently (bounded) instead of serially. On SSH this
    // turns N round-trips-in-sequence into N/concurrency batches; on local
    // disk it overlaps the read+decode work. Order is not preserved — callers
    // sort by updatedAt/createdAt anyway.
    final maps = <Map<String, Object?>>[];
    for (var i = 0; i < sessionIds.length; i += _sessionReadConcurrency) {
      final batch = sessionIds.skip(i).take(_sessionReadConcurrency);
      final decoded = await Future.wait(
        batch.map((id) => _readSessionJsonMap(workspaceId, id)),
      );
      for (final map in decoded) {
        if (map != null) maps.add(map);
      }
    }
    return maps;
  }

  Future<Map<String, Object?>?> _readSessionJsonMap(
    String workspaceId,
    String sessionId,
  ) async {
    try {
      final text = await fs.readString(sessionFile(workspaceId, sessionId));
      if (text == null || text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object {
      // Skip unreadable/corrupt session files; best-effort listing.
    }
    return null;
  }

  Future<List<Map<String, Object?>>> listAllSessionJsonMaps() async {
    final maps = <Map<String, Object?>>[];
    for (final workspaceId in await listWorkspaceIds()) {
      maps.addAll(await listSessionJsonMapsForWorkspace(workspaceId));
    }
    return maps;
  }

  Future<List<String>> listSessionDirectoryIds(String workspaceId) async {
    final dir = sessionsDir(workspaceId);
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return const [];
    return [
      for (final entry in await fs.listDir(dir))
        if (entry.isDirectory) entry.name,
    ];
  }

  Future<List<String>> listSessionIdsForWorkspace(String workspaceId) async {
    final dated = <({String id, int createdAt})>[];
    final dir = sessionsDir(workspaceId);
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return const [];
    for (final entry in await fs.listDir(dir)) {
      if (!entry.isDirectory) continue;
      final file = sessionFile(workspaceId, entry.name);
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
