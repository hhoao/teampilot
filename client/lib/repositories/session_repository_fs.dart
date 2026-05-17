import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/remote_file_store.dart';

/// Local or remote file access for [SessionRepository].
class SessionRepositoryFs {
  const SessionRepositoryFs({
    required this.projectsFile,
    required this.sessionsDir,
    this.remote,
  });

  final String projectsFile;
  final String sessionsDir;
  final RemoteFileStore? remote;

  bool get isRemote => remote != null;

  String sessionFile(String sessionId) =>
      p.join(sessionsDir, '$sessionId.json');

  Future<String?> readText(String path) async {
    if (isRemote) {
      return remote!.readFile(path);
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  Future<void> writeText(String path, String contents) async {
    if (isRemote) {
      final posix = p.Context(style: p.Style.posix);
      final parent = posix.dirname(path);
      if (parent.isNotEmpty && parent != '.') {
        await remote!.ensureDirectory(parent);
      }
      await remote!.writeFile(path, contents);
      return;
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(contents);
    await tmp.rename(file.path);
  }

  Future<bool> exists(String path) async {
    if (isRemote) {
      return remote!.fileExists(path);
    }
    return File(path).existsSync();
  }

  Future<void> deleteFile(String path) async {
    if (isRemote) {
      await remote!.deleteFile(path);
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } on Object {
        // best effort
      }
    }
  }

  Future<void> ensureSessionsDir() async {
    if (isRemote) {
      await remote!.ensureDirectory(sessionsDir);
      return;
    }
    await Directory(sessionsDir).create(recursive: true);
  }

  Future<List<Map<String, Object?>>> listSessionJsonMaps() async {
    if (isRemote) {
      final posix = p.Context(style: p.Style.posix);
      final maps = <Map<String, Object?>>[];
      try {
        final entries = await remote!.listDirectoryEntries(sessionsDir);
        for (final entry in entries) {
          if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
          final text = await remote!.readFile(
            posix.join(sessionsDir, entry.name),
          );
          if (text == null || text.isEmpty) continue;
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map) {
              maps.add(Map<String, Object?>.from(decoded));
            }
          } on Object {
            continue;
          }
        }
      } on Object {
        return maps;
      }
      return maps;
    }

    final dir = Directory(sessionsDir);
    if (!dir.existsSync()) return [];
    final maps = <Map<String, Object?>>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
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
