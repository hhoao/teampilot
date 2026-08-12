import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
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
    expect(tool.status, AiToolCallStatus.complete,
        reason: 'G5: parse-path result application must not leave running');
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

  test(
    'G1: message id priority is message.id -> event uuid -> lazy fallback',
    () {
      // Real Claude Code data (~/.claude/projects scan, 2026-08-12): 7362/11320
      // messages carry message.id, 3958 uuid-only, 0 with no id at all, 0
      // non-contiguous same-id events — priority and merge semantics hold on
      // real transcripts; fallback never triggers there.
      final messages = <AiMessage>[];
      var fallbackSeq = 0;
      String fallback() => 'claude-${fallbackSeq++}';

      expect(
        appendClaudeJsonlEvent(
          messages,
          {
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'with message id'},
              ],
              'id': 'mid-1',
            },
            'uuid': 'uuid-1',
          },
          fallbackId: fallback,
        ),
        isTrue,
      );
      expect(fallbackSeq, 0, reason: 'message.id present must not consume fallback');

      expect(
        appendClaudeJsonlEvent(
          messages,
          {
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'uuid only'},
              ],
            },
            'uuid': 'uuid-2',
          },
          fallbackId: fallback,
        ),
        isTrue,
      );
      expect(fallbackSeq, 0, reason: 'uuid present must not consume fallback');

      expect(
        appendClaudeJsonlEvent(
          messages,
          {
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': 'no ids at all'},
              ],
            },
          },
          fallbackId: fallback,
        ),
        isTrue,
      );
      expect(fallbackSeq, 1, reason: 'id-less consumed event takes one fallback id');

      expect(
        appendClaudeJsonlEvent(
          messages,
          {
            'type': 'queue-operation',
            'operation': 'enqueue',
          },
          fallbackId: fallback,
        ),
        isFalse,
      );
      expect(fallbackSeq, 1,
          reason: 'discarded event must not consume a fallback id');

      expect(
        messages.map((m) => m.id).toList(),
        ['mid-1', 'uuid-2', 'claude-0'],
        reason: 'G1 priority: message.id beats uuid, both beat lazy fallback',
      );
    },
  );

  test('G3: encrypted/empty thinking yields no reasoning part', () {
    // Real Claude Code data: 389/2297 thinking blocks carry null/empty
    // thinking (encrypted), 0 non-string — all discarded, none surface as
    // empty AiReasoningPart.
    expect(
      appendClaudeJsonlEvent(
        [],
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': null},
            ],
          },
          'uuid': 'a-enc',
        },
        fallbackId: () => 'fb',
      ),
      isFalse,
      reason: 'encrypted thinking-only event must be discarded entirely',
    );

    final mixed = <AiMessage>[];
    expect(
      appendClaudeJsonlEvent(
        mixed,
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': '   '},
              {'type': 'text', 'text': 'ok'},
            ],
          },
          'uuid': 'a-mixed',
        },
        fallbackId: () => 'fb',
      ),
      isTrue,
    );
    final parts = mixed.single.parts;
    expect(parts.whereType<AiReasoningPart>(), isEmpty,
        reason: 'empty thinking must not produce a reasoning part');
    expect(parts.single, isA<AiTextPart>());
  });

  test('G4: id-less tool_use is skipped, not synthesized', () {
    final withText = <AiMessage>[];
    expect(
      appendClaudeJsonlEvent(
        withText,
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'ls'}},
              {'type': 'text', 'text': 'plan'},
            ],
          },
          'uuid': 'a-1',
        },
        fallbackId: () => 'fb',
      ),
      isTrue,
    );
    final parts = withText.single.parts;
    expect(parts.whereType<AiToolCallPart>(), isEmpty,
        reason: 'id-less tool_use must not become a tool part');
    expect(parts.single, isA<AiTextPart>());

    expect(
      appendClaudeJsonlEvent(
        [],
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'ls'}},
            ],
          },
          'uuid': 'a-2',
        },
        fallbackId: () => 'fb',
      ),
      isFalse,
      reason: 'id-less tool_use-only event must be discarded (no synthesis)',
    );
  });

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
