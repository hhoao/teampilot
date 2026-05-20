import 'dart:convert';

import 'package:path/path.dart' as p;

import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';

/// Local or remote file access for [SessionRepository].
class SessionRepositoryFs {
  SessionRepositoryFs({
    required this.projectsFile,
    required this.sessionsDir,
    Filesystem? fs,
  }) : fs = fs ?? LocalFilesystem();

  final String projectsFile;
  final String sessionsDir;
  final Filesystem fs;

  p.Context get _pathContext => fs.pathContext;

  String sessionFile(String sessionId) =>
      _pathContext.join(sessionsDir, '$sessionId.json');

  Future<String?> readText(String path) => fs.readString(path);

  Future<void> writeText(String path, String contents) =>
      fs.atomicWrite(path, contents);

  Future<bool> exists(String path) async => (await fs.stat(path)).exists;

  Future<void> deleteFile(String path) async {
    try {
      await fs.removeRecursive(path);
    } on Object {
      // best effort
    }
  }

  Future<void> ensureSessionsDir() => fs.ensureDir(sessionsDir);

  Future<List<Map<String, Object?>>> listSessionJsonMaps() async {
    final maps = <Map<String, Object?>>[];
    for (final entry in await fs.listDir(sessionsDir)) {
      if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
      try {
        final text = await fs.readString(
          _pathContext.join(sessionsDir, entry.name),
        );
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
