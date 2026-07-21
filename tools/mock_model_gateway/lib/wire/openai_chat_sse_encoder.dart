import 'dart:convert';

import '../core/turns.dart';

/// OpenAI Chat Completions SSE encoder (`stream: true`).
///
/// OpenCode's `@ai-sdk/openai-compatible` requests `stream: true` and hangs on
/// a plain `chat.completion` JSON body (TUI stays on ▣ Build). Flashskyai still
/// accepts non-streaming JSON — the server picks based on the request flag.
class OpenAiChatSseEncoder {
  static String encodeTurn({
    required String messageId,
    required String model,
    required ResolvedTurn turn,
  }) {
    switch (turn) {
      case ResolvedTextTurn(:final text):
        return _encodeText(
          messageId: messageId,
          model: model,
          text: text,
        );
      case ResolvedToolUseTurn(:final id, :final wireName, :final input):
        return _encodeToolCalls(
          messageId: messageId,
          model: model,
          callId: id,
          name: wireName,
          input: input,
        );
      case ResolvedAssignedTaskUpdateTurn():
        throw StateError(
          'ResolvedAssignedTaskUpdateTurn must be resolved before SSE encoding',
        );
    }
  }

  static String _encodeText({
    required String messageId,
    required String model,
    required String text,
  }) {
    final buf = StringBuffer();
    buf.write(
      _chunk(
        messageId: messageId,
        model: model,
        delta: {'role': 'assistant', 'content': ''},
      ),
    );
    if (text.isNotEmpty) {
      buf.write(
        _chunk(
          messageId: messageId,
          model: model,
          delta: {'content': text},
        ),
      );
    }
    buf.write(
      _chunk(
        messageId: messageId,
        model: model,
        delta: const <String, Object?>{},
        finishReason: 'stop',
      ),
    );
    buf.write('data: [DONE]\n\n');
    return buf.toString();
  }

  static String _encodeToolCalls({
    required String messageId,
    required String model,
    required String callId,
    required String name,
    required Map<String, Object?> input,
  }) {
    final args = jsonEncode(input);
    final buf = StringBuffer();
    buf.write(
      _chunk(
        messageId: messageId,
        model: model,
        delta: {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'index': 0,
              'id': callId,
              'type': 'function',
              'function': {'name': name, 'arguments': ''},
            },
          ],
        },
      ),
    );
    buf.write(
      _chunk(
        messageId: messageId,
        model: model,
        delta: {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': args},
            },
          ],
        },
      ),
    );
    buf.write(
      _chunk(
        messageId: messageId,
        model: model,
        delta: const <String, Object?>{},
        finishReason: 'tool_calls',
      ),
    );
    buf.write('data: [DONE]\n\n');
    return buf.toString();
  }

  static String _chunk({
    required String messageId,
    required String model,
    required Map<String, Object?> delta,
    String? finishReason,
  }) {
    final payload = <String, Object?>{
      'id': messageId,
      'object': 'chat.completion.chunk',
      'created': 0,
      'model': model,
      'choices': [
        {
          'index': 0,
          'delta': delta,
          'finish_reason': finishReason,
        },
      ],
    };
    return 'data: ${jsonEncode(payload)}\n\n';
  }
}
