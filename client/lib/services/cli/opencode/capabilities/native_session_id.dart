import 'dart:io' show Directory, File;

import 'package:sqlite3/sqlite3.dart';

import '../../../io/filesystem.dart';

/// Resolves OpenCode's native `ses_*` id for a per-session data dir.
///
/// Order: persisted binding → legacy `storage/session/**/ses_*.json` →
/// newest row in `opencode.db` (current OpenCode layout).
Future<String?> resolveOpencodeNativeSessionId({
  required Filesystem fs,
  required String dataDir,
  String? persistedNativeId,
}) async {
  final persisted = persistedNativeId?.trim() ?? '';
  if (persisted.isNotEmpty) return persisted;

  final fromJson = await resolveOpencodeNativeSessionIdFromJson(fs, dataDir);
  if (fromJson != null) return fromJson;

  return resolveOpencodeNativeSessionIdFromSqlite(fs, dataDir);
}

Future<String?> resolveOpencodeNativeSessionIdFromJson(
  Filesystem fs,
  String dataDir,
) async {
  final path = fs.pathContext;
  final sessionDir = path.join(dataDir, 'storage', 'session');

  var bestName = '';
  try {
    final entries = await fs.listDirRecursive(sessionDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      final name = path.basename(e.name);
      if (!name.startsWith('ses_') || !name.endsWith('.json')) continue;
      if (e.name.compareTo(bestName) > 0) bestName = e.name;
    }
  } on Object {
    return null;
  }
  if (bestName.isEmpty) return null;
  final name = path.basename(bestName);
  return name.substring(0, name.length - '.json'.length);
}

Future<String?> resolveOpencodeNativeSessionIdFromSqlite(
  Filesystem fs,
  String dataDir,
) async {
  final path = fs.pathContext;
  final dbPath = path.join(dataDir, 'opencode.db');
  if (!await opencodeSqliteMainExists(fs, dbPath)) return null;

  Directory? tempDir;
  Database? db;
  try {
    tempDir = await Directory.systemTemp.createTemp('opencode-session-');
    final tempDbPath = path.join(tempDir.path, 'opencode.db');
    final copied = await copyOpencodeSqliteSnapshot(
      fs: fs,
      dbPath: dbPath,
      destDbPath: tempDbPath,
    );
    if (copied.isEmpty) return null;
    db = sqlite3.open(tempDbPath, mode: OpenMode.readOnly);
    final rows = db.select(
      '''
SELECT id
FROM session
ORDER BY time_updated DESC, id DESC
LIMIT 1
''',
    );
    if (rows.isEmpty) return null;
    final id = '${rows.first['id']}'.trim();
    return id.isEmpty ? null : id;
  } on Object {
    return null;
  } finally {
    db?.close();
    if (tempDir != null) {
      try {
        await tempDir.delete(recursive: true);
      } on Object {
        // best-effort cleanup
      }
    }
  }
}

Future<bool> opencodeSqliteMainExists(Filesystem fs, String dbPath) async {
  final bytes = await fs.readBytes(dbPath);
  return bytes != null && bytes.isNotEmpty;
}

/// Copy `opencode.db` plus WAL sidecars. OpenCode opens with
/// `PRAGMA journal_mode = WAL`; copying only the main file yields an empty
/// schema while the writer is still live.
Future<List<String>> copyOpencodeSqliteSnapshot({
  required Filesystem fs,
  required String dbPath,
  required String destDbPath,
}) async {
  final copiedSources = <String>[];
  for (final suffix in const ['', '-wal', '-shm']) {
    final src = '$dbPath$suffix';
    final bytes = await fs.readBytes(src);
    if (bytes == null || bytes.isEmpty) {
      if (suffix.isEmpty) return const [];
      continue;
    }
    await File('$destDbPath$suffix').writeAsBytes(bytes);
    copiedSources.add(src);
  }
  return copiedSources;
}
