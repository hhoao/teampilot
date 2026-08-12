import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../native_session_id.dart';

/// 行级增量状态:每个 message 的指纹 = (part 数, MAX(part.time_updated),
/// message.time_updated)。全量 parse 后由 [seedFromFullParse] 对齐,之后
/// 每次 refresh 只重读指纹变化的行并原地合并进 [messages]。
class OpencodeHistoryIncrementalState extends AiTranscriptIncrementalState {
  final Map<String, _MessageFingerprint> _seen = {};
  List<AiMessage> _messages = [];

  bool _unsupported = false;
  bool get unsupported => _unsupported;

  @override
  List<AiMessage> get messages => _messages;

  void _adopt(List<AiMessage> messages) {
    _messages = messages;
  }
}

class _MessageFingerprint {
  const _MessageFingerprint(this.partCount, this.maxPartUpdated, this.updated);

  final int partCount;
  final int? maxPartUpdated;
  final int? updated;

  @override
  bool operator ==(Object other) =>
      other is _MessageFingerprint &&
      other.partCount == partCount &&
      other.maxPartUpdated == maxPartUpdated &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(partCount, maxPartUpdated, updated);
}

/// opencode SQLite 的行级增量刷新器。
///
/// 一次 refresh 只跑一个 session 级聚合查询(索引覆盖,不读 data 大字段),
/// 指纹与上次不一致的 message 才重读行 + 单消息 parse,然后**原地**合并
/// 进 [OpencodeHistoryIncrementalState.messages](列表实例不变)。
/// 删除/压缩/计数回退/schema 不兼容 → 返回 null,loader 回退全量。
class OpencodeHistoryIncrementalRefresher
    implements AiTranscriptIncrementalRefresher {
  const OpencodeHistoryIncrementalRefresher();

  @override
  OpencodeHistoryIncrementalState createState() =>
      OpencodeHistoryIncrementalState();

  @override
  Future<void> seedFromFullParse({
    required SessionHistoryContext ctx,
    required List<AiMessage> messages,
    required AiTranscriptIncrementalState state,
  }) async {
    if (state is! OpencodeHistoryIncrementalState) return;
    final s = state;
    s._adopt(messages);
    s._seen.clear();
    final rows = await _readFingerprints(ctx);
    if (rows == null) {
      // DB 尚不存在(暂态,下次 seed 重试)与 schema 不兼容(永久回退
      // 全量)都表现为 null;只有 DB 存在且查询失败才标记不可增量,避免
      // 每轮都重新尝试。
      final dbPath = _dbPath(ctx);
      var exists = false;
      if (dbPath != null) {
        final st = await ctx.fs.stat(dbPath);
        exists = st.exists;
      }
      s._unsupported = exists;
      return;
    }
    s._unsupported = false;
    for (final row in rows) {
      s._seen[row.messageId] = _MessageFingerprint(
        row.partCount,
        row.maxPartUpdated,
        row.updated,
      );
    }
  }

  @override
  Future<AiTranscriptIncrementalResult?> refresh({
    required SessionHistoryContext ctx,
    required AiTranscriptIncrementalState state,
    bool force = false,
  }) async {
    if (force) return null;
    if (state is! OpencodeHistoryIncrementalState) return null;
    final s = state;
    if (s._unsupported) return null;
    if (s._seen.isEmpty) return null; // 尚未对齐 → 让 loader 走全量。

    final rows = await _readFingerprints(ctx);
    if (rows == null) return null;

    final rowIds = rows.map((r) => r.messageId).toSet();
    if (s._seen.keys.any((id) => !rowIds.contains(id))) {
      // 消息被删除/压缩 → 增量无法表达,回退全量重建。
      return null;
    }

    final changed = <String>[];
    for (final row in rows) {
      final seen = s._seen[row.messageId];
      final fp = _MessageFingerprint(
        row.partCount,
        row.maxPartUpdated,
        row.updated,
      );
      if (seen == null || seen != fp) {
        changed.add(row.messageId);
        s._seen[row.messageId] = fp;
      }
    }
    if (changed.isEmpty) {
      return (messages: s._messages, parentPath: _dbPath(ctx));
    }

    final bundles = await _loadMessageBundles(ctx, changed);
    if (bundles == null) return null;

    final parsed = <AiMessage>[];
    final adapter = const OpencodeAiTranscriptAdapter();
    for (final bundle in bundles) {
      parsed.addAll(await adapter.parse(bundle));
    }
    _mergeInPlace(s._messages, parsed);
    return (messages: s._messages, parentPath: _dbPath(ctx));
  }

  String? _dbPath(SessionHistoryContext ctx) {
    final dataDir = opencodeDataDirFromEnv(ctx);
    if (dataDir.isEmpty) return null;
    return ctx.fs.pathContext.join(dataDir, 'opencode.db');
  }
}

/// 把 [parsed](按 (createdMs, id) 排序的单消息 parse 结果)合并进 [target]。
///
/// - 新消息按 (createdMs, id) 插入正确位置;
/// - 已存在的消息原地替换;
/// - 最后对整个列表跑一次原地 assistant 合并,与全量
///   [finalizeAiMessagesForHistory] 语义完全一致。
void _mergeInPlace(List<AiMessage> target, List<AiMessage> parsed) {
  if (parsed.isEmpty) return;
  final byId = {for (final m in target) m.id: m};
  for (final message in parsed) {
    final existing = byId[message.id];
    if (existing == null) {
      final idx = _insertionIndex(target, message);
      target.insert(idx, message);
      byId[message.id] = message;
    } else {
      final idx = target.indexWhere((m) => m.id == message.id);
      target[idx] = message;
      byId[message.id] = message;
    }
  }
  coalesceAdjacentAssistantsInPlace(target);
}

int _insertionIndex(List<AiMessage> target, AiMessage message) {
  var lo = 0;
  var hi = target.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    final existing = target[mid];
    if (_compareMessageOrder(existing, message) <= 0) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

int _compareMessageOrder(AiMessage a, AiMessage b) {
  final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
  final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
  if (ta != tb) return ta.compareTo(tb);
  return a.id.compareTo(b.id);
}

typedef _FingerprintRow = ({
  String messageId,
  int partCount,
  int? maxPartUpdated,
  int? updated,
});

/// Session 级聚合指纹:一条索引查询,不读 data 大字段。
Future<List<_FingerprintRow>?> _readFingerprints(
  SessionHistoryContext ctx,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: ctx.fs.pathContext.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  return handle.read<List<_FingerprintRow>?>((db) {
    final rows = db.select(
      '''
SELECT m.id AS mid, m.time_updated AS mtu,
       COUNT(p.id) AS pc, MAX(p.time_updated) AS ptu
FROM message m
LEFT JOIN part p ON p.message_id = m.id
WHERE m.session_id = ?
GROUP BY m.id
''',
      [sessionId],
    );
    return [
      for (final row in rows)
        (
          messageId: '${row['mid']}',
          partCount: row['pc'] is int ? row['pc'] as int : 0,
          maxPartUpdated: row['ptu'] is int ? row['ptu'] as int : null,
          updated: row['mtu'] is int ? row['mtu'] as int : null,
        ),
    ];
  });
}

/// 重读 [messageIds] 的完整行(message data + 全部 part),构建单消息 bundle。
Future<List<AiTranscriptBundle>?> _loadMessageBundles(
  SessionHistoryContext ctx,
  List<String> messageIds,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: ctx.fs.pathContext.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  final bundles = await handle.read<List<AiTranscriptBundle>?>((
    db,
  ) {
    final out = <AiTranscriptBundle>[];
    for (final messageId in messageIds) {
      final messageRows = db.select(
        '''
SELECT id, data, time_created
FROM message
WHERE session_id = ? AND id = ?
''',
        [sessionId, messageId],
      );
      if (messageRows.isEmpty) continue;
      final fragments = _buildSqliteFragments(db, sessionId, messageRows);
      out.add(
        AiTranscriptBundle(
          adapterId: 'opencode',
          fragments: _toTranscriptFragments(fragments),
          hints: const {
            'sessionId': '',
            'source': 'sqlite',
            'incremental': 'true',
          },
        ),
      );
    }
    return out;
  });
  return bundles;
}

/// Locate OpenCode session/message/part files under the session data dir.
///
/// Prefers the legacy JSON tree (`storage/message|part`). When that is absent
/// (current OpenCode installs store rows in `opencode.db` with WAL), reads
/// SQLite — copying `-wal`/`-shm` sidecars so a live writer is visible — and
/// emits the same fragment layout so [OpencodeAiTranscriptAdapter] stays one
/// parser.
///
/// Fragment names:
/// - `session/{sessionId}.json`
/// - `message/{messageId}.json`
/// - `part/{messageID}/{partId}.json`
Future<AiTranscriptBundle?> locateOpencodeTranscript(
  SessionHistoryContext ctx,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;

  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;

  // The seat's own rows rarely move while a running task sub-agent streams
  // output into its own session, so the expensive full locate is memoized on
  // a seat-only fingerprint: a child write (new part rows in a child session)
  // must NOT re-read + re-decode the whole seat tree — the child resolves are
  // memoized independently.
  final memoKey = '$dataDir\u0000$sessionId';
  final fingerprint = await _seatFingerprint(ctx, dataDir, sessionId);
  if (fingerprint != null) {
    final memo = _parentBundles[memoKey];
    if (memo != null && memo.fingerprint == fingerprint) return memo.bundle;
  }

  final located = await locateOpencodeTranscriptForSession(ctx, sessionId);
  if (located != null && fingerprint != null) {
    _parentBundles[memoKey] = _ParentBundleMemo(
      fingerprint: fingerprint,
      bundle: located,
    );
    _evictParentBundles();
  }
  return located;
}

/// Seat-only change signal: part row count + newest `time_updated` for the
/// seat session itself (not its children).
Future<String?> _seatFingerprint(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: path.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  return handle.read<String?>((db) {
    final rows = db.select(
      'SELECT COUNT(*), MAX(time_updated) FROM part WHERE session_id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return '${rows.first['COUNT(*)']}|${rows.first['MAX(time_updated)']}';
  });
}

final Map<String, _ParentBundleMemo> _parentBundles = {};
const int _parentBundleCap = 16;

void _evictParentBundles() {
  if (_parentBundles.length <= _parentBundleCap) return;
  _parentBundles.removeWhere(
    (_, __) => _parentBundles.length > _parentBundleCap,
  );
}

@visibleForTesting
void clearOpencodeParentMemo() => _parentBundles.clear();

class _ParentBundleMemo {
  const _ParentBundleMemo({
    required this.fingerprint,
    required this.bundle,
  });

  final String fingerprint;
  final AiTranscriptBundle bundle;
}

/// Same [dataDir] resolution as [locateOpencodeTranscript], but loads an
/// explicit OpenCode native session id (child task sessions, nested inflate).
Future<AiTranscriptBundle?> locateOpencodeTranscriptForSession(
  SessionHistoryContext ctx,
  String sessionId,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final trimmed = sessionId.trim();
  if (trimmed.isEmpty) return null;

  final jsonBundle = await _locateJsonStorage(ctx, dataDir, trimmed);
  if (jsonBundle != null) return jsonBundle;

  return _locateSqliteStorage(ctx, dataDir, trimmed);
}

/// TeamPilot history context: dirname of absolute [OPENCODE_DB].
String opencodeDataDirFromEnv(SessionHistoryContext ctx) {
  final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
  if (db.isEmpty || db == ':memory:') return '';
  return ctx.fs.pathContext.dirname(db);
}

/// Live cache token for the loader: a fingerprint of the whole SQLite store.
///
/// Each session has its own `runtime/opencode/` data dir containing the seat
/// session *plus* its task-child sessions, so a store-wide fingerprint is a
/// correct "anything moved" signal: it changes when the seat writes a turn
/// (parent transcript refresh) and also when a running sub-agent appends to
/// its own child session (which is what lets the live refresh re-inflate and
/// follow the running task). The read is one cheap indexed count on the
/// direct read-only connection — no full-file copy.
///
/// Returns null when the store layout cannot be fingerprinted cheaply; the
/// loader then falls back to its default probe (which misses for OpenCode,
/// i.e. always reload — same as before).
Future<String?> opencodeLiveCacheToken(SessionHistoryContext ctx) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;

  final path = ctx.fs.pathContext;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: path.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  return handle.read<String?>((db) {
    final parts = db.select('SELECT COUNT(*), MAX(time_updated) FROM part');
    final sessions = db.select(
      'SELECT COUNT(*), MAX(time_updated) FROM session',
    );
    if (parts.isEmpty || sessions.isEmpty) return null;
    return 'oc|${parts.first['COUNT(*)']}|${parts.first['MAX(time_updated)']}'
        '|${sessions.first['COUNT(*)']}|${sessions.first['MAX(time_updated)']}';
  });
}

Future<AiTranscriptBundle?> _locateJsonStorage(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final messageDir = path.join(dataDir, 'storage', 'message', sessionId);
  final messageStat = await ctx.fs.stat(messageDir);
  if (!messageStat.isDirectory) return null;

  final messageFiles = await _listJsonFiles(ctx, messageDir);
  if (messageFiles.isEmpty) return null;

  final storageDir = path.join(dataDir, 'storage');
  final fragments = <AiTranscriptFragment>[];
  final readPaths = <String>[];

  final sessionPath = await _findSessionFile(ctx, dataDir, sessionId);
  if (sessionPath != null) {
    final bytes = await ctx.fs.readBytes(sessionPath);
    if (bytes != null) {
      readPaths.add(sessionPath);
      fragments.add(
        AiTranscriptFragment(name: 'session/$sessionId.json', bytes: bytes),
      );
    }
  }

  for (final filePath in messageFiles) {
    final bytes = await ctx.fs.readBytes(filePath);
    if (bytes == null) continue;
    readPaths.add(filePath);
    final messageId = path.basenameWithoutExtension(filePath);
    fragments.add(
      AiTranscriptFragment(name: 'message/$messageId.json', bytes: bytes),
    );
  }

  for (final filePath in messageFiles) {
    final messageId = path.basenameWithoutExtension(filePath);
    final partDir = path.join(dataDir, 'storage', 'part', messageId);
    final partFiles = await _listJsonFiles(ctx, partDir);
    for (final partPath in partFiles) {
      final bytes = await ctx.fs.readBytes(partPath);
      if (bytes == null) continue;
      readPaths.add(partPath);
      final partId = path.basenameWithoutExtension(partPath);
      fragments.add(
        AiTranscriptFragment(
          name: 'part/$messageId/$partId.json',
          bytes: bytes,
        ),
      );
    }
  }

  if (fragments.where((f) => f.name.startsWith('message/')).isEmpty) {
    return null;
  }

  final totalBytes =
      fragments.fold<int>(0, (sum, f) => sum + f.bytes.length);
  return AiTranscriptBundle(
    adapterId: 'opencode',
    fragments: fragments,
    hints: {
      'sessionId': sessionId,
      'source': 'json',
      'cacheToken': 'opencode-json|$sessionId|$totalBytes',
      ...AiHistoryWatchMeta(
        changeWatchRoot: storageDir,
        cacheTokenPaths: readPaths,
      ).toHints(),
    },
  );
}

/// Incremental sqlite locate: only messages with `id > [afterMessageId]`.
///
/// Uses the same read path + fragment builder as [_locateSqliteStorage]
/// so both callers share one consistent read.
Future<AiTranscriptBundle?> locateOpencodeTranscriptIncremental(
  SessionHistoryContext ctx, {
  required int afterMessageId,
}) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;

  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;

  final path = ctx.fs.pathContext;
  final dbPath = path.join(dataDir, 'opencode.db');
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: dbPath,
  );
  if (handle == null) return null;

  final read = await handle.read<({List<SqliteFragmentData> fragments, String lastId})?>(
    (db) {
      final messageRows = db.select(
        '''
SELECT id, data, time_created
FROM message
WHERE session_id = ? AND id > ?
ORDER BY id ASC
''',
        [sessionId, afterMessageId],
      );
      if (messageRows.isEmpty) return null;
      final fragments = _buildSqliteFragments(db, sessionId, messageRows);
      return (
        fragments: fragments,
        lastId: '${messageRows.last['id']}',
      );
    },
  );
  if (read == null) return null;

  final fragments = _toTranscriptFragments(read.fragments);
  if (fragments.where((f) => f.name.startsWith('message/')).isEmpty) {
    return null;
  }

  final lastId = read.lastId;
  return AiTranscriptBundle(
    adapterId: 'opencode',
    fragments: fragments,
    hints: {
      'sessionId': sessionId,
      'source': 'sqlite',
      'incremental': 'true',
      'afterMessageId': '$afterMessageId',
      'lastMessageId': lastId,
      'cacheToken': 'opencode-sqlite|$sessionId|$lastId',
      ...AiHistoryWatchMeta(
        changeWatchRoot: dataDir,
        cacheTokenPaths: handle.sourcePaths,
      ).toHints(),
    },
  );
}

Future<AiTranscriptBundle?> _locateSqliteStorage(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final dbPath = path.join(dataDir, 'opencode.db');
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: dbPath,
  );
  if (handle == null) return null;

  final fragmentsData = await handle.read<List<SqliteFragmentData>>((db) {
    final messageRows = db.select(
      '''
SELECT id, data, time_created
FROM message
WHERE session_id = ?
ORDER BY time_created ASC, id ASC
''',
      [sessionId],
    );
    if (messageRows.isEmpty) return null;
    return _buildSqliteFragments(db, sessionId, messageRows);
  });
  if (fragmentsData == null) return null;
  final fragments = _toTranscriptFragments(fragmentsData);
  if (fragments.where((f) => f.name.startsWith('message/')).isEmpty) {
    return null;
  }

  final totalBytes = fragments.fold<int>(0, (sum, f) => sum + f.bytes.length);
  return AiTranscriptBundle(
    adapterId: 'opencode',
    fragments: fragments,
    hints: {
      'sessionId': sessionId,
      'source': 'sqlite',
      'cacheToken': 'opencode-sqlite|$sessionId|$totalBytes',
      ...AiHistoryWatchMeta(
        changeWatchRoot: dataDir,
        cacheTokenPaths: handle.sourcePaths,
      ).toHints(),
    },
  );
}

/// Converts sendable fragment data (built on a worker isolate) back into
/// [AiTranscriptFragment]s on the UI isolate.
List<AiTranscriptFragment> _toTranscriptFragments(
  List<SqliteFragmentData> data,
) {
  return [
    for (final d in data) AiTranscriptFragment(name: d.name, bytes: d.bytes),
  ];
}

/// Message → `message/{id}.json` (+ parts → `part/{messageId}/{partId}.json`)
/// fragments, shared by the full and incremental sqlite locates.
///
/// Returns sendable name+bytes records so the whole query + fragment build can
/// run on a worker isolate ([OpencodeSqliteReadHandle.read]).
typedef SqliteFragmentData = ({String name, List<int> bytes});

List<SqliteFragmentData> _buildSqliteFragments(
  Database db,
  String sessionId,
  List<Row> messageRows,
) {
  final fragments = <SqliteFragmentData>[];

  // Batch the per-message part lookups into one session-scoped query; the
  // old N+1 (one `WHERE message_id = ?` per message) multiplied the query
  // count by the message count on every live refresh. Schemas without the
  // `part.session_id` column fall back to the per-message queries.
  final partsByMessage = <String, List<Row>>{};
  var batchedParts = false;
  try {
    final partRows = db.select(
      '''
SELECT id, message_id, data, time_created
FROM part
WHERE session_id = ?
ORDER BY time_created ASC, id ASC
''',
      [sessionId],
    );
    for (final part in partRows) {
      partsByMessage
          .putIfAbsent('${part['message_id']}', () => <Row>[])
          .add(part);
    }
    batchedParts = true;
  } on SqliteException {
    // Legacy schema without `part.session_id`; fall back below.
  }

  for (final row in messageRows) {
    final messageId = '${row['id']}';
    final raw = row['data'];
    final obj = _decodeDbJson(raw);
    if (obj == null) continue;
    obj.putIfAbsent('id', () => messageId);
    obj.putIfAbsent('sessionID', () => sessionId);
    final time = obj['time'];
    if (time is! Map) {
      final created = row['time_created'];
      if (created is int) {
        obj['time'] = {'created': created};
      }
    }
    fragments.add((
      name: 'message/$messageId.json',
      bytes: utf8.encode(jsonEncode(obj)),
    ));

    final partsForMessage = batchedParts
        ? partsByMessage[messageId] ?? const <Row>[]
        : db.select(
            '''
SELECT id, data, time_created
FROM part
WHERE message_id = ?
ORDER BY time_created ASC, id ASC
''',
            [messageId],
          );
    for (final part in partsForMessage) {
      final partId = '${part['id']}';
      final partObj = _decodeDbJson(part['data']);
      if (partObj == null) continue;
      partObj.putIfAbsent('id', () => partId);
      partObj.putIfAbsent('messageID', () => messageId);
      fragments.add((
        name: 'part/$messageId/$partId.json',
        bytes: utf8.encode(jsonEncode(partObj)),
      ));
    }
  }
  return fragments;
}

Map<String, dynamic>? _decodeDbJson(Object? raw) {
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

Future<String?> _resolveSessionId(
  SessionHistoryContext ctx,
  String dataDir,
) {
  return resolveOpencodeNativeSessionId(
    fs: ctx.fs,
    dataDir: dataDir,
    persistedNativeId: ctx.persistedNativeId,
  );
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

Future<List<String>> _listJsonFiles(
  SessionHistoryContext ctx,
  String dir,
) async {
  final stat = await ctx.fs.stat(dir);
  if (!stat.isDirectory) return const [];
  final path = ctx.fs.pathContext;
  final out = <String>[];
  try {
    final entries = await ctx.fs.listDir(dir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (!e.name.endsWith('.json')) continue;
      out.add(path.join(dir, e.name));
    }
  } on Object {
    return const [];
  }
  out.sort();
  return out;
}

/// OpenCode storage fragments → [AiMessage] with text / tool-call parts.
final class OpencodeAiTranscriptAdapter implements AiTranscriptAdapter {
  const OpencodeAiTranscriptAdapter();

  @override
  String get id => 'opencode';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final messageInfos = <_OcMessage>[];
    final partsByMessage = <String, List<Map<String, dynamic>>>{};

    for (final fragment in bundle.fragments) {
      final name = fragment.name;
      final content = utf8.decode(fragment.bytes, allowMalformed: true);
      if (name.startsWith('message/')) {
        final obj = _tryDecodeObject(content);
        if (obj == null) continue;
        final id = '${obj['id'] ?? ''}'.trim();
        final role = '${obj['role'] ?? ''}'.trim();
        if (id.isEmpty || (role != 'user' && role != 'assistant')) continue;
        messageInfos.add(
          _OcMessage(
            id: id,
            role: role,
            createdMs: _createdMs(obj['time']),
          ),
        );
      } else if (name.startsWith('part/')) {
        // part/{messageId}/{partId}.json
        final segments = name.split('/');
        if (segments.length < 3) continue;
        final messageId = segments[1];
        final obj = _tryDecodeObject(content);
        if (obj == null) continue;
        partsByMessage.putIfAbsent(messageId, () => []).add(obj);
      }
    }

    messageInfos.sort((a, b) {
      final byTime = a.createdMs.compareTo(b.createdMs);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });

    final messages = <AiMessage>[];
    for (final info in messageInfos) {
      final partsRaw = partsByMessage[info.id] ?? const [];
      // Stable order by part id when present.
      final sorted = List<Map<String, dynamic>>.of(partsRaw)
        ..sort((a, b) => '${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}'));

      final parts = <AiMessagePart>[];
      for (final part in sorted) {
        parts.addAll(_partsFromOcPart(part, info));
      }
      if (parts.isEmpty) continue;

      messages.add(
        AiMessage(
          id: info.id,
          role: info.role == 'user' ? AiRole.user : AiRole.assistant,
          parts: parts,
          createdAt: info.createdMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(info.createdMs, isUtc: true)
              : null,
        ),
      );
    }

    return finalizeAiMessagesForHistory(messages);
  }
}

class _OcMessage {
  const _OcMessage({
    required this.id,
    required this.role,
    required this.createdMs,
  });

  final String id;
  final String role;
  final int createdMs;
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

int _createdMs(Object? time) {
  if (time is Map) {
    final created = time['created'];
    if (created is num) return created.toInt();
  }
  return 0;
}

Iterable<AiMessagePart> _partsFromOcPart(
  Map<String, dynamic> part,
  _OcMessage message,
) {
  final type = part['type'];
  switch (type) {
    case 'text':
      if (part['synthetic'] == true || part['ignored'] == true) {
        return const [];
      }
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isEmpty) return const [];
      return [AiTextPart(text: text)];
    case 'reasoning':
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isEmpty) return const [];
      return [AiReasoningPart(text: text)];
    case 'tool':
      if (message.role != 'assistant') return const [];
      final toolName = '${part['tool'] ?? ''}'.trim();
      final callId = '${part['callID'] ?? part['id'] ?? ''}'.trim();
      if (callId.isEmpty) return const [];
      final name = toolName.isEmpty ? 'tool' : toolName;
      final stateRaw = part['state'];
      if (stateRaw is! Map) {
        return [
          AiToolCallPart(toolCallId: callId, toolName: name),
        ];
      }
      final state = Map<String, dynamic>.from(stateRaw);
      final statusRaw = '${state['status'] ?? ''}';
      final isError = statusRaw == 'error';
      Object? result;
      AiToolCallStatus status;
      if (statusRaw == 'completed') {
        result = '${state['output'] ?? ''}';
        status = AiToolCallStatus.complete;
      } else if (isError) {
        final error = '${state['error'] ?? ''}'.trim();
        result = error.isEmpty ? null : error;
        status = AiToolCallStatus.complete;
      } else if (statusRaw == 'pending' ||
          statusRaw == 'running' ||
          statusRaw.isEmpty) {
        status = AiToolCallStatus.incomplete;
      } else {
        status = AiToolCallStatus.incomplete;
      }
      return [
        AiToolCallPart(
          toolCallId: callId,
          toolName: name,
          args: _asArgs(state['input']),
          result: result,
          status: status,
          isError: isError,
        ),
      ];
    default:
      return const [];
  }
}

Map<String, Object?>? _asArgs(Object? input) {
  if (input is! Map) return null;
  return {
    for (final entry in input.entries) '${entry.key}': entry.value,
  };
}
