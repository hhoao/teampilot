import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/claude_ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('claude_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required List<String> transcriptRoots,
    String bucket = 'home-me-proj',
    String taskId = 'task-1',
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: taskId,
      env: const {},
      transcriptRoots: transcriptRoots,
      bucket: bucket,
    );
  }

  test('ClaudeAiTranscriptAdapter parses user text and correlates tool_result',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    final adapter = const ClaudeAiTranscriptAdapter();
    final messages = await adapter.parse(
      AiTranscriptBundle(
        adapterId: adapter.id,
        fragments: [
          AiTranscriptFragment(name: 'basic.jsonl', bytes: bytes),
        ],
      ),
    );

    expect(adapter.id, 'claude');
    expect(messages, hasLength(2));

    final user = messages[0];
    expect(user.id, 'u-1');
    expect(user.role, AiRole.user);
    expect(user.parts, hasLength(1));
    expect(user.parts.single, isA<AiTextPart>());
    expect((user.parts.single as AiTextPart).text, 'hello');
    expect(user.createdAt, DateTime.parse('2026-07-10T10:00:00.000Z'));

    final assistant = messages[1];
    expect(assistant.id, 'a-1');
    expect(assistant.role, AiRole.assistant);
    expect(assistant.parts[0], isA<AiTextPart>());
    expect((assistant.parts[0] as AiTextPart).text, 'hi');
    final tool = assistant.parts.whereType<AiToolCallPart>().single;
    expect(tool.toolCallId, 'toolu_1');
    expect(tool.toolName, 'Bash');
    expect(tool.args, {'command': 'ls'});
    expect(tool.result, 'ok');

    // tool_result-only user turn (u-2) must not become a user message
    expect(messages.any((m) => m.id == 'u-2'), isFalse);
    for (final m in messages.where((m) => m.role == AiRole.user)) {
      expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
    }
  });

  test('skips corrupt JSONL lines', () async {
    final bytes = utf8Bytes('''
{"type":"user","message":{"role":"user","content":"ok"},"uuid":"u-ok"}
not-json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"uuid":"a-ok"}
''');
    final messages = await const ClaudeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [AiTranscriptFragment(name: 'mixed.jsonl', bytes: bytes)],
      ),
    );
    expect(messages.map((m) => m.id), ['u-ok', 'a-ok']);
  });

  test('user text + tool_result emits text and correlates result', () async {
    final bytes = utf8Bytes('''
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"path":"a"}}]},"uuid":"a-1"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"after tool"},{"type":"tool_result","tool_use_id":"t1","content":"file"}]},"uuid":"u-1"}
''');
    final messages = await const ClaudeAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [AiTranscriptFragment(name: 'mixed.jsonl', bytes: bytes)],
      ),
    );
    expect(messages, hasLength(2));
    final tool = messages[0].parts.whereType<AiToolCallPart>().single;
    expect(tool.result, 'file');
    expect(messages[1].id, 'u-1');
    expect(messages[1].role, AiRole.user);
    expect((messages[1].parts.single as AiTextPart).text, 'after tool');
  });

  test('locateClaudeTranscript returns bundle with file bytes', () async {
    final projects = p.join(base.path, 'projects', 'home-me-proj');
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, 'task-1.jsonl')).writeAsBytes(fixture);

    final bundle = await locateClaudeTranscript(
      ctx(transcriptRoots: [base.path]),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'claude');
    expect(bundle.fragments, hasLength(1));
    expect(bundle.fragments.single.name, 'task-1.jsonl');
    expect(bundle.fragments.single.bytes, fixture);

    final transcriptPath = p.join(projects, 'task-1.jsonl');
    final watchMeta = AiHistoryWatchMeta.fromHints(bundle.hints);
    expect(watchMeta, isNotNull);
    expect(watchMeta!.changeWatchRoot, p.dirname(transcriptPath));
    expect(watchMeta.cacheTokenPaths, [transcriptPath]);
  });

  test('locateClaudeTranscript returns null when missing', () async {
    final bundle = await locateClaudeTranscript(
      ctx(transcriptRoots: [base.path]),
    );
    expect(bundle, isNull);
  });

  test(
    'merges streamed assistant lines by message.id and keeps thinking',
    () async {
      // From TeamPilot runtime Claude JSONL (sanitized): thinking + text share
      // message.id across different event uuids.
      final bytes = await File(
        'test/fixtures/session_history/claude/streamed_turn.jsonl',
      ).readAsBytes();
      final messages = await const ClaudeAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(name: 'streamed_turn.jsonl', bytes: bytes),
          ],
        ),
      );

      expect(messages, hasLength(2));
      expect(messages[0].role, AiRole.user);
      expect((messages[0].parts.single as AiTextPart).text, 'hello');

      final asst = messages[1];
      expect(asst.id, 'e6ddd410-d9f2-4647-9608-eea1054e5abc');
      expect(asst.role, AiRole.assistant);
      expect(
        asst.parts.whereType<AiReasoningPart>().single.text,
        'short thinking about greeting',
      );
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        'Hey! Welcome — short reply.',
      );
    },
  );

  test('appendClaudeJsonlEvent merges streamed assistant lines across calls',
      () {
    final messages = <AiMessage>[];
    expect(
      appendClaudeJsonlEvent(
        messages,
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
            'id': 'msg-1',
          },
          'uuid': 'a1',
        },
        fallbackId: () => 'fb',
      ),
      isTrue,
    );
    expect(
      appendClaudeJsonlEvent(
        messages,
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': ' world'},
            ],
            'id': 'msg-1',
          },
          'uuid': 'a2',
        },
        fallbackId: () => 'fb',
      ),
      isTrue,
    );
    expect(messages, hasLength(1));
    expect(
      messages.single.parts.map((p) => (p as AiTextPart).text).join(),
      'hello world',
    );
  });

  test('appendClaudeJsonlEvent skips noise records', () {
    expect(
      appendClaudeJsonlEvent(
        [],
        {'type': 'queue-operation', 'operation': 'enqueue'},
        fallbackId: () => 'fb',
      ),
      isFalse,
    );
  });
}

List<int> utf8Bytes(String s) => utf8.encode(s);
