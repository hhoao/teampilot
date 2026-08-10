import 'dart:convert';
import 'dart:io' show Directory;

import 'package:ai_message_core/ai_message_core.dart';
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
  final dataDir = _resolveDataDir(ctx);
  if (dataDir.isEmpty) return null;

  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;

  return locateOpencodeTranscriptForSession(ctx, sessionId);
}

/// Same [dataDir] resolution as [locateOpencodeTranscript], but loads an
/// explicit OpenCode native session id (child task sessions, nested inflate).
Future<AiTranscriptBundle?> locateOpencodeTranscriptForSession(
  SessionHistoryContext ctx,
  String sessionId,
) async {
  final dataDir = _resolveDataDir(ctx);
  if (dataDir.isEmpty) return null;

  final trimmed = sessionId.trim();
  if (trimmed.isEmpty) return null;

  final jsonBundle = await _locateJsonStorage(ctx, dataDir, trimmed);
  if (jsonBundle != null) return jsonBundle;

  return _locateSqliteStorage(ctx, dataDir, trimmed);
}

/// TeamPilot history context: dirname of absolute [OPENCODE_DB].
String _resolveDataDir(SessionHistoryContext ctx) {
  final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
  if (db.isEmpty || db == ':memory:') return '';
  return ctx.fs.pathContext.dirname(db);
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

Future<AiTranscriptBundle?> _locateSqliteStorage(
  SessionHistoryContext ctx,
  String dataDir,
  String sessionId,
) async {
  final path = ctx.fs.pathContext;
  final dbPath = path.join(dataDir, 'opencode.db');
  if (!await opencodeSqliteMainExists(ctx.fs, dbPath)) return null;

  Directory? tempDir;
  Database? db;
  try {
    tempDir = await Directory.systemTemp.createTemp('opencode-history-');
    final tempDbPath = path.join(tempDir.path, 'opencode.db');
    final copiedPaths = await copyOpencodeSqliteSnapshot(
      fs: ctx.fs,
      dbPath: dbPath,
      destDbPath: tempDbPath,
    );
    if (copiedPaths.isEmpty) return null;
    db = sqlite3.open(tempDbPath, mode: OpenMode.readOnly);

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

    final fragments = <AiTranscriptFragment>[];
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

      final partRows = db.select(
        '''
SELECT id, data, time_created
FROM part
WHERE message_id = ?
ORDER BY time_created ASC, id ASC
''',
        [messageId],
      );
      for (final part in partRows) {
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
          cacheTokenPaths: copiedPaths,
        ).toHints(),
      },
    );
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
