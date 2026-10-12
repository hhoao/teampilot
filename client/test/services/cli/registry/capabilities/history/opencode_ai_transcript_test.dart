import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_watch_meta.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../../../../support/opencode_v2_sqlite.dart';

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

  AiTranscriptFragment fragment(Map<String, Object?> obj) {
    final id = obj['id'];
    return AiTranscriptFragment(
      name: 'session_message/$id.json',
      bytes: utf8.encode(jsonEncode(obj)),
    );
  }

  test('OpencodeAiTranscriptAdapter parses messages and tool parts', () async {
    final bundle = AiTranscriptBundle(
      adapterId: 'opencode',
      fragments: [
        fragment({
          'id': 'msg_user1',
          'type': 'user',
          'text': 'hello opencode',
          'time': {'created': 1720612801000},
        }),
        fragment({
          'id': 'msg_asst1',
          'type': 'assistant',
          'time': {'created': 1720612802000},
          'content': [
            opencodeV2Text('listing files'),
            opencodeV2Tool(
              id: 'call_1',
              name: 'bash',
              status: 'completed',
              input: {'command': 'ls'},
              output: 'a.txt\nb.txt',
            ),
          ],
        }),
        AiTranscriptFragment(
          name: 'session_message/msg_bad.json',
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
    expect(asst.parts.whereType<AiTextPart>().single.text, 'listing files');
    final tool = asst.parts.whereType<AiToolCallPart>().single;
    expect(tool.toolCallId, 'call_1');
    expect(tool.toolName, 'bash');
    expect(tool.args, {'command': 'ls'});
    expect(tool.result, 'a.txt\nb.txt');
    expect(tool.isError, isFalse);

    for (final m in messages.where((m) => m.role == AiRole.user)) {
      expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
    }
  });

  test('locateOpencodeTranscript returns null when missing', () async {
    final bundle = await locateOpencodeTranscript(ctx(dataDir: base.path));
    expect(bundle, isNull);
  });

  test('parses reasoning parts from OpenCode storage', () async {
    final messages = await const OpencodeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [
          fragment({
            'id': 'msg_r1',
            'type': 'assistant',
            'time': {'created': 1720612802000},
            'content': [
              opencodeV2Reasoning('thinking about the unread mailbox'),
              opencodeV2Text('done'),
            ],
          }),
        ],
      ),
    );

    expect(messages, hasLength(1));
    expect(
      messages.single.parts.whereType<AiReasoningPart>().single.text,
      'thinking about the unread mailbox',
    );
    expect(messages.single.parts.whereType<AiTextPart>().single.text, 'done');
  });

  test(
    'message id is the fragment/db id; empty-id message skipped, no fallback (G1)',
    () async {
      final messages = await const OpencodeAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'opencode',
          fragments: [
            fragment({
              'id': 'msg_a',
              'type': 'user',
              'text': 'a',
              'time': {'created': 1},
            }),
            fragment({
              'type': 'user',
              'text': 'noid',
              'time': {'created': 2},
            }),
            fragment({
              'id': 'msg_b',
              'type': 'assistant',
              'time': {'created': 3},
              'content': [
                opencodeV2Tool(
                  id: 'call_b',
                  name: 'bash',
                  status: 'completed',
                  input: {'command': 'pwd'},
                  output: '/tmp',
                ),
              ],
            }),
          ],
        ),
      );

      expect(messages, hasLength(2));
      expect(messages.map((m) => m.id), ['msg_a', 'msg_b']);
      expect(
        messages.map((m) => m.id).toSet(),
        hasLength(2),
        reason: 'id 必须唯一',
      );
      expect(
        messages.expand((m) => m.parts).whereType<AiTextPart>(),
        everyElement(isNot(matches('noid'))),
      );
      expect(
        messages.expand((m) => m.parts).whereType<AiTextPart>(),
        everyElement(isNot(matches(RegExp(r'^opencode-\d+$')))),
        reason: '不允许出现 fallback 合成 id',
      );
    },
  );

  test(
    'full and incremental sqlite locate share the same message ids (G1)',
    () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      db.execute('PRAGMA journal_mode=WAL;');
      createOpencodeV2Schema(db);
      insertOpencodeV2Session(db, id: 'sess-g1');
      for (var i = 1; i <= 3; i++) {
        if (i.isOdd) {
          insertOpencodeV2User(
            db,
            id: '$i',
            sessionId: 'sess-g1',
            seq: i,
            text: 'm$i',
          );
        } else {
          insertOpencodeV2Assistant(
            db,
            id: '$i',
            sessionId: 'sess-g1',
            seq: i,
            content: [opencodeV2Text('m$i')],
          );
        }
      }
      db.close();

      final adapter = const OpencodeAiTranscriptAdapter();
      final full = await locateOpencodeTranscript(
        ctx(dataDir: base.path, persistedNativeId: 'sess-g1'),
      );
      expect(full, isNotNull);
      final fullMessages = await adapter.parse(full!);
      expect(fullMessages.map((m) => m.id), ['1', '2', '3']);

      const afterSeq = 1;
      final inc = await locateOpencodeTranscriptIncremental(
        ctx(dataDir: base.path, persistedNativeId: 'sess-g1'),
        afterSeq: afterSeq,
      );
      expect(inc, isNotNull);
      expect(inc!.hints['lastMessageId'], '3');
      expect(inc.hints['lastSeq'], '3');
      final incMessages = await adapter.parse(inc);
      expect(incMessages.map((m) => m.id), ['2', '3']);
      expect(
        incMessages.map((m) => m.id),
        fullMessages.skip(afterSeq).map((m) => m.id),
      );
    },
  );

  test(
    'non-Map tool input yields args null, never a bare string (G2)',
    () async {
      final messages = await const OpencodeAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'opencode',
          fragments: [
            fragment({
              'id': 'msg_g2',
              'type': 'assistant',
              'time': {'created': 1},
              'content': [
                {
                  'type': 'tool',
                  'id': 'call_str',
                  'name': 'bash',
                  'state': {
                    'status': 'completed',
                    'input': 'ls -la',
                    'content': [
                      {'type': 'text', 'text': 'ok'},
                    ],
                  },
                },
                opencodeV2Tool(
                  id: 'call_map',
                  name: 'bash',
                  status: 'completed',
                  input: {'command': 'pwd'},
                  output: '/tmp',
                ),
              ],
            }),
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
    },
  );

  test(
    'completed/error/running tool states map to contract statuses with inline result (G5)',
    () async {
      final messages = await const OpencodeAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'opencode',
          fragments: [
            fragment({
              'id': 'msg_g5',
              'type': 'assistant',
              'time': {'created': 1},
              'content': [
                opencodeV2Tool(
                  id: 'call_done',
                  name: 'bash',
                  status: 'completed',
                  input: {'command': 'ls'},
                  output: 'a.txt',
                ),
                opencodeV2Tool(
                  id: 'call_err',
                  name: 'bash',
                  status: 'error',
                  input: {'command': 'nope'},
                  error: 'command not found',
                ),
                opencodeV2Tool(
                  id: 'call_run',
                  name: 'bash',
                  status: 'running',
                  input: {'command': 'sleep'},
                ),
              ],
            }),
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
          expect(
            t.status,
            isNot(AiToolCallStatus.running),
            reason: '有 result 的 tool part 不得是 running',
          );
        }
      }
    },
  );

  test('locateOpencodeTranscript reads session_v2 / session_message', () async {
    final dbPath = p.join(base.path, 'opencode.db');
    final db = sqlite3.open(dbPath);
    createOpencodeV2Schema(db);
    insertOpencodeV2Session(db, id: 'ses_db1', timeUpdated: 2);
    insertOpencodeV2User(
      db,
      id: 'msg_u',
      sessionId: 'ses_db1',
      seq: 1,
      text: 'hello db',
      timeCreated: 1,
    );
    insertOpencodeV2Assistant(
      db,
      id: 'msg_a',
      sessionId: 'ses_db1',
      seq: 2,
      timeCreated: 2,
      content: [
        opencodeV2Tool(
          id: 'call_db',
          name: 'bash',
          status: 'completed',
          input: {'command': 'pwd'},
          output: '/tmp',
        ),
      ],
    );
    db.close();

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
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      addTearDown(db.close);
      db.execute('PRAGMA journal_mode=WAL;');
      createOpencodeV2Schema(db);
      insertOpencodeV2Session(db, id: 'ses_wal1', timeUpdated: 2);
      insertOpencodeV2User(
        db,
        id: 'msg_wal_u',
        sessionId: 'ses_wal1',
        seq: 1,
        text: 'hello from wal',
        timeCreated: 1,
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
    'locateOpencodeTranscriptIncremental returns only messages after afterSeq',
    () async {
      final dbPath = p.join(base.path, 'opencode.db');
      final db = sqlite3.open(dbPath);
      db.execute('PRAGMA journal_mode=WAL;');
      createOpencodeV2Schema(db);
      insertOpencodeV2Session(db, id: 'sess-1');
      insertOpencodeV2User(
        db,
        id: 'msg_u',
        sessionId: 'sess-1',
        seq: 1,
        text: 'hi',
        timeCreated: 1000,
      );
      insertOpencodeV2Assistant(
        db,
        id: 'msg_a',
        sessionId: 'sess-1',
        seq: 2,
        timeCreated: 2000,
        content: [opencodeV2Text('hello')],
      );
      db.close();

      final first = await locateOpencodeTranscriptIncremental(
        ctx(dataDir: base.path, persistedNativeId: 'sess-1'),
        afterSeq: 0,
      );
      expect(first, isNotNull);
      expect(first!.hints['lastMessageId'], 'msg_a');
      expect(first.hints['lastSeq'], '2');
      final adapter = const OpencodeAiTranscriptAdapter();
      expect(await adapter.parse(first), hasLength(2));

      final second = await locateOpencodeTranscriptIncremental(
        ctx(dataDir: base.path, persistedNativeId: 'sess-1'),
        afterSeq: 1,
      );
      expect(second, isNotNull);
      expect(second!.hints['lastMessageId'], 'msg_a');
      final messages = await adapter.parse(second);
      expect(messages, hasLength(1));
      expect(messages.single.role, AiRole.assistant);
    },
  );
}
