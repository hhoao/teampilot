import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../chat/conversation/history/ai_history_watch_meta.dart';
import '../../../../chat/conversation/history/session_history_context.dart';
import '../../../registry/capabilities/ai_history_capability.dart';
import '../native_session_id.dart';
import 'ai_transcript_adapter.dart';

export 'ai_transcript_adapter.dart';

/// 行级增量状态:每个 `session_message` 的指纹 = (seq, time_updated)。
/// 全量 parse 后由 [seedFromFullParse] 对齐,之后每次 refresh 只重读
/// 指纹变化的行并原地合并进 [messages]。
class OpencodeHistoryIncrementalState extends AiTranscriptIncrementalState {
  final Map<String, _MessageFingerprint> _seen = {};
  List<AiMessage> _messages = [];

  /// seed 时解析并固定的 seat 会话 id。增量刷新全部读取固定用它,避免
  /// 每次按"最新会话"重新解析——task 子会话活跃时最新会话会翻转到
  /// 子会话,导致指纹/重读落在子会话上:与 seed 的父会话不一致 → 反复
  /// 回退全量(重复解析),或父/子消息混入同一列表(同内容不同 ses_ id
  /// → 页面出现重复气泡)。
  String? sessionId;

  bool _unsupported = false;
  bool get unsupported => _unsupported;

  @override
  List<AiMessage> get messages => _messages;

  void _adopt(List<AiMessage> messages) {
    _messages = messages;
  }
}

class _MessageFingerprint {
  const _MessageFingerprint(this.seq, this.updated);

  final int seq;
  final int? updated;

  @override
  bool operator ==(Object other) =>
      other is _MessageFingerprint &&
      other.seq == seq &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(seq, updated);
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
    final dataDir = opencodeDataDirFromEnv(ctx);
    final sessionId = dataDir.isEmpty
        ? null
        : await _resolveSessionId(ctx, dataDir);
    s.sessionId = sessionId;
    final rows = sessionId == null
        ? null
        : await _readFingerprints(ctx, sessionId);
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
      s._seen[row.messageId] = _MessageFingerprint(row.seq, row.updated);
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
    final sessionId = s.sessionId;
    if (sessionId == null) return null;

    final rows = await _readFingerprints(ctx, sessionId);
    if (rows == null) return null;

    final rowIds = rows.map((r) => r.messageId).toSet();
    if (s._seen.keys.any((id) => !rowIds.contains(id))) {
      // 消息被删除/压缩 → 增量无法表达,回退全量重建。
      return null;
    }

    final changed = <String>[];
    for (final row in rows) {
      final seen = s._seen[row.messageId];
      final fp = _MessageFingerprint(row.seq, row.updated);
      if (seen == null || seen != fp) {
        changed.add(row.messageId);
        s._seen[row.messageId] = fp;
      }
    }
    if (changed.isEmpty) {
      return (messages: s._messages, parentPath: _dbPath(ctx));
    }

    final bundles = await _loadMessageBundles(ctx, sessionId, changed);
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

typedef _FingerprintRow = ({String messageId, int seq, int? updated});

/// Session 级聚合指纹:一条索引查询,不读 data 大字段。
/// [sessionId] 由调用方传入(增量状态 seed 时固定),不在查询内重新解析。
Future<List<_FingerprintRow>?> _readFingerprints(
  SessionHistoryContext ctx,
  String sessionId,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: ctx.fs.pathContext.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  return handle.read<List<_FingerprintRow>?>(_readFingerprintsQuery, sessionId);
}

/// 行级指纹查询(worker isolate 上执行,args = sessionId)。
List<_FingerprintRow>? _readFingerprintsQuery(Database db, Object? args) {
  final sessionId = args as String;
  final rows = db.select(
    '''
SELECT id, seq, time_updated
FROM session_message
WHERE session_id = ?
ORDER BY seq ASC, id ASC
''',
    [sessionId],
  );
  return [
    for (final row in rows)
      (
        messageId: '${row['id']}',
        seq: _intColumn(row['seq']),
        updated: row['time_updated'] is int ? row['time_updated'] as int : null,
      ),
  ];
}

/// 重读 [messageIds] 的完整 `session_message` 行,构建单消息 bundle。
/// [sessionId] 由调用方传入(增量状态 seed 时固定),不在查询内重新解析。
Future<List<AiTranscriptBundle>?> _loadMessageBundles(
  SessionHistoryContext ctx,
  String sessionId,
  List<String> messageIds,
) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final handle = await resolveOpencodeSqliteReadPath(
    fs: ctx.fs,
    dbPath: ctx.fs.pathContext.join(dataDir, 'opencode.db'),
  );
  if (handle == null) return null;

  final bundles = await handle.read<List<AiTranscriptBundle>?>(
    _messageBundlesQuery,
    {'sessionId': sessionId, 'messageIds': messageIds},
  );
  return bundles;
}

/// 重读 [messageIds] 的完整 `session_message` 行,构建单消息 bundle。
/// (worker isolate 上执行,args = {sessionId, messageIds})。
List<AiTranscriptBundle>? _messageBundlesQuery(Database db, Object? args) {
  final map = args as Map<String, Object?>;
  final sessionId = map['sessionId'] as String;
  final messageIds = (map['messageIds'] as List).cast<String>();
  final out = <AiTranscriptBundle>[];
  for (final messageId in messageIds) {
    final messageRows = db.select(
      '''
SELECT id, type, data, time_created
FROM session_message
WHERE session_id = ? AND id = ?
''',
      [sessionId, messageId],
    );
    if (messageRows.isEmpty) continue;
    final fragments = _buildSqliteFragments(sessionId, messageRows);
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
}

/// Locate OpenCode `session_v2` / `session_message` rows under the session
/// data dir.
///
/// Reads the SQLite store (`opencode.db` with WAL) — copying `-wal`/`-shm`
/// sidecars so a live writer is visible — and emits the fragment layout so
/// [OpencodeAiTranscriptAdapter] stays one parser.
///
/// Fragment names: `session_message/{id}.json`
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

/// Seat-only change signal: `session_message` row count + newest
/// `time_updated` for the seat session itself (not its children).
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

  return handle.read<String?>(_seatFingerprintQuery, sessionId);
}

/// Seat 级聚合指纹(worker isolate 上执行,args = sessionId)。
String? _seatFingerprintQuery(Database db, Object? args) {
  final sessionId = args as String;
  final rows = db.select(
    'SELECT COUNT(*), MAX(time_updated) FROM session_message '
    'WHERE session_id = ?',
    [sessionId],
  );
  if (rows.isEmpty) return null;
  return '${rows.first['COUNT(*)']}|${rows.first['MAX(time_updated)']}';
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
  const _ParentBundleMemo({required this.fingerprint, required this.bundle});

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

  return handle.read<String?>(_storeCacheTokenQuery);
}

/// Cursor-backed SQLite transcript source. It deliberately reuses the full
/// locator's `session_message` ordering and fragment conversion, then asks
/// [OpencodeAiTranscriptAdapter] to perform the one canonical conversion.
///
/// A missing modern store fingerprint, a changed source token, or a malformed
/// cursor yields null so the history loader retains its full-parse fallback.
final class OpencodeTranscriptPageReader implements AiTranscriptPageReader {
  const OpencodeTranscriptPageReader();

  @override
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  }) async {
    if (limit <= 0) return null;
    final snapshot = await _pageSnapshot(ctx);
    if (snapshot == null) return null;
    final page = await _readPage(
      ctx: ctx,
      snapshot: snapshot,
      offset: 0,
      limit: limit,
      rebuilt: true,
    );
    return page?.page;
  }

  @override
  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  }) async {
    if (limit <= 0 || cursor.offset <= 0) return null;
    final expected = _decodePageToken(cursor.sourceToken);
    if (expected == null) return null;
    final snapshot = await _pageSnapshot(ctx);
    if (snapshot == null ||
        snapshot.sourceToken != cursor.sourceToken ||
        snapshot.dataDir != expected.dataDir ||
        snapshot.sessionId != expected.sessionId) {
      return null;
    }
    final page = await _readPage(
      ctx: ctx,
      snapshot: snapshot,
      offset: cursor.offset,
      limit: limit,
      rebuilt: false,
    );
    if (page == null ||
        _stableHash(page.firstMessageId ?? '') != cursor.lineHash) {
      return null;
    }
    return page.page;
  }

  Future<_OpencodePageRead?> _readPage({
    required SessionHistoryContext ctx,
    required _OpencodePageSnapshot snapshot,
    required int offset,
    required int limit,
    required bool rebuilt,
  }) async {
    final handle = await resolveOpencodeSqliteReadPath(
      fs: ctx.fs,
      dbPath: ctx.fs.pathContext.join(snapshot.dataDir, 'opencode.db'),
    );
    if (handle == null) return null;
    final rows = await handle.read<_OpencodePageRows?>(_pageRowsQuery, {
      'sessionId': snapshot.sessionId,
      'offset': offset,
      'limit': limit,
    });
    if (rows == null || rows.fragments.isEmpty || rows.firstMessageId == null) {
      return null;
    }
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: _toTranscriptFragments(rows.fragments),
        hints: const {'source': 'sqlite', 'paged': 'true'},
      ),
    );
    // Empty output means this raw row window contains only unsupported or
    // synthetic entries. Do not advance a cursor that cannot be compared with
    // the adapter's visible transcript.
    if (messages.isEmpty) return null;
    final hasOlder = rows.nextMessageId != null;
    final nextOffset = offset + limit;
    return (
      firstMessageId: rows.firstMessageId,
      page: AiHistoryPage(
        messages: messages,
        hasOlder: hasOlder,
        nextCursor: hasOlder
            ? AiHistoryCursor(
                sourceToken: snapshot.sourceToken,
                offset: nextOffset,
                lineHash: _stableHash(rows.nextMessageId!),
              )
            : null,
        sourceToken: snapshot.sourceToken,
        rebuilt: rebuilt,
      ),
    );
  }
}

typedef _OpencodePageSnapshot = ({
  String dataDir,
  String sessionId,
  String sourceToken,
});

Future<_OpencodePageSnapshot?> _pageSnapshot(SessionHistoryContext ctx) async {
  final dataDir = opencodeDataDirFromEnv(ctx);
  if (dataDir.isEmpty) return null;
  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null || sessionId.isEmpty) return null;
  // The existing store fingerprint is intentionally cheap and returns null on
  // old/unsupported schemas (for example, without time_updated). Never hash
  // the database as a paging fallback.
  final version = await opencodeLiveCacheToken(ctx);
  if (version == null || version.isEmpty) return null;
  final sourceToken = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'dataDir': dataDir,
        'sessionId': sessionId,
        'version': version,
      }),
    ),
  );
  return (dataDir: dataDir, sessionId: sessionId, sourceToken: sourceToken);
}

({String dataDir, String sessionId})? _decodePageToken(String token) {
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(token)));
    if (decoded is! Map ||
        decoded['dataDir'] is! String ||
        decoded['sessionId'] is! String ||
        decoded['version'] is! String) {
      return null;
    }
    return (
      dataDir: decoded['dataDir'] as String,
      sessionId: decoded['sessionId'] as String,
    );
  } on Object {
    return null;
  }
}

typedef _OpencodePageRows = ({
  List<SqliteFragmentData> fragments,
  String? firstMessageId,
  String? nextMessageId,
});

typedef _OpencodePageRead = ({String? firstMessageId, AiHistoryPage page});

/// Page query with the same `seq` message order and
/// `_buildSqliteFragments` conversion used by the full SQLite locator. The
/// descending read makes the recent page cheap; fragments are restored to
/// ascending order before the adapter sees them.
_OpencodePageRows? _pageRowsQuery(Database db, Object? args) {
  final map = args as Map<String, Object?>;
  final sessionId = map['sessionId'] as String;
  final offset = map['offset'] as int;
  final limit = map['limit'] as int;
  if (offset < 0 || limit <= 0) return null;
  final rows = db.select(
    '''
SELECT id, type, data, time_created
FROM session_message
WHERE session_id = ?
ORDER BY seq DESC, id DESC
LIMIT ? OFFSET ?
''',
    [sessionId, limit + 1, offset],
  );
  if (rows.isEmpty) return null;
  final visible = rows.length > limit ? rows.sublist(0, limit) : rows;
  final nextId = rows.length > limit ? '${rows[limit]['id']}' : null;
  final firstId = '${visible.first['id']}';
  final fragments = _buildSqliteFragments(
    sessionId,
    visible.reversed.toList(growable: false),
  );
  return (fragments: fragments, firstMessageId: firstId, nextMessageId: nextId);
}

int _stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Store 级指纹(worker isolate 上执行,args = null)。
String? _storeCacheTokenQuery(Database db, Object? args) {
  final messages = db.select(
    'SELECT COUNT(*), MAX(time_updated) FROM session_message',
  );
  final sessions = db.select(
    'SELECT COUNT(*), MAX(time_updated) FROM session_v2',
  );
  if (messages.isEmpty || sessions.isEmpty) return null;
  return 'oc|${messages.first['COUNT(*)']}|${messages.first['MAX(time_updated)']}'
      '|${sessions.first['COUNT(*)']}|${sessions.first['MAX(time_updated)']}';
}

/// Incremental sqlite locate: only messages with `seq > [afterSeq]`.
///
/// Uses the same read path + fragment builder as [_locateSqliteStorage]
/// so both callers share one consistent read.
///
/// Worker isolate 上执行,args = {sessionId, afterSeq}。
({List<SqliteFragmentData> fragments, String lastId, int lastSeq})?
_incrementalLocateQuery(Database db, Object? args) {
  final map = args as Map<String, Object?>;
  final sessionId = map['sessionId'] as String;
  final afterSeq = map['afterSeq'] as int;
  final messageRows = db.select(
    '''
SELECT id, type, data, time_created, seq
FROM session_message
WHERE session_id = ? AND seq > ?
ORDER BY seq ASC, id ASC
''',
    [sessionId, afterSeq],
  );
  if (messageRows.isEmpty) return null;
  final fragments = _buildSqliteFragments(sessionId, messageRows);
  return (
    fragments: fragments,
    lastId: '${messageRows.last['id']}',
    lastSeq: _intColumn(messageRows.last['seq']),
  );
}

/// 全量 sqlite locate 查询(worker isolate 上执行,args = sessionId)。
List<SqliteFragmentData>? _fullLocateQuery(Database db, Object? args) {
  final sessionId = args as String;
  final messageRows = db.select(
    '''
SELECT id, type, data, time_created
FROM session_message
WHERE session_id = ?
ORDER BY seq ASC, id ASC
''',
    [sessionId],
  );
  if (messageRows.isEmpty) return null;
  return _buildSqliteFragments(sessionId, messageRows);
}

Future<AiTranscriptBundle?> locateOpencodeTranscriptIncremental(
  SessionHistoryContext ctx, {
  required int afterSeq,
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

  final read = await handle
      .read<
        ({List<SqliteFragmentData> fragments, String lastId, int lastSeq})?
      >(_incrementalLocateQuery, {
        'sessionId': sessionId,
        'afterSeq': afterSeq,
      });
  if (read == null) return null;

  final fragments = _toTranscriptFragments(read.fragments);
  if (fragments.where((f) => f.name.startsWith('session_message/')).isEmpty) {
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
      'afterSeq': '$afterSeq',
      'lastMessageId': lastId,
      'lastSeq': '${read.lastSeq}',
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

  final fragmentsData = await handle.read<List<SqliteFragmentData>>(
    _fullLocateQuery,
    sessionId,
  );
  if (fragmentsData == null) return null;
  final fragments = _toTranscriptFragments(fragmentsData);
  if (fragments.where((f) => f.name.startsWith('session_message/')).isEmpty) {
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

/// `session_message` → `session_message/{id}.json` fragments, shared by the
/// full and incremental sqlite locates.
///
/// OpenCode stores `data` as `Omit<Info, "type"|"id">`; the locator merges
/// the row `id` and `type` so [OpencodeAiTranscriptAdapter] sees one object.
///
/// Returns sendable name+bytes records so the whole query + fragment build can
/// run on a worker isolate ([OpencodeSqliteReadHandle.read]).
typedef SqliteFragmentData = ({String name, List<int> bytes});

List<SqliteFragmentData> _buildSqliteFragments(
  String sessionId,
  List<Row> messageRows,
) {
  final fragments = <SqliteFragmentData>[];
  for (final row in messageRows) {
    final messageId = '${row['id']}';
    final type = '${row['type'] ?? ''}';
    final obj = _decodeDbJson(row['data']);
    if (obj == null) continue;
    obj['id'] = messageId;
    obj['type'] = type;
    obj.putIfAbsent('sessionID', () => sessionId);
    if (obj['time'] is! Map) {
      final created = row['time_created'];
      if (created is int) {
        obj['time'] = {'created': created};
      }
    }
    fragments.add((
      name: 'session_message/$messageId.json',
      bytes: utf8.encode(jsonEncode(obj)),
    ));
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

Future<String?> _resolveSessionId(SessionHistoryContext ctx, String dataDir) {
  return resolveOpencodeNativeSessionId(
    fs: ctx.fs,
    dataDir: dataDir,
    persistedNativeId: ctx.persistedNativeId,
  );
}

int _intColumn(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
