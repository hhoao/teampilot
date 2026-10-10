import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_transcript.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';
import 'package:teampilot/services/acp/acp_session.dart';

import '../../support/in_memory_filesystem.dart';

String _line(Map<String, Object?> entry) => jsonEncode(entry);

void main() {
  test('missing or empty jsonl replays to no messages', () {
    expect(replayAcpChatTranscript(null), isEmpty);
    expect(replayAcpChatTranscript(''), isEmpty);
    expect(replayAcpChatTranscript('\n\n'), isEmpty);
  });

  test('user + coalesced chunks + stop become two chat bubbles', () {
    final jsonl = [
      _line({
        'type': 'user',
        'text': 'hi',
        'at': '2026-10-10T06:00:00.000Z',
        'seq': 0,
      }),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'Hel',
        'thought': false,
        'at': '2026-10-10T06:00:01.000Z',
        'seq': 1,
      }),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'lo',
        'thought': false,
        'at': '2026-10-10T06:00:01.100Z',
        'seq': 2,
      }),
      _line({
        'type': 'stop',
        'kind': 'endTurn',
        'at': '2026-10-10T06:00:02.000Z',
        'seq': 3,
      }),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'hi');
    expect(messages[0].createdAt, DateTime.parse('2026-10-10T06:00:00.000Z'));
    expect(messages[1].role, AiRole.assistant);
    expect((messages[1].parts.single as AiTextPart).text, 'Hello');
  });

  test('thought chunks stay a separate reasoning part from text', () {
    final jsonl = [
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'think',
        'thought': true,
        'seq': 0,
      }),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'ing',
        'thought': true,
        'seq': 1,
      }),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'Hi',
        'thought': false,
        'seq': 2,
      }),
    ].join('\n');

    final parts = replayAcpChatTranscript(jsonl).single.parts;
    expect(parts, hasLength(2));
    expect((parts[0] as AiReasoningPart).text, 'thinking');
    expect((parts[1] as AiTextPart).text, 'Hi');
  });

  test('tool_call updates upsert onto the same assistant card', () {
    final jsonl = [
      _line({
        'type': 'tool_call',
        'toolCallId': 't1',
        'title': 'read file',
        'status': 'inProgress',
        'seq': 0,
      }),
      _line({
        'type': 'tool_call',
        'toolCallId': 't1',
        'status': 'completed',
        'seq': 1,
      }),
    ].join('\n');

    final part =
        replayAcpChatTranscript(jsonl).single.parts.single as AiToolCallPart;
    expect(part.toolCallId, 't1');
    expect(part.toolName, 'read file');
    expect(part.status, AiToolCallStatus.complete);
    expect(part.isError, isFalse);
  });

  test('cancelled stop does not add a system bubble', () {
    final jsonl = [
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'partial',
        'thought': false,
        'seq': 0,
      }),
      _line({'type': 'stop', 'kind': 'cancelled', 'seq': 1}),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.assistant);
  });

  test('error stop + turn_error system is one system bubble', () {
    final jsonl = [
      _line({'type': 'stop', 'kind': 'error', 'message': 'boom', 'seq': 0}),
      _line({
        'type': 'system',
        'kind': 'turn_error',
        'message': 'Turn failed: boom',
        'seq': 1,
      }),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.system);
    expect(
      (messages.single.parts.single as AiTextPart).text,
      'Turn failed: boom',
    );
  });

  test('handshake auth system rows are not restored as history', () {
    final jsonl = [
      _line({
        'type': 'system',
        'kind': 'auth',
        'message': 'Not logged in',
        'seq': 0,
      }),
      _line({'type': 'user', 'text': 'hi', 'seq': 1}),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'ok',
        'thought': false,
        'seq': 2,
      }),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect(messages[1].role, AiRole.assistant);
  });

  test('processExited from a prior agent process is not restored', () {
    final jsonl = [
      _line({'type': 'user', 'text': 'hi', 'seq': 0}),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'ok',
        'thought': false,
        'seq': 1,
      }),
      _line({
        'type': 'system',
        'kind': 'processExited',
        'message': 'Gemini 意外退出 (0)',
        'seq': 2,
      }),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect(messages[1].role, AiRole.assistant);
  });

  test('skips torn tail lines and unknown types', () {
    final jsonl = [
      _line({'type': 'user', 'text': 'keep', 'seq': 0}),
      '{not-json',
      _line({'type': 'plan', 'seq': 1}),
      _line({
        'type': 'chunk',
        'role': 'assistant',
        'text': 'ok',
        'thought': false,
        'seq': 2,
      }),
    ].join('\n');

    final messages = replayAcpChatTranscript(jsonl);
    expect(messages, hasLength(2));
    expect((messages[0].parts.single as AiTextPart).text, 'keep');
    expect((messages[1].parts.single as AiTextPart).text, 'ok');
  });

  test('writer loadMessages reads the jsonl through the filesystem', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.recordUserPrompt('hello');
    await writer.recordChunk(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'world',
        isThought: false,
      ),
    );
    await writer.recordStop(const AcpStop(kind: AcpStopKind.endTurn));

    final messages = await writer.loadMessages();
    expect(messages, hasLength(2));
    expect((messages[0].parts.single as AiTextPart).text, 'hello');
    expect((messages[1].parts.single as AiTextPart).text, 'world');
  });
}
