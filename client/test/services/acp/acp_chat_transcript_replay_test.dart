import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_transcript.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';

import '../../support/in_memory_filesystem.dart';

String _line(Map<String, Object?> entry) => jsonEncode(entry);

void main() {
  test('missing or empty jsonl decodes to no messages', () {
    expect(decodeAcpChatTranscript(null), isEmpty);
    expect(decodeAcpChatTranscript(''), isEmpty);
    expect(decodeAcpChatTranscript('\n\n'), isEmpty);
  });

  test('legacy chunk jsonl without v:1 decodes to empty', () {
    final jsonl = _line({
      'type': 'chunk',
      'role': 'assistant',
      'text': 'Hello',
      'seq': 0,
    });
    expect(decodeAcpChatTranscript(jsonl), isEmpty);
  });

  test('garbage and non-v1 lines are skipped', () {
    final jsonl = [
      'not-json',
      _line({'v': 1, 'type': 'nope', 'id': 'x'}),
      _line({'v': 1, 'type': 'user', 'id': 'acp-u-1', 'text': 'hi'}),
    ].join('\n');
    final messages = decodeAcpChatTranscript(jsonl);
    expect(messages, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, 'hi');
  });

  test('round-trips user, assistant parts, and system', () {
    final original = [
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
        createdAt: DateTime.utc(2026, 10, 10, 6),
      ),
      AiMessage(
        id: 'acp-a-1',
        role: AiRole.assistant,
        parts: const [
          AiReasoningPart(text: 'think'),
          AiTextPart(text: 'Hello'),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Read',
            status: AiToolCallStatus.complete,
            isError: false,
          ),
        ],
        createdAt: DateTime.utc(2026, 10, 10, 6, 0, 1),
      ),
      AiMessage(
        id: 'acp-sys-1',
        role: AiRole.system,
        parts: const [AiTextPart(text: 'Turn failed')],
        createdAt: DateTime.utc(2026, 10, 10, 6, 0, 2),
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    expect(loaded, hasLength(3));
    expect(loaded[0].id, 'acp-u-1');
    expect(loaded[0].role, AiRole.user);
    expect((loaded[0].parts.single as AiTextPart).text, 'hi');
    expect(loaded[1].id, 'acp-a-1');
    final parts = loaded[1].parts;
    expect(parts[0], isA<AiReasoningPart>());
    expect((parts[0] as AiReasoningPart).text, 'think');
    expect((parts[1] as AiTextPart).text, 'Hello');
    final tool = parts[2] as AiToolCallPart;
    expect(tool.toolCallId, 't1');
    expect(tool.toolName, 'Read');
    expect(tool.status, AiToolCallStatus.complete);
    expect(tool.isError, isFalse);
    expect((loaded[2].parts.single as AiTextPart).text, 'Turn failed');
  });

  test('round-trips TodoWrite args and task category', () {
    final original = [
      AiMessage(
        id: 'acp-a-todo',
        role: AiRole.assistant,
        parts: const [
          AiToolCallPart(
            toolCallId: 'TodoWrite',
            toolName: 'TodoWrite',
            category: AiToolCallCategory.task,
            status: AiToolCallStatus.complete,
            args: {
              'merge': true,
              'todos': [
                {'id': 'a', 'content': 'Task A', 'status': 'completed'},
                {'id': 'b', 'content': 'Task B', 'status': 'pending'},
              ],
            },
          ),
        ],
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    expect(loaded, hasLength(1));
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolName, 'TodoWrite');
    expect(part.category, AiToolCallCategory.task);
    expect(part.args?['merge'], isTrue);
    expect(part.args?['todos'], [
      {'id': 'a', 'content': 'Task A', 'status': 'completed'},
      {'id': 'b', 'content': 'Task B', 'status': 'pending'},
    ]);
  });

  test('round-trips generate_image filePath in args', () {
    final original = [
      AiMessage(
        id: 'acp-a-img',
        role: AiRole.assistant,
        parts: const [
          AiToolCallPart(
            toolCallId: 'img-1',
            toolName: 'generate_image',
            status: AiToolCallStatus.complete,
            args: {'description': 'a cat', 'filePath': '/tmp/cat.png'},
          ),
        ],
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolName, 'generate_image');
    expect(part.args, {'description': 'a cat', 'filePath': '/tmp/cat.png'});
  });

  test('old tool lines without args or category still decode', () {
    final jsonl = _line({
      'v': 1,
      'type': 'assistant',
      'id': 'acp-a-1',
      'parts': [
        {
          'kind': 'tool',
          'toolCallId': 't1',
          'title': 'Read',
          'status': 'complete',
          'isError': false,
        },
      ],
    });
    final loaded = decodeAcpChatTranscript(jsonl);
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolCallId, 't1');
    expect(part.toolName, 'Read');
    expect(part.status, AiToolCallStatus.complete);
    expect(part.category, AiToolCallCategory.other);
    expect(part.args, isNull);
  });

  test('mergeHydratedAcpMessages appends a live landing prompt', () {
    final loaded = [
      AiMessage(
        id: 'acp-u-old',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'old')],
      ),
    ];
    final live = [
      AiMessage(
        id: 'acp-u-next',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'next')],
      ),
    ];
    final merged = mergeHydratedAcpMessages(loaded: loaded, live: live);
    expect(merged, hasLength(2));
    expect((merged.last.parts.single as AiTextPart).text, 'next');
  });

  test('saveMessages round-trips through loadMessages', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hello')],
      ),
    ]);
    final loaded = await writer.loadMessages();
    expect(loaded, hasLength(1));
    expect((loaded.single.parts.single as AiTextPart).text, 'hello');
    expect(fs.files[path], contains('"v":1'));
    expect(fs.files[path], isNot(contains('"type":"chunk"')));
  });

  test('loadMessages treats a missing file as empty', () async {
    final writer = AcpChatTranscriptWriter(
      fs: InMemoryFilesystem(),
      path: '/tp/missing.jsonl',
    );
    expect(await writer.loadMessages(), isEmpty);
  });

  test('second saveMessages replaces the previous snapshot', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'first')],
      ),
    ]);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-2',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'second')],
      ),
    ]);
    final loaded = await writer.loadMessages();
    expect(loaded, hasLength(1));
    expect((loaded.single.parts.single as AiTextPart).text, 'second');
  });
}
