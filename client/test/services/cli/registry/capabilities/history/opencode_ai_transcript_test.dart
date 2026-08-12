import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String dataDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DB': p.join(dataDir, 'opencode.db')},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  test(
    'OpencodeAiTranscriptAdapter parses messages and tool parts',
    () async {
      // Fragments in the DB-emitted layout (message/ + part/ names), same
      // shape the SQLite locate produces.
      final bundle = AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          AiTranscriptFragment(
            name: 'session/ses_demo001.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'ses_demo001',
                'projectID': 'proj_demo',
                'time': {'created': 1720612800000},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'message/msg_user1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_user1',
                'sessionID': 'ses_demo001',
                'role': 'user',
                'time': {'created': 1720612801000},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'message/msg_asst1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_asst1',
                'sessionID': 'ses_demo001',
                'role': 'assistant',
                'time': {'created': 1720612802000},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_user1/prt_text1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_text1',
                'messageID': 'msg_user1',
                'type': 'text',
                'text': 'hello opencode',
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_asst1/prt_text2.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_text2',
                'messageID': 'msg_asst1',
                'type': 'text',
                'text': 'listing files',
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_asst1/prt_tool1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_tool1',
                'messageID': 'msg_asst1',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_1',
                'state': {
                  'status': 'completed',
                  'input': {'command': 'ls'},
                  'output': 'a.txt\nb.txt',
                },
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_asst1/prt_bad.json',
            bytes: utf8.encode('not-json'),
          ),
        ],
      );

      final adapter = const OpencodeAiTranscriptAdapter();
      final messages = await adapter.parse(bundle);

      expect(adapter.id, 'opencode');
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.id, 'msg_user1');
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'hello opencode');
      expect(
        user.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1720612801000, isUtc: true),
      );

      final asst = messages[1];
      expect(asst.id, 'msg_asst1');
      expect(asst.role, AiRole.assistant);
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        'listing files',
      );
      final tool = asst.parts.whereType<AiToolCallPart>().single;
      expect(tool.toolCallId, 'call_1');
      expect(tool.toolName, 'bash');
      expect(tool.args, {'command': 'ls'});
      expect(tool.result, 'a.txt\nb.txt');
      expect(tool.isError, isFalse);

      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test('locateOpencodeTranscript returns null when missing', () async {
    final bundle = await locateOpencodeTranscript(ctx(dataDir: base.path));
    expect(bundle, isNull);
  });

  test('parses reasoning parts from OpenCode storage', () async {
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          AiTranscriptFragment(
            name: 'message/msg_r1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_r1',
                'role': 'assistant',
                'time': {'created': 1720612802000},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_r1/prt_reason.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_reason',
                'messageID': 'msg_r1',
                'type': 'reasoning',
                'text': 'thinking about the unread mailbox',
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_r1/prt_text.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_text',
                'messageID': 'msg_r1',
                'type': 'text',
                'text': 'done',
              }),
            ),
          ),
        ],
      ),
    );

    expect(messages, hasLength(1));
    expect(
      messages.single.parts.whereType<AiReasoningPart>().single.text,
      'thinking about the unread mailbox',
    );
    expect(
      messages.single.parts.whereType<AiTextPart>().single.text,
      'done',
    );
  });

  test('locateOpencodeTranscript reads opencode.db when JSON tree missing',
      () async {
    // Mirrors current ~/.local/share/opencode layout (SQLite, no storage/message).
    final dbPath = p.join(base.path, 'opencode.db');
    final db = sqlite3.open(dbPath);
    db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  time_updated INTEGER
);
CREATE TABLE message (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
CREATE TABLE part (
  id TEXT PRIMARY KEY,
  message_id TEXT,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
''');
    db.execute(
      "INSERT INTO session(id, time_updated) VALUES ('ses_db1', 2)",
    );
    db.execute(
      '''
INSERT INTO message(id, session_id, time_created, data)
VALUES (
  'msg_u',
  'ses_db1',
  1,
  '{"role":"user","time":{"created":1}}'
)
''',
    );
    db.execute(
      '''
INSERT INTO message(id, session_id, time_created, data)
VALUES (
  'msg_a',
  'ses_db1',
  2,
  '{"role":"assistant","time":{"created":2}}'
)
''',
    );
    db.execute(
      '''
INSERT INTO part(id, message_id, session_id, time_created, data)
VALUES (
  'prt_u',
  'msg_u',
  'ses_db1',
  1,
  '{"type":"text","text":"hello db"}'
)
''',
    );
    db.execute(
      '''
INSERT INTO part(id, message_id, session_id, time_created, data)
VALUES (
  'prt_a',
  'msg_a',
  'ses_db1',
  2,
  '{"type":"tool","tool":"bash","callID":"call_db","state":{"status":"completed","input":{"command":"pwd"},"output":"/tmp"}}'
)
''',
    );
    db.dispose();

    final bundle = await locateOpencodeTranscript(
      ctx(dataDir: base.path, persistedNativeId: 'ses_db1'),
    );
    expect(bundle, isNotNull);
    expect(bundle!.hints['source'], 'sqlite');

    final watchMeta = AiHistoryWatchMeta.fromHints(bundle.hints);
    expect(watchMeta, isNotNull);
    expect(watchMeta!.changeWatchRoot, base.path);
    expect(watchMeta.cacheTokenPaths, [dbPath]);

    final messages = await const OpencodeAiTranscriptAdapter().parse(bundle);
    expect(messages, hasLength(2));
    expect((messages[0].parts.single as AiTextPart).text, 'hello db');
    final tool = messages[1].parts.whereType<AiToolCallPart>().single;
    expect(tool.toolName, 'bash');
    expect(tool.result, '/tmp');
  });

  test(
    'locateOpencodeTranscript reads WAL sidecars (live OpenCode layout)',
    () async {
      // OpenCode keeps an open WAL writer; the main file alone has no tables.
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('''
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  time_updated INTEGER
);
CREATE TABLE message (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
CREATE TABLE part (
  id TEXT PRIMARY KEY,
  message_id TEXT,
  session_id TEXT,
  time_created INTEGER,
  data TEXT
);
''');
      db.execute(
        "INSERT INTO session(id, time_updated) VALUES ('ses_wal1', 2)",
      );
      db.execute(
        '''
INSERT INTO message(id, session_id, time_created, data)
VALUES (
  'msg_wal_u',
  'ses_wal1',
  1,
  '{"role":"user","time":{"created":1}}'
)
''',
      );
      db.execute(
        '''
INSERT INTO part(id, message_id, session_id, time_created, data)
VALUES (
  'prt_wal_u',
  'msg_wal_u',
  'ses_wal1',
  1,
  '{"type":"text","text":"hello from wal"}'
)
''',
      );

      expect(
        File('$dbPath-wal').existsSync(),
        isTrue,
        reason: 'WAL sidecar must exist while writer is open',
      );

      final bundle = await locateOpencodeTranscript(
        ctx(dataDir: base.path, persistedNativeId: 'ses_wal1'),
      );
      expect(bundle, isNotNull);
      final messages = await const OpencodeAiTranscriptAdapter().parse(bundle!);
      expect(messages, hasLength(1));
      expect(
        (messages.single.parts.single as AiTextPart).text,
        'hello from wal',
      );
      expect(
        AiHistoryWatchMeta.fromHints(bundle.hints)!.cacheTokenPaths,
        containsAll([dbPath, '$dbPath-wal']),
      );
    },
  );

  test(
      'locateOpencodeTranscriptIncremental returns only messages after afterMessageId',
      () async {
    final dbPath = p.join(base.path, 'opencode.db');
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('''
    CREATE TABLE message (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
    db.execute('''
    CREATE TABLE part (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
    final userData = jsonEncode({
      'role': 'user',
      'time': {'created': 1000},
      'content': [
        {'type': 'text', 'text': 'hi'}
      ],
    });
    final asstData = jsonEncode({
      'role': 'assistant',
      'time': {'created': 2000},
      'content': [
        {'type': 'text', 'text': 'hello'}
      ],
    });
    db.execute(
      'INSERT INTO message (session_id, data, time_created) VALUES (?, ?, ?)',
      ['sess-1', userData, 1000]);
    db.execute(
      'INSERT INTO message (session_id, data, time_created) VALUES (?, ?, ?)',
      ['sess-1', asstData, 2000]);
    db.execute(
      'INSERT INTO part (message_id, data, time_created) VALUES (?, ?, ?)',
      [1, jsonEncode({'type': 'text', 'text': 'hi'}), 1000]);
    db.execute(
      'INSERT INTO part (message_id, data, time_created) VALUES (?, ?, ?)',
      [2, jsonEncode({'type': 'text', 'text': 'hello'}), 2000]);
    db.dispose();

    final first = await locateOpencodeTranscriptIncremental(
      ctx(dataDir: base.path, persistedNativeId: 'sess-1'),
      afterMessageId: 0,
    );
    expect(first, isNotNull);
    expect(first!.hints['lastMessageId'], '2');
    final adapter = const OpencodeAiTranscriptAdapter();
    expect(await adapter.parse(first), hasLength(2));

    final second = await locateOpencodeTranscriptIncremental(
      ctx(dataDir: base.path, persistedNativeId: 'sess-1'),
      afterMessageId: 1,
    );
    expect(second, isNotNull);
    expect(second!.hints['lastMessageId'], '2');
    final messages = await adapter.parse(second);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.assistant);
  });
}
