import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
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
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
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

  test('message id is the fragment/db id; empty-id message skipped, no fallback (G1)',
      () async {
    // opencode 无 fallback id：消息 id 恒 = 片段携带的 id（JSON 树文件名 / db 行 id），
    // 空 id 整条跳过，绝不合成 {cli}-{seq} 类 id（区别于 claude/codex/cursor 的惰性 fallback）。
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          AiTranscriptFragment(
            name: 'message/msg_a.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_a',
                'role': 'user',
                'time': {'created': 1},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_a/prt_a1.json',
            bytes: utf8.encode(
              jsonEncode({'id': 'prt_a1', 'type': 'text', 'text': 'a'}),
            ),
          ),
          // 无 id 的消息：必须整条跳过（含其 parts），不消耗任何序号。
          AiTranscriptFragment(
            name: 'message/msg_noid.json',
            bytes: utf8.encode(
              jsonEncode({
                'role': 'user',
                'time': {'created': 2},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_noid/prt_noid1.json',
            bytes: utf8.encode(
              jsonEncode({'id': 'prt_noid1', 'type': 'text', 'text': 'noid'}),
            ),
          ),
          AiTranscriptFragment(
            name: 'message/msg_b.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_b',
                'role': 'assistant',
                'time': {'created': 3},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_b/prt_b1.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_b1',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_b',
                'state': {'status': 'completed', 'input': {'command': 'pwd'}, 'output': '/tmp'},
              }),
            ),
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages.map((m) => m.id), ['msg_a', 'msg_b']);
    expect(messages.map((m) => m.id).toSet(), hasLength(2),
        reason: 'id 必须唯一');
    expect(
      messages.expand((m) => m.parts).whereType<AiTextPart>(),
      everyElement(isNot(matches('noid'))),
    );
    expect(
      messages.expand((m) => m.parts).whereType<AiTextPart>(),
      everyElement(isNot(matches(RegExp(r'^opencode-\d+$')))),
      reason: '不允许出现 fallback 合成 id',
    );
  });

  test('full and incremental sqlite locate share the same message ids (G1)',
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
    for (var i = 1; i <= 3; i++) {
      final role = i.isOdd ? 'user' : 'assistant';
      db.execute(
        'INSERT INTO message (session_id, data, time_created) VALUES (?, ?, ?)',
        [
          'sess-g1',
          jsonEncode({'role': role, 'time': {'created': i * 1000}}),
          i * 1000,
        ],
      );
      db.execute(
        'INSERT INTO part (message_id, data, time_created) VALUES (?, ?, ?)',
        [i, jsonEncode({'type': 'text', 'text': 'm$i'}), i * 1000],
      );
    }
    db.dispose();

    final adapter = const OpencodeAiTranscriptAdapter();
    final full = await locateOpencodeTranscript(
      ctx(dataDir: base.path, persistedNativeId: 'sess-g1'),
    );
    expect(full, isNotNull);
    final fullMessages = await adapter.parse(full!);
    expect(fullMessages.map((m) => m.id), ['1', '2', '3']);

    const afterMessageId = 1;
    final inc = await locateOpencodeTranscriptIncremental(
      ctx(dataDir: base.path, persistedNativeId: 'sess-g1'),
      afterMessageId: afterMessageId,
    );
    expect(inc, isNotNull);
    expect(inc!.hints['lastMessageId'], '3');
    final incMessages = await adapter.parse(inc);
    expect(incMessages.map((m) => m.id), ['2', '3']);

    // 窗口一致性：增量产出 = 全量产出中 id 大于 afterMessageId 的子集（同源同 id）。
    expect(
      incMessages.map((m) => m.id),
      fullMessages
          .map((m) => m.id)
          .where((id) => int.parse(id) > afterMessageId),
    );
  });

  test('non-Map tool input yields args null, never a bare string (G2)',
      () async {
    // _asArgs 仅接受 Map：字符串/数字等非 Map input → args=null，
    // 绝不以裸字符串形式出现在 args 里（契约：args 必须 Map 或 null）。
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          AiTranscriptFragment(
            name: 'message/msg_g2.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_g2',
                'role': 'assistant',
                'time': {'created': 1},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_g2/prt_str.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_str',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_str',
                'state': {'status': 'completed', 'input': 'ls -la', 'output': 'ok'},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_g2/prt_map.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_map',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_map',
                'state': {
                  'status': 'completed',
                  'input': {'command': 'pwd'},
                  'output': '/tmp',
                },
              }),
            ),
          ),
        ],
      ),
    );

    final tools = messages.single.parts.whereType<AiToolCallPart>().toList();
    expect(tools, hasLength(2));
    final strTool = tools.singleWhere((t) => t.toolCallId == 'call_str');
    expect(strTool.args, isNull);
    expect(strTool.result, 'ok');
    final mapTool = tools.singleWhere((t) => t.toolCallId == 'call_map');
    expect(mapTool.args, {'command': 'pwd'});
  });

  test('completed/error/running tool states map to contract statuses with inline result (G5)',
      () async {
    // result 内联在 part state：completed → state.output、error → state.error；
    // 任何有 result 的 tool part status 都不是 running；pending/running → incomplete 且 result=null。
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          AiTranscriptFragment(
            name: 'message/msg_g5.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'msg_g5',
                'role': 'assistant',
                'time': {'created': 1},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_g5/prt_done.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_done',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_done',
                'state': {'status': 'completed', 'input': {'command': 'ls'}, 'output': 'a.txt'},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_g5/prt_err.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_err',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_err',
                'state': {'status': 'error', 'input': {'command': 'nope'}, 'error': 'command not found'},
              }),
            ),
          ),
          AiTranscriptFragment(
            name: 'part/msg_g5/prt_run.json',
            bytes: utf8.encode(
              jsonEncode({
                'id': 'prt_run',
                'type': 'tool',
                'tool': 'bash',
                'callID': 'call_run',
                'state': {'status': 'running', 'input': {'command': 'sleep'}},
              }),
            ),
          ),
        ],
      ),
    );

    final tools = messages.single.parts.whereType<AiToolCallPart>().toList();
    expect(tools, hasLength(3));
    final done = tools.singleWhere((t) => t.toolCallId == 'call_done');
    expect(done.status, AiToolCallStatus.complete);
    expect(done.result, 'a.txt');
    expect(done.isError, isFalse);
    final err = tools.singleWhere((t) => t.toolCallId == 'call_err');
    expect(err.status, AiToolCallStatus.complete);
    expect(err.isError, isTrue);
    expect(err.result, 'command not found');
    final run = tools.singleWhere((t) => t.toolCallId == 'call_run');
    expect(run.status, AiToolCallStatus.incomplete);
    expect(run.result, isNull);
    for (final t in tools) {
      if (t.result != null) {
        expect(t.status, isNot(AiToolCallStatus.running),
            reason: '有 result 的 tool part 不得是 running');
      }
    }
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
