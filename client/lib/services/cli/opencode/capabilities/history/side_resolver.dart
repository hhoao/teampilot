import 'dart:convert';
import 'dart:io' show Directory;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import 'ai_transcript.dart';
import '../native_session_id.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

final _opencodeTaskIdPattern = RegExp(r'<task id="(ses_[^"]+)">');

String? opencodeChildSessionId(AiToolCallPart part) {
  final result = part.result;
  if (result is Map) {
    final map = Map<String, dynamic>.from(result);
    final direct = _trimmedSessionId(map['sessionId']);
    if (direct != null) return direct;

    final metadata = map['metadata'];
    if (metadata is Map) {
      final fromMeta = _trimmedSessionId(
        Map<String, dynamic>.from(metadata)['sessionId'],
      );
      if (fromMeta != null) return fromMeta;
    }
  }

  final text = switch (result) {
    String s => s,
    null => null,
    _ => result.toString(),
  };
  if (text == null || text.isEmpty) return null;

  final match = _opencodeTaskIdPattern.firstMatch(text);
  return match?.group(1);
}

String? _trimmedSessionId(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

final class OpencodeSideResolver implements SubagentSideResolver {
  const OpencodeSideResolver();

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    final childSessionId = opencodeChildSessionId(part);
    final resolvedId =
        (childSessionId == null || childSessionId.isEmpty)
        ? await _discoverRunningChildSession(
            ctx: ctx,
            parentSessionId: _parentSessionId(ctx, parentHandle),
            toolCallId: part.toolCallId,
            toolCallAt: toolCallAt,
          )
        : childSessionId;
    if (resolvedId == null || resolvedId.isEmpty) return null;

    final bundle = await locateOpencodeTranscriptForSession(ctx, resolvedId);
    if (bundle == null) return null;

    if (childSessionId != null && childSessionId.isNotEmpty) {
      await _logParentIdMismatchIfNeeded(
        ctx: ctx,
        bundle: bundle,
        childSessionId: childSessionId,
        parentSessionId: _parentSessionId(ctx, parentHandle),
      );
    }

    try {
      final messages = await const OpencodeAiTranscriptAdapter().parse(bundle);
      return SubagentSideResolveResult(
        messages: messages,
        handle: SubagentSessionHandle(resolvedId),
      );
    } catch (e, st) {
      appLogger.w(
        '[subagent-inflate] OpenCode child session failed '
        'sessionId=$resolvedId: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// While a `task` sub-agent runs, OpenCode only writes the child `ses_*`
  /// id into the tool result once the task finishes. Discover the running
  /// child by scanning sessions whose parent linkage points at this session;
  /// the child transcript itself is appended live, so the preview can follow
  /// it. Returns null when nothing matches (or the layout is unavailable).
  ///
  /// The scan is memoized per (dataDir, parent, toolCallId) on a cheap store
  /// fingerprint (SQLite: `opencode.db`/WAL mtime+size; JSON: `storage/session`
  /// listing) so the 750ms live refresh does not copy the whole database (or
  /// re-read every session file) on every tick while a task runs — the store
  /// only re-scan when it actually moved.
  Future<String?> _discoverRunningChildSession({
    required SessionHistoryContext ctx,
    required String? parentSessionId,
    required String toolCallId,
    required DateTime? toolCallAt,
  }) async {
    final parent = parentSessionId?.trim() ?? '';
    if (parent.isEmpty) return null;
    final dataDir = opencodeDataDirFromEnv(ctx);
    if (dataDir.isEmpty) return null;

    final memoKey = '$dataDir\u0000$parent\u0000$toolCallId'
        '\u0000${toolCallAt?.toUtc().millisecondsSinceEpoch ?? ''}';

    final jsonFingerprint = await _jsonStorageFingerprint(ctx, dataDir);
    if (jsonFingerprint != null) {
      final cached = _cachedDiscovery(memoKey, jsonFingerprint);
      if (cached != null) return cached;
      final found = await _discoverFromJsonStorage(
        ctx,
        dataDir: dataDir,
        parentSessionId: parent,
        toolCallAt: toolCallAt,
      );
      if (found != null) {
        _rememberDiscovery(memoKey, jsonFingerprint, found);
        return found;
      }
    }

    final sqliteFingerprint = await _sqliteFingerprint(ctx, dataDir);
    if (sqliteFingerprint != null) {
      final cached = _cachedDiscovery(memoKey, sqliteFingerprint);
      if (cached != null) return cached;
      final found = await _discoverFromSqlite(
        ctx,
        dataDir: dataDir,
        parentSessionId: parent,
        toolCallAt: toolCallAt,
      );
      if (found != null) {
        _rememberDiscovery(memoKey, sqliteFingerprint, found);
        return found;
      }
    }

    return null;
  }

  /// JSON storage listing token (name+size+mtime of every `ses_*.json`);
  /// null when the legacy `storage/session` tree is absent.
  static Future<String?> _jsonStorageFingerprint(
    SessionHistoryContext ctx,
    String dataDir,
  ) async {
    final path = ctx.fs.pathContext;
    final sessionDir = path.join(dataDir, 'storage', 'session');
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDirRecursive(sessionDir);
    } on Object {
      return null;
    }
    final parts = <String>[];
    for (final e in entries) {
      if (e.isDirectory) continue;
      final name = path.basename(e.name);
      if (!name.startsWith('ses_') || !name.endsWith('.json')) continue;
      final st = await ctx.fs.stat(path.join(sessionDir, e.name));
      if (!st.isFile) continue;
      parts.add('${name}|${st.size ?? 0}|${st.mtime?.toUtc().toIso8601String() ?? ''}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// SQLite store token: mtime+size of `opencode.db` plus its WAL sidecars
  /// (with WAL the main file can stay static between checkpoints); null when
  /// the database is absent.
  static Future<String?> _sqliteFingerprint(
    SessionHistoryContext ctx,
    String dataDir,
  ) async {
    final path = ctx.fs.pathContext;
    final dbPath = path.join(dataDir, 'opencode.db');
    final parts = <String>[];
    for (final suffix in const ['', '-wal', '-shm']) {
      final st = await ctx.fs.stat('$dbPath$suffix');
      if (!st.isFile) continue;
      parts.add('$suffix|${st.size ?? 0}|${st.mtime?.toUtc().toIso8601String() ?? ''}');
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  static final Map<String, _ChildDiscoveryMemo> _discoveryMemo = {};
  static const int _discoveryMemoCap = 32;

  @visibleForTesting
  static void clearDiscoveryMemo() => _discoveryMemo.clear();

  static String? _cachedDiscovery(String key, String fingerprint) {
    final memo = _discoveryMemo[key];
    if (memo == null) return null;
    return memo.fingerprint == fingerprint ? memo.childId : null;
  }

  static void _rememberDiscovery(String key, String fingerprint, String childId) {
    if (_discoveryMemo.length >= _discoveryMemoCap) {
      _discoveryMemo.clear();
    }
    _discoveryMemo[key] = _ChildDiscoveryMemo(
      fingerprint: fingerprint,
      childId: childId,
    );
  }

  Future<String?> _discoverFromJsonStorage(
    SessionHistoryContext ctx, {
    required String dataDir,
    required String parentSessionId,
    required DateTime? toolCallAt,
  }) async {
    final path = ctx.fs.pathContext;
    final sessionDir = path.join(dataDir, 'storage', 'session');
    List<FsDirEntry> entries;
    try {
      entries = await ctx.fs.listDirRecursive(sessionDir);
    } on Object {
      return null;
    }

    final candidates = <({String id, int createdMs})>[];
    for (final e in entries) {
      if (e.isDirectory) continue;
      final name = path.basename(e.name);
      if (!name.startsWith('ses_') || !name.endsWith('.json')) continue;
      final bytes = await ctx.fs.readBytes(path.join(sessionDir, e.name));
      if (bytes == null) continue;
      final obj = _tryDecodeObject(utf8.decode(bytes, allowMalformed: true));
      if (obj == null) continue;
      final parentOf = _parentOf(obj);
      if (parentOf != parentSessionId) continue;
      final created = _createdMs(obj['time']);
      if (created <= 0) continue;
      candidates.add((
        id: name.substring(0, name.length - '.json'.length),
        createdMs: created,
      ));
    }
    return _pickRunningChild(candidates, toolCallAt);
  }

  Future<String?> _discoverFromSqlite(
    SessionHistoryContext ctx, {
    required String dataDir,
    required String parentSessionId,
    required DateTime? toolCallAt,
  }) async {
    final path = ctx.fs.pathContext;
    final dbPath = path.join(dataDir, 'opencode.db');
    if (!await opencodeSqliteMainExists(ctx.fs, dbPath)) return null;

    Directory? tempDir;
    Database? db;
    try {
      tempDir = await Directory.systemTemp.createTemp('opencode-child-');
      final tempDbPath = path.join(tempDir.path, 'opencode.db');
      final copied = await copyOpencodeSqliteSnapshot(
        fs: ctx.fs,
        dbPath: dbPath,
        destDbPath: tempDbPath,
      );
      if (copied.isEmpty) return null;
      db = sqlite3.open(tempDbPath, mode: OpenMode.readOnly);

      final rows = db.select('SELECT id, data, time_created FROM session');
      final candidates = <({String id, int createdMs})>[];
      for (final row in rows) {
        final id = '${row['id']}'.trim();
        if (!id.startsWith('ses_')) continue;
        final obj = _decodeRowData(row['data']);
        if (obj == null) continue;
        if (_parentOf(obj) != parentSessionId) continue;
        final created = _createdMs(obj['time']);
        final ms = created > 0 ? created : _intValue(row['time_created']);
        if (ms <= 0) continue;
        candidates.add((id: id, createdMs: ms));
      }
      return _pickRunningChild(candidates, toolCallAt);
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

  /// Prefer the child created at/after the tool call time (earliest such —
  /// sequential spawns), else the newest child of this session.
  static String? _pickRunningChild(
    List<({String id, int createdMs})> candidates,
    DateTime? toolCallAt,
  ) {
    if (candidates.isEmpty) return null;
    final atMs = toolCallAt?.toUtc().millisecondsSinceEpoch;
    if (atMs != null) {
      final sorted = List.of(candidates)
        ..sort((a, b) => a.createdMs.compareTo(b.createdMs));
      for (final c in sorted) {
        if (c.createdMs >= atMs) return c.id;
      }
    }
    String bestId = '';
    var bestMs = -1;
    for (final c in candidates) {
      if (c.createdMs > bestMs) {
        bestMs = c.createdMs;
        bestId = c.id;
      }
    }
    return bestId.isEmpty ? null : bestId;
  }

  static String _parentOf(Map<String, dynamic> obj) =>
      '${obj['parent_id'] ?? obj['parentID'] ?? ''}'.trim();

  static Map<String, dynamic>? _decodeRowData(Object? raw) {
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

  static int _createdMs(Object? time) {
    if (time is Map) {
      final created = time['created'];
      if (created is num) return created.toInt();
    }
    return 0;
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  // OpenCode never hits the loader's parent cache token (its transcript is a
  // JSON/SQLite tree, not a `{taskId}.jsonl` under projects/), so every live
  // refresh re-inflates already — no fingerprint needed.
  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => null;
}

class _ChildDiscoveryMemo {
  const _ChildDiscoveryMemo({
    required this.fingerprint,
    required this.childId,
  });

  final String fingerprint;
  final String childId;
}

String? _parentSessionId(
  SessionHistoryContext ctx,
  SubagentSideHandle? parentHandle,
) {
  if (parentHandle is SubagentSessionHandle) {
    final id = parentHandle.sessionId.trim();
    if (id.isNotEmpty) return id;
  }
  final persisted = ctx.persistedNativeId?.trim();
  if (persisted != null && persisted.isNotEmpty) return persisted;
  return null;
}

Future<void> _logParentIdMismatchIfNeeded({
  required SessionHistoryContext ctx,
  required AiTranscriptBundle bundle,
  required String childSessionId,
  required String? parentSessionId,
}) async {
  final expectedParent = parentSessionId?.trim();
  if (expectedParent == null || expectedParent.isEmpty) return;

  final sessionMeta = await _sessionMetaFromBundle(ctx, bundle, childSessionId);
  if (sessionMeta == null) return;

  final actualParent =
      '${sessionMeta['parent_id'] ?? sessionMeta['parentID'] ?? ''}'.trim();
  if (actualParent.isEmpty || actualParent == expectedParent) return;

  appLogger.w(
    '[subagent-inflate] OpenCode child session parent_id mismatch '
    'child=$childSessionId expectedParent=$expectedParent '
    'actualParent=$actualParent',
  );
}

Future<Map<String, dynamic>?> _sessionMetaFromBundle(
  SessionHistoryContext ctx,
  AiTranscriptBundle bundle,
  String sessionId,
) async {
  for (final fragment in bundle.fragments) {
    if (!fragment.name.startsWith('session/')) continue;
    final obj = _tryDecodeObject(
      utf8.decode(fragment.bytes, allowMalformed: true),
    );
    if (obj != null) return obj;
  }

  final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
  if (db.isEmpty || db == ':memory:') return null;
  final dataDir = ctx.fs.pathContext.dirname(db);
  final sessionPath = await _findSessionFile(ctx, dataDir, sessionId);
  if (sessionPath == null) return null;

  final bytes = await ctx.fs.readBytes(sessionPath);
  if (bytes == null) return null;
  return _tryDecodeObject(utf8.decode(bytes, allowMalformed: true));
}

Future<String?> _findSessionFile(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final sessionDir = path.join(dataDir, 'storage', 'session');
  try {
    final entries = await ctx.fs.listDirRecursive(sessionDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (path.basename(e.name) != '$sessionId.json') continue;
      return path.join(sessionDir, e.name);
    }
  } on Object {
    return null;
  }
  return null;
}

Map<String, dynamic>? _tryDecodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}
