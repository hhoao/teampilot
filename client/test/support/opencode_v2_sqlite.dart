import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Minimal OpenCode v2 tables TeamPilot history reads.
const opencodeV2SchemaSql = '''
CREATE TABLE session_v2 (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);
CREATE TABLE session_message (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  type TEXT NOT NULL,
  seq INTEGER NOT NULL,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL,
  data TEXT NOT NULL
);
''';

void createOpencodeV2Schema(Database db) {
  db.execute(opencodeV2SchemaSql);
}

void insertOpencodeV2Session(
  Database db, {
  required String id,
  String? parentId,
  int timeCreated = 1,
  int timeUpdated = 1,
}) {
  db.execute(
    'INSERT INTO session_v2 (id, parent_id, time_created, time_updated) '
    'VALUES (?, ?, ?, ?)',
    [id, parentId, timeCreated, timeUpdated],
  );
}

void insertOpencodeV2User(
  Database db, {
  required String id,
  required String sessionId,
  required int seq,
  required String text,
  int? timeCreated,
}) {
  final created = timeCreated ?? seq * 1000;
  insertOpencodeV2Message(
    db,
    id: id,
    sessionId: sessionId,
    type: 'user',
    seq: seq,
    timeCreated: created,
    data: {
      'text': text,
      'time': {'created': created},
    },
  );
}

void insertOpencodeV2Assistant(
  Database db, {
  required String id,
  required String sessionId,
  required int seq,
  required List<Map<String, Object?>> content,
  int? timeCreated,
  int? timeUpdated,
}) {
  final created = timeCreated ?? seq * 1000;
  insertOpencodeV2Message(
    db,
    id: id,
    sessionId: sessionId,
    type: 'assistant',
    seq: seq,
    timeCreated: created,
    timeUpdated: timeUpdated ?? created,
    data: {
      'agent': 'build',
      'model': {'providerID': 'opencode', 'id': 'test'},
      'content': content,
      'time': {'created': created},
    },
  );
}

void insertOpencodeV2Message(
  Database db, {
  required String id,
  required String sessionId,
  required String type,
  required int seq,
  required Map<String, Object?> data,
  int timeCreated = 1,
  int? timeUpdated,
}) {
  db.execute(
    'INSERT INTO session_message '
    '(id, session_id, type, seq, time_created, time_updated, data) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      sessionId,
      type,
      seq,
      timeCreated,
      timeUpdated ?? timeCreated,
      jsonEncode(data),
    ],
  );
}

Map<String, Object?> opencodeV2Text(String text) => {
  'type': 'text',
  'text': text,
};

Map<String, Object?> opencodeV2Reasoning(String text) => {
  'type': 'reasoning',
  'text': text,
};

Map<String, Object?> opencodeV2Tool({
  required String id,
  required String name,
  required String status,
  Map<String, Object?> input = const {},
  String? output,
  String? error,
}) {
  final state = <String, Object?>{'status': status, 'input': input};
  if (status == 'completed' && output != null) {
    state['content'] = [
      {'type': 'text', 'text': output},
    ];
  }
  if (status == 'error' && error != null) {
    state['error'] = {'message': error};
  }
  return {'type': 'tool', 'id': id, 'name': name, 'state': state};
}

/// Convert a v1 `storage/message` + `storage/part` tree into v2 tables.
Future<void> writeOpencodeV2DbFromV1JsonTree(
  String dbPath,
  String storageRoot,
) async {
  await File(dbPath).parent.create(recursive: true);
  final db = sqlite3.open(dbPath);
  try {
    createOpencodeV2Schema(db);
    final messagesDir = Directory(p.join(storageRoot, 'message'));
    final partsDir = Directory(p.join(storageRoot, 'part'));
    final partsByMessage = <String, List<Map<String, dynamic>>>{};
    if (await partsDir.exists()) {
      await for (final entity in partsDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final obj = _decodeObject(await entity.readAsString());
        if (obj == null) continue;
        final messageId =
            '${obj['messageID'] ?? p.basename(p.dirname(entity.path))}';
        partsByMessage.putIfAbsent(messageId, () => []).add(obj);
      }
    }
    final sessionIds = <String>{};
    final seqBySession = <String, int>{};
    final pending =
        <({String id, String sessionId, String role, int created})>[];
    if (await messagesDir.exists()) {
      await for (final entity in messagesDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final obj = _decodeObject(await entity.readAsString());
        if (obj == null) continue;
        final id = '${obj['id'] ?? p.basenameWithoutExtension(entity.path)}';
        final sessionId = '${obj['sessionID'] ?? ''}';
        if (id.isEmpty || sessionId.isEmpty) continue;
        sessionIds.add(sessionId);
        pending.add((
          id: id,
          sessionId: sessionId,
          role: '${obj['role'] ?? ''}',
          created: _jsonTime(obj) ?? 0,
        ));
      }
      pending.sort((a, b) {
        final byTime = a.created.compareTo(b.created);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
      for (final message in pending) {
        final seq = (seqBySession[message.sessionId] ?? 0) + 1;
        seqBySession[message.sessionId] = seq;
        final created = message.created > 0 ? message.created : seq * 1000;
        final parts = List<Map<String, dynamic>>.of(
          partsByMessage[message.id] ?? const [],
        )..sort((a, b) => '${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}'));
        if (message.role == 'user') {
          final texts = [
            for (final part in parts)
              if (part['type'] == 'text') '${part['text'] ?? ''}'.trim(),
          ]..removeWhere((t) => t.isEmpty);
          insertOpencodeV2User(
            db,
            id: message.id,
            sessionId: message.sessionId,
            seq: seq,
            text: texts.join('\n'),
            timeCreated: created,
          );
        } else if (message.role == 'assistant') {
          insertOpencodeV2Assistant(
            db,
            id: message.id,
            sessionId: message.sessionId,
            seq: seq,
            timeCreated: created,
            content: [for (final part in parts) ..._v2ContentFromV1Part(part)],
          );
        }
      }
    }
    for (final sessionId in sessionIds) {
      insertOpencodeV2Session(db, id: sessionId);
    }
  } finally {
    db.close();
  }
}

void writeOpencodeV2TextTurns(
  Database db, {
  String sessionId = 'ses_1',
  int extraTurns = 0,
}) {
  insertOpencodeV2Session(
    db,
    id: sessionId,
    timeCreated: 1001,
    timeUpdated: 1001,
  );
  insertOpencodeV2User(
    db,
    id: 'msg_user',
    sessionId: sessionId,
    seq: 1,
    text: 'hi',
    timeCreated: 1001,
  );
  insertOpencodeV2Assistant(
    db,
    id: 'msg_assistant',
    sessionId: sessionId,
    seq: 2,
    timeCreated: 2001,
    content: [opencodeV2Text('hello')],
  );
  for (var i = 0; i < extraTurns; i++) {
    final created = 3001 + i;
    insertOpencodeV2User(
      db,
      id: 'msg_extra_$i',
      sessionId: sessionId,
      seq: 3 + i,
      text: 'extra $i',
      timeCreated: created,
    );
  }
}

List<Map<String, Object?>> _v2ContentFromV1Part(Map<String, dynamic> part) {
  final type = '${part['type'] ?? ''}';
  if (type == 'text') {
    final text = '${part['text'] ?? ''}'.trim();
    if (text.isEmpty) return const [];
    return [opencodeV2Text(text)];
  }
  if (type == 'reasoning') {
    final text = '${part['text'] ?? ''}'.trim();
    if (text.isEmpty) return const [];
    return [opencodeV2Reasoning(text)];
  }
  if (type != 'tool') return const [];
  final stateRaw = part['state'];
  Map<String, Object?> input = const {};
  var status = 'running';
  String? output;
  String? error;
  if (stateRaw is Map) {
    status = '${stateRaw['status'] ?? 'running'}';
    final inputRaw = stateRaw['input'];
    if (inputRaw is Map) {
      input = {for (final e in inputRaw.entries) '${e.key}': e.value};
    }
    if (status == 'completed') {
      final raw = '${stateRaw['output'] ?? ''}';
      if (raw.isNotEmpty) output = raw;
    }
    if (status == 'error') {
      final raw = '${stateRaw['error'] ?? ''}';
      if (raw.isNotEmpty) error = raw;
    }
  }
  final callId = '${part['callID'] ?? part['id'] ?? ''}'.trim();
  if (callId.isEmpty) return const [];
  return [
    opencodeV2Tool(
      id: callId,
      name: '${part['tool'] ?? part['name'] ?? 'tool'}',
      status: status,
      input: input,
      output: output,
      error: error,
    ),
  ];
}

Map<String, dynamic>? _decodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on Object {
    return null;
  }
  return null;
}

int? _jsonTime(Map<String, dynamic> obj) {
  final time = obj['time'];
  if (time is! Map) return null;
  final created = time['created'];
  if (created is int) return created;
  if (created is num) return created.toInt();
  return null;
}
