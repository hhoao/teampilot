import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';
import 'sqlite_worker_pool.dart';

/// Resolves OpenCode's native `ses_*` id for a per-session data dir.
///
/// Order: persisted binding → newest row in `opencode.db` (current layout).
Future<String?> resolveOpencodeNativeSessionId({
  required Filesystem fs,
  required String dataDir,
  String? persistedNativeId,
}) async {
  final persisted = persistedNativeId?.trim() ?? '';
  if (persisted.isNotEmpty) return persisted;

  return resolveOpencodeNativeSessionIdFromSqlite(fs, dataDir);
}

Future<String?> resolveOpencodeNativeSessionIdFromSqlite(
  Filesystem fs,
  String dataDir,
) async {
  final path = fs.pathContext;
  final dbPath = path.join(dataDir, 'opencode.db');
  final handle = await resolveOpencodeSqliteReadPath(
    fs: fs,
    dbPath: dbPath,
  );
  if (handle == null) return null;

  return handle.read<String?>(opencodeNewestSessionId);
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

/// Read handle for the OpenCode SQLite store.
class OpencodeSqliteReadHandle {
  const OpencodeSqliteReadHandle({
    required this.path,
    required this.sourcePaths,
  });

  /// Path to open read-only (live DB on local backends, snapshot on remote).
  final String path;

  /// Change-signal paths for the watch meta: the live DB file (local) or the
  /// copied snapshot files (remote).
  final List<String> sourcePaths;

  /// Runs a read-only SQLite query **off the UI isolate**, through the
  /// per-store resident worker ([OpencodeSqliteWorkerPool]).
  ///
  /// `sqlite3` FFI calls are synchronous and block the calling isolate's
  /// thread for the whole query; on a large store (40MB+ WAL) that is
  /// hundreds of ms of UI-isolate time per live-refresh tick, during which the
  /// isolate cannot reach a safepoint either. The worker isolate keeps the UI
  /// isolate responsive and out of native code, and its **resident connection**
  /// keeps the page cache warm across queries — no per-query open/spawn.
  ///
  /// [query] must be a top-level function ([SqliteQueryFn]); its result [T]
  /// must be sendable (primitive / String / List / Map / records of those).
  /// Returns null when the open or query fails.
  Future<T?> read<T>(SqliteQueryFn query, [Object? args]) {
    return OpencodeSqliteWorkerPool.instance.run<T>(
      dbPath: path,
      query: query,
      args: args,
    );
  }
}

/// Newest ROOT session row — never a task child, so the seat stays on the
/// parent conversation while a `task` sub-agent is running.
///
/// Current OpenCode layout: `parent_id` is a real column — one indexed
/// scoped query. Legacy layout (parent linkage inside the `data` JSON blob)
/// falls back to a full scan filtering out rows with a non-empty parent.
String? opencodeNewestSessionId(Database db, Object? args) {
  try {
    final rows = db.select(
      '''
SELECT id
FROM session
WHERE parent_id IS NULL OR parent_id = ''
ORDER BY time_updated DESC, id DESC
LIMIT 1
''',
    );
    if (rows.isEmpty) return null;
    final id = '${rows.first['id']}'.trim();
    return id.isEmpty ? null : id;
  } on SqliteException {
    // Legacy layout: no parent_id column; parent linkage lives in `data`.
    final rows = db.select(
      '''
SELECT id, data, time_updated
FROM session
ORDER BY time_updated DESC, id DESC
''',
    );
    for (final row in rows) {
      final id = '${row['id']}'.trim();
      if (id.isEmpty) continue;
      final obj = _decodeRowData(row['data']);
      if (obj == null) continue;
      final parent = '${obj['parent_id'] ?? obj['parentID'] ?? ''}'.trim();
      if (parent.isNotEmpty) continue;
      return id;
    }
    return null;
  }
}

Map<String, dynamic>? _decodeRowData(Object? raw) {
  try {
    final decoded = switch (raw) {
      final String s => jsonDecode(s),
      final List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ => null,
    };
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on Object {
    return null;
  }
  return null;
}

/// Resolves a readable local path for the OpenCode SQLite store:
///
///  - **native local backend**: the live DB itself. OpenCode keeps a WAL
///    writer open, but a second read-only connection reads the WAL fine, so no
///    full-file copy is needed — critical because a session with many task
///    sub-agents resolves the store once per sub-agent per live refresh.
///  - **remote backends** (SFTP / WSL): a snapshot copied through the
///    filesystem abstraction, memoized per `(dbPath, fingerprint)` so the
///    whole live-refresh burst shares a single transfer until the store moves.
///
/// Returns null when the store is absent.
Future<OpencodeSqliteReadHandle?> resolveOpencodeSqliteReadPath({
  required Filesystem fs,
  required String dbPath,
}) async {
  if (fs is LocalFilesystem) {
    final st = await fs.stat(dbPath);
    if (!st.isFile) return null;
    // Watch targets: the main DB plus any WAL sidecar, so poll-fallback
    // change detection still sees writes that only hit the WAL.
    final sources = <String>[dbPath];
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = await fs.stat('$dbPath$suffix');
      if (sidecar.isFile) sources.add('$dbPath$suffix');
    }
    return OpencodeSqliteReadHandle(path: dbPath, sourcePaths: sources);
  }

  final fingerprint = await _sqliteStoreFingerprint(fs, dbPath);
  if (fingerprint == null) return null;

  final memo = _snapshots[dbPath];
  if (memo != null && memo.fingerprint == fingerprint) {
    return OpencodeSqliteReadHandle(
      path: memo.tempDbPath,
      sourcePaths: memo.sourcePaths,
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('opencode-snapshot-');
  final tempDbPath = p.join(tempDir.path, 'opencode.db');
  final copied = await copyOpencodeSqliteSnapshot(
    fs: fs,
    dbPath: dbPath,
    destDbPath: tempDbPath,
  );
  if (copied.isEmpty) {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // best-effort cleanup
    }
    return null;
  }

  final previous = _snapshots.remove(dbPath);
  if (previous != null) {
    try {
      await Directory(previous.tempDir).delete(recursive: true);
    } on Object {
      // best-effort cleanup
    }
  }
  _snapshots[dbPath] = _SqliteSnapshot(
    fingerprint: fingerprint,
    tempDbPath: tempDbPath,
    tempDir: tempDir.path,
    sourcePaths: copied,
  );
  if (_snapshots.length > _snapshotCap) {
    _snapshots.clear();
  }
  return OpencodeSqliteReadHandle(
    path: tempDbPath,
    sourcePaths: copied,
  );
}

final Map<String, _SqliteSnapshot> _snapshots = {};
const int _snapshotCap = 8;

/// Store change signal: mtime+size of `opencode.db` plus WAL sidecars (with
/// WAL the main file can stay static between checkpoints).
Future<String?> _sqliteStoreFingerprint(
  Filesystem fs,
  String dbPath,
) async {
  final parts = <String>[];
  for (final suffix in const ['', '-wal', '-shm']) {
    final st = await fs.stat('$dbPath$suffix');
    if (!st.isFile) continue;
    parts.add(
      '$suffix|${st.size ?? 0}|${st.mtime?.toUtc().toIso8601String() ?? ''}',
    );
  }
  return parts.isEmpty ? null : parts.join('\n');
}

class _SqliteSnapshot {
  const _SqliteSnapshot({
    required this.fingerprint,
    required this.tempDbPath,
    required this.tempDir,
    required this.sourcePaths,
  });

  final String fingerprint;
  final String tempDbPath;
  final String tempDir;
  final List<String> sourcePaths;
}
