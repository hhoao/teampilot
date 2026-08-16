import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../../utils/logging/logger.dart';
import '../../../../session/session_history_context.dart';
import 'ai_transcript.dart';
import '../native_session_id.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';

// Real opencode task outputs embed the child session id as
// `<task id="ses_..." state="completed">` (plus optional extra attributes),
// so the tag must tolerate attributes between the id and the closing `>`.
final _opencodeTaskIdPattern = RegExp(r'<task id="(ses_[^"]+)"[^>]*>');

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
    // Discovery only makes sense while the task is genuinely running: an
    // error/completed result without a session id has no live child to follow,
    // and scanning the store for it on every refresh is pure waste.
    final needsDiscovery =
        (childSessionId == null || childSessionId.isEmpty) &&
        part.status == AiToolCallStatus.incomplete;
    final resolvedId = needsDiscovery
        ? await _discoverRunningChildSession(
            ctx: ctx,
            parentSessionId: _parentSessionId(ctx, parentHandle),
            toolCallId: part.toolCallId,
            toolCallAt: toolCallAt,
          )
        : childSessionId;
    if (resolvedId == null || resolvedId.isEmpty) return null;

    // 子会话结果 memo:指纹未变时复用同一解析结果(消息列表实例相同),
    // 让 loader/seat 的 identical 快速路径生效——活跃子 agent 每 tick 重
    // inflate 时,未变化的子会话零重解析、零内容比较;子会话移动才重解析。
    final fingerprint = await _childFingerprint(ctx, resolvedId);
    if (fingerprint != null) {
      final memo = _childResults[resolvedId];
      if (memo != null && memo.fingerprint == fingerprint) {
        return memo.result;
      }
    }

    final bundle = await _bundleForChild(ctx, resolvedId);
    if (bundle == null) return null;

    try {
      final messages = await const OpencodeAiTranscriptAdapter().parse(bundle);
      final result = SubagentSideResolveResult(
        messages: messages,
        handle: SubagentSessionHandle(resolvedId),
      );
      if (fingerprint != null) {
        _childResults[resolvedId] = _ChildResultMemo(
          fingerprint: fingerprint,
          result: result,
        );
        _evictChildResults();
      }
      return result;
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

  /// Child bundle with an mtime-validated memo: a session with a dozen task
  /// children would otherwise re-query + re-parse every child on each live
  /// refresh even though only the running one moved.
  Future<AiTranscriptBundle?> _bundleForChild(
    SessionHistoryContext ctx,
    String childId,
  ) async {
    final fingerprint = await _childFingerprint(ctx, childId);
    if (fingerprint == null) {
      return locateOpencodeTranscriptForSession(ctx, childId);
    }
    final memo = _childBundles[childId];
    if (memo != null && memo.fingerprint == fingerprint) {
      return memo.bundle;
    }
    final bundle = await locateOpencodeTranscriptForSession(ctx, childId);
    if (bundle != null) {
      _childBundles[childId] = _ChildBundleMemo(
        fingerprint: fingerprint,
        bundle: bundle,
      );
      _evictChildBundles();
    }
    return bundle;
  }

  static final Map<String, _ChildBundleMemo> _childBundles = {};
  static const int _childBundleCap = 64;

  static void _evictChildBundles() {
    if (_childBundles.length <= _childBundleCap) return;
    _childBundles.removeWhere(
      (_, __) => _childBundles.length > _childBundleCap,
    );
  }

  @visibleForTesting
  static void clearChildBundleMemo() => _childBundles.clear();

  /// childId → 已解析结果(见 [resolve] 的注释):指纹未变时复用同一
  /// 消息列表实例。与 [_childBundles] 的淘汰策略一致。
  static final Map<String, _ChildResultMemo> _childResults = {};
  static const int _childResultCap = 64;

  static void _evictChildResults() {
    if (_childResults.length <= _childResultCap) return;
    _childResults.removeWhere(
      (_, __) => _childResults.length > _childResultCap,
    );
  }

  @visibleForTesting
  static void clearChildResultMemo() => _childResults.clear();

  /// Cheap change signal for one child session: part row count + newest
  /// `time_updated` (parts are appended/updated while a task streams output).
  Future<String?> _childFingerprint(
    SessionHistoryContext ctx,
    String childId,
  ) async {
    final dataDir = opencodeDataDirFromEnv(ctx);
    if (dataDir.isEmpty) return null;
    final path = ctx.fs.pathContext;
    final handle = await resolveOpencodeSqliteReadPath(
      fs: ctx.fs,
      dbPath: path.join(dataDir, 'opencode.db'),
    );
    if (handle == null) return null;

    return handle.read<String?>(_childFingerprintQuery, childId);
  }

  /// Child 会话指纹查询(worker isolate 上执行,args = childId)。
  static String? _childFingerprintQuery(Database db, Object? args) {
    final childId = args as String;
    final rows = db.select(
      'SELECT COUNT(*), MAX(time_updated) FROM part WHERE session_id = ?',
      [childId],
    );
    if (rows.isEmpty) return null;
    return '${rows.first['COUNT(*)']}|${rows.first['MAX(time_updated)']}';
  }

  /// While a `task` sub-agent runs, OpenCode only writes the child `ses_*`
  /// id into the tool result once the task finishes. Discover the running
  /// child by scanning sessions whose parent linkage points at this session;
  /// the child transcript itself is appended live, so the preview can follow
  /// it. Returns null when nothing matches (or the layout is unavailable).
  ///
  /// The scan is memoized per (dataDir, parent, toolCallId) on a cheap store
  /// fingerprint (`opencode.db`/WAL mtime+size) so the live refresh does not
  /// copy the whole database on every tick while a task runs — the store only
  /// re-scans when it actually moved.
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

  Future<String?> _discoverFromSqlite(
    SessionHistoryContext ctx, {
    required String dataDir,
    required String parentSessionId,
    required DateTime? toolCallAt,
  }) async {
    final path = ctx.fs.pathContext;
    final dbPath = path.join(dataDir, 'opencode.db');
    final handle = await resolveOpencodeSqliteReadPath(
      fs: ctx.fs,
      dbPath: dbPath,
    );
    if (handle == null) return null;

    return handle.read<String?>(_discoverChildQuery, {
      'parentSessionId': parentSessionId,
      'toolCallAt': toolCallAt,
    });
  }

  /// 子会话发现查询(worker isolate 上执行,args = {parentSessionId,
  /// toolCallAt})。
  static String? _discoverChildQuery(Database db, Object? args) {
    final map = args as Map<String, Object?>;
    final parentSessionId = map['parentSessionId'] as String;
    final toolCallAt = map['toolCallAt'] as DateTime?;
    final candidates = <({String id, int createdMs})>[];
    try {
      // Current OpenCode layout: `parent_id` is a real column — one
      // indexed scoped query, no full-scan + JSON decode.
      final rows = db.select(
        'SELECT id, time_created FROM session WHERE parent_id = ?',
        [parentSessionId],
      );
      for (final row in rows) {
        final id = '${row['id']}'.trim();
        if (!id.startsWith('ses_')) continue;
        final ms = _intValue(row['time_created']);
        if (ms <= 0) continue;
        candidates.add((id: id, createdMs: ms));
      }
    } on SqliteException {
      // Legacy layout: parent linkage inside the `data` JSON blob.
      final rows = db.select('SELECT id, data, time_created FROM session');
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
    }
    return OpencodeSideResolver._pickRunningChild(candidates, toolCallAt);
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

class _ChildBundleMemo {
  const _ChildBundleMemo({
    required this.fingerprint,
    required this.bundle,
  });

  final String fingerprint;
  final AiTranscriptBundle bundle;
}

/// 子会话解析结果 memo(见 [OpencodeSideResolver.resolve] 的注释)。
class _ChildResultMemo {
  const _ChildResultMemo({
    required this.fingerprint,
    required this.result,
  });

  final String fingerprint;
  final SubagentSideResolveResult result;
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
