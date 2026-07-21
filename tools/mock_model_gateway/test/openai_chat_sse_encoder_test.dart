import 'dart:convert';

import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/wire/openai_chat_adapter.dart';
import 'package:mock_model_gateway/wire/openai_chat_sse_encoder.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiChatSseEncoder', () {
    test('encodes text turn as chat.completion.chunk SSE ending in [DONE]', () {
      final body = OpenAiChatSseEncoder.encodeTurn(
        messageId: 'msg_1',
        model: 'mock-model',
        turn: const ResolvedTextTurn('MARK_A1'),
      );

      expect(body, contains('chat.completion.chunk'));
      expect(body, contains('MARK_A1'));
      expect(body, contains('data: [DONE]'));
      expect(body, contains('"finish_reason":"stop"'));

      final chunks = body
          .split('\n\n')
          .where((c) => c.startsWith('data: ') && !c.contains('[DONE]'))
          .map((c) => jsonDecode(c.substring('data: '.length)) as Map)
          .toList();
      expect(chunks, isNotEmpty);
      expect(chunks.first['object'], 'chat.completion.chunk');
    });

    test('encodes tool_calls as streaming deltas', () {
      final body = OpenAiChatSseEncoder.encodeTurn(
        messageId: 'msg_2',
        model: 'mock-model',
        turn: const ResolvedToolUseTurn(
          id: 'tu1',
          wireName: 'mcp__teammate-bus__send_message',
          input: {'to': 'worker-1', 'content': 'ping'},
        ),
      );

      expect(body, contains('tool_calls'));
      expect(body, contains('mcp__teammate-bus__send_message'));
      expect(body, contains('"finish_reason":"tool_calls"'));
      expect(body, contains('data: [DONE]'));
    });
  });

  group('OpenAiChatAdapter.wantsStream', () {
    test('true only when stream flag is set', () {
      expect(OpenAiChatAdapter.wantsStream({'stream': true}), isTrue);
      expect(OpenAiChatAdapter.wantsStream({'stream': false}), isFalse);
      expect(OpenAiChatAdapter.wantsStream(null), isFalse);
    });

    test('encodeStreamingResponse delegates to SSE encoder', () {
      final adapter = OpenAiChatAdapter();
      final body = adapter.encodeStreamingResponse(
        turn: const ResolvedTextTurn('hi'),
        messageId: 'msg_s',
        model: 'm',
      );
      expect(body, contains('data: [DONE]'));
      expect(body, contains('hi'));
    });
  });
}
