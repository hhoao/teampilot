import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/opencode_ai_transcript.dart';
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
      env: {'OPENCODE_DATA_DIR': dataDir},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> copyFixtureTree() async {
    final fixtureRoot = Directory('test/fixtures/session_history/opencode/storage');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, 'storage', rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  }

  test(
    'OpencodeAiTranscriptAdapter parses messages and tool parts',
    () async {
      await copyFixtureTree();
      final bundle = await locateOpencodeTranscript(
        ctx(dataDir: base.path, persistedNativeId: 'ses_demo001'),
      );
      expect(bundle, isNotNull);

      final adapter = const OpencodeAiTranscriptAdapter();
      final messages = await adapter.parse(bundle!);

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

  test('locateOpencodeTranscript packs session/message/part fragments', () async {
    await copyFixtureTree();

    final bundle = await locateOpencodeTranscript(
      ctx(dataDir: base.path, persistedNativeId: 'ses_demo001'),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'opencode');
    expect(
      bundle.fragments.any((f) => f.name.startsWith('session/')),
      isTrue,
    );
    expect(
      bundle.fragments.any((f) => f.name.startsWith('message/')),
      isTrue,
    );
    expect(
      bundle.fragments.any((f) => f.name.startsWith('part/')),
      isTrue,
    );
    expect(bundle.hints['sessionId'], 'ses_demo001');
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

    final messages = await const OpencodeAiTranscriptAdapter().parse(bundle);
    expect(messages, hasLength(2));
    expect((messages[0].parts.single as AiTextPart).text, 'hello db');
    final tool = messages[1].parts.whereType<AiToolCallPart>().single;
    expect(tool.toolName, 'bash');
    expect(tool.result, '/tmp');
  });
}
