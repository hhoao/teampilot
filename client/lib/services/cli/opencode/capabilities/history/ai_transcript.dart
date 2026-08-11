import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import '../native_session_id.dart';

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

  Database? db;
  try {
    db = sqlite3.open(handle.path, mode: OpenMode.readOnly);
    final rows = db.select(
      'SELECT COUNT(*), MAX(time_updated) FROM part WHERE session_id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return '${rows.first['COUNT(*)']}|${rows.first['MAX(time_updated)']}';
  } on Object {
    return null;
  } finally {
    db?.dispose();
  }
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

  Database? db;
  try {
    db = sqlite3.open(handle.path, mode: OpenMode.readOnly);
    final parts = db.select('SELECT COUNT(*), MAX(time_updated) FROM part');
    final sessions = db.select(
      'SELECT COUNT(*), MAX(time_updated) FROM session',
    );
    if (parts.isEmpty || sessions.isEmpty) return null;
    return 'oc|${parts.first['COUNT(*)']}|${parts.first['MAX(time_updated)']}'
        '|${sessions.first['COUNT(*)']}|${sessions.first['MAX(time_updated)']}';
  } on Object {
    return null;
  } finally {
    db?.dispose();
  }
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

  Database? db;
  try {
    db = sqlite3.open(handle.path, mode: OpenMode.readOnly);

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
    if (fragments.where((f) => f.name.startsWith('message/')).isEmpty) {
      return null;
    }

    final lastId = '${messageRows.last['id']}';
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
  } on Object {
    return null;
  } finally {
    db?.close();
  }
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

  Database? db;
  try {
    db = sqlite3.open(handle.path, mode: OpenMode.readOnly);

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

    final fragments = _buildSqliteFragments(db, sessionId, messageRows);
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
        'source': 'sqlite',
        'cacheToken': 'opencode-sqlite|$sessionId|$totalBytes',
        ...AiHistoryWatchMeta(
          changeWatchRoot: dataDir,
          cacheTokenPaths: handle.sourcePaths,
        ).toHints(),
      },
    );
  } on Object {
    return null;
  } finally {
    db?.close();
  }
}

/// Message → `message/{id}.json` (+ parts → `part/{messageId}/{partId}.json`)
/// fragments, shared by the full and incremental sqlite locates.
List<AiTranscriptFragment> _buildSqliteFragments(
  Database db,
  String sessionId,
  List<Row> messageRows,
) {
  final fragments = <AiTranscriptFragment>[];

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
    fragments.add(
      AiTranscriptFragment(
        name: 'message/$messageId.json',
        bytes: utf8.encode(jsonEncode(obj)),
      ),
    );

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
      fragments.add(
        AiTranscriptFragment(
          name: 'part/$messageId/$partId.json',
          bytes: utf8.encode(jsonEncode(partObj)),
        ),
      );
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
