import 'dart:convert';

import '../services/storage/app_storage.dart';
import '../services/storage/session_storage_layout.dart';
import '../services/io/filesystem.dart';

/// Local or remote file access for [SessionRepository].
///
/// On disk each session is one self-contained directory; see
/// [SessionStorageLayout] for the canonical path layout.
class SessionRepositoryFs {
  SessionRepositoryFs({
    required this.projectsFile,
    required this.sessionsDir,
    Filesystem? fs,
  }) : fs = fs ?? AppStorage.fs;

  final String projectsFile;
  final String sessionsDir;
  final Filesystem fs;

  late final SessionStorageLayout _layout = SessionStorageLayout(
    sessionsDir: sessionsDir,
    context: fs.pathContext,
  );

  /// `{sessionsDir}/{sessionId}` — the self-contained directory for one session.
  String sessionDir(String sessionId) => _layout.sessionDir(sessionId);

  /// `{sessionDir}/session.json` — the session metadata file.
  String sessionFile(String sessionId) => _layout.sessionFile(sessionId);

  Future<String?> readText(String path) => fs.readString(path);

  Future<void> writeText(String path, String contents) =>
      fs.atomicWrite(path, contents);

  Future<bool> exists(String path) async => (await fs.stat(path)).exists;

  /// Recursively removes one session's entire directory (metadata + bus logs).
  Future<void> deleteSessionDir(String sessionId) async {
    try {
      await fs.removeRecursive(sessionDir(sessionId));
    } on Object {
      // best effort
    }
  }

  Future<void> ensureSessionsDir() => fs.ensureDir(sessionsDir);

  Future<List<Map<String, Object?>>> listSessionJsonMaps() async {
    final maps = <Map<String, Object?>>[];
    for (final entry in await fs.listDir(sessionsDir)) {
      if (!entry.isDirectory) continue;
      try {
        final text = await fs.readString(sessionFile(entry.name));
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
}
