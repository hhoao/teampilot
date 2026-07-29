import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/cursor_ai_transcript.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cursor_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String configDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': configDir},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> copyFixtureTree() async {
    final fixtureRoot = Directory('test/fixtures/session_history/cursor');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  }

  test(
    'CursorAiTranscriptAdapter parses role content and correlates tool_result',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/cursor/projects/home-me-proj/'
        'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/'
        'chat-aaaa-bbbb-cccc-dddd.jsonl',
      ).readAsBytes();
      final adapter = const CursorAiTranscriptAdapter();
      final messages = await adapter.parse(
        AiTranscriptBundle(
          adapterId: adapter.id,
          fragments: [
            AiTranscriptFragment(
              name: 'chat-aaaa-bbbb-cccc-dddd.jsonl',
              bytes: bytes,
            ),
          ],
        ),
      );

      expect(adapter.id, 'cursor');
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'hello cursor');

      final asst = messages[1];
      expect(asst.role, AiRole.assistant);
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        'hi from cursor',
      );
      final tool = asst.parts.whereType<AiToolCallPart>().single;
      expect(tool.toolCallId, 'toolu_c1');
      expect(tool.toolName, 'Shell');
      expect(tool.args, {'command': 'pwd'});
      expect(tool.result, '/tmp/proj');

      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test(
    'parses tool_use without id and drops [REDACTED] text sentinel',
    () async {
      // Mirrors real Cursor agent-transcripts: tool_use often has no id,
      // and a literal [REDACTED] text block sits next to the tools.
      const raw = '''
{"role":"assistant","message":{"content":[{"type":"text","text":"先查 working→idle\\n\\n[REDACTED]"},{"type":"tool_use","name":"Grep","input":{"pattern":"workingSessionIds"}},{"type":"tool_use","name":"Read","input":{"path":"/tmp/a.dart"}}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"[REDACTED]"},{"type":"tool_use","name":"Shell","input":{"command":"pwd"}}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 't.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );

      // Consecutive assistant lines merge into one turn.
      expect(messages, hasLength(1));
      expect(messages.single.parts.whereType<AiTextPart>().single.text,
          '先查 working→idle');
      expect(
        messages.single.parts.whereType<AiToolCallPart>().map((t) => t.toolName),
        ['Grep', 'Read', 'Shell'],
      );
    },
  );

  test(
    'unwraps Cursor <user_query> and strips <timestamp>',
    () async {
      const raw = '''
{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Sat</timestamp>\\n<user_query>\\nhello world\\n</user_query>"}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 'u.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );
      expect(messages, hasLength(1));
      expect((messages.single.parts.single as AiTextPart).text, 'hello world');
    },
  );

  test(
    'parses TeamPilot runtime agent-transcript (no tool id, split lines)',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
      ).readAsBytes();
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(
              name: 'agent_transcript_no_tool_id.jsonl',
              bytes: bytes,
            ),
          ],
        ),
      );

      expect(messages, hasLength(2));
      expect(messages[0].role, AiRole.user);
      expect(
        (messages[0].parts.single as AiTextPart).text,
        'hello',
      );

      final asst = messages[1];
      expect(asst.role, AiRole.assistant);
      expect(asst.parts.whereType<AiToolCallPart>().single.toolName, 'Read');
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        '你好。需要我帮你做什么？',
      );
    },
  );

  test('locateCursorTranscript returns agent-transcripts jsonl', () async {
    await copyFixtureTree();
    final fixture = await File(
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/'
      'chat-aaaa-bbbb-cccc-dddd.jsonl',
    ).readAsBytes();

    final bundle = await locateCursorTranscript(
      ctx(
        configDir: base.path,
        persistedNativeId: 'chat-aaaa-bbbb-cccc-dddd',
      ),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'cursor');
    expect(bundle.fragments, hasLength(1));
    expect(bundle.fragments.single.name, 'chat-aaaa-bbbb-cccc-dddd.jsonl');
    expect(bundle.fragments.single.bytes, fixture);

    final watchMeta = AiHistoryWatchMeta.fromHints(bundle.hints);
    expect(
      watchMeta?.changeWatchRoot,
      p.join(base.path, 'projects', 'home-me-proj'),
    );
    expect(bundle.hints['cacheToken'], contains('shell-pwd.txt'));
    expect(bundle.hints['cacheToken'], isNot(contains('terminals:empty')));
  });

  test('locateCursorTranscript cacheToken changes when terminal file added',
      () async {
    await copyFixtureTree();
    final context = ctx(
      configDir: base.path,
      persistedNativeId: 'chat-aaaa-bbbb-cccc-dddd',
    );

    final before = await locateCursorTranscript(context);
    expect(before, isNotNull);
    final tokenBefore = before!.hints['cacheToken'];

    final terminalsDir = p.join(base.path, 'projects', 'home-me-proj', 'terminals');
    await Directory(terminalsDir).create(recursive: true);
    await File(p.join(terminalsDir, '1.txt')).writeAsString('''
---
pid: 1
command: "echo hi"
started_at: 2026-07-29T10:00:00.000Z
---
hello
''');

    final after = await locateCursorTranscript(context);
    expect(after, isNotNull);
    final tokenAfter = after!.hints['cacheToken'];

    expect(tokenAfter, isNot(equals(tokenBefore)));
    expect(tokenAfter, contains('terminals'));
    expect(tokenAfter, isNot(contains('terminals:empty')));
  });

  test('locateCursorTranscript returns null when missing', () async {
    final bundle = await locateCursorTranscript(ctx(configDir: base.path));
    expect(bundle, isNull);
  });
}
