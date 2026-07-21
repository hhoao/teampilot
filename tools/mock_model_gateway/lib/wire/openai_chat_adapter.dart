import 'dart:convert';

import '../core/turns.dart';
import 'assigned_task_id_parser.dart';
import 'openai_chat_sse_encoder.dart';
import 'wire_adapter.dart';

/// OpenAI Chat Completions (`/v1/chat/completions`) wire adapter.
///
/// Default [encodeResponse] is non-streaming `chat.completion` JSON (flashskyai).
/// When the request sets `stream: true` (OpenCode), the server uses
/// [OpenAiChatSseEncoder] instead — see [wantsStream].
class OpenAiChatAdapter implements WireAdapter {
  @override
  String get wireId => 'openai_chat';

  @override
  String get responseMimeType => 'application/json';

  /// Whether [requestBody] asks for SSE (`stream: true`).
  static bool wantsStream(Map<String, Object?>? requestBody) =>
      requestBody?['stream'] == true;

  @override
  bool matchesPath(String path) {
    return path == '/v1/chat/completions' ||
        path == '/openai/v1/chat/completions' ||
        path.endsWith('/v1/chat/completions');
  }

  @override
  String encodeResponse({
    required ResolvedTurn turn,
    required String messageId,
    required String model,
  }) {
    final Map<String, Object?> message;
    final String finishReason;

    switch (turn) {
      case ResolvedTextTurn(:final text):
        message = {
          'role': 'assistant',
          'content': text,
        };
        finishReason = 'stop';
      case ResolvedToolUseTurn(:final id, :final wireName, :final input):
        message = {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': id,
              'type': 'function',
              'function': {
                'name': wireName,
                'arguments': jsonEncode(input),
              },
            },
          ],
        };
        finishReason = 'tool_calls';
      case ResolvedAssignedTaskUpdateTurn():
        throw StateError(
          'ResolvedAssignedTaskUpdateTurn must be resolved before encoding',
        );
    }

    return jsonEncode({
      'id': messageId,
      'object': 'chat.completion',
      'created': 0,
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': message,
          'finish_reason': finishReason,
        },
      ],
      'usage': {
        'prompt_tokens': 1,
        'completion_tokens': 1,
        'total_tokens': 2,
      },
    });
  }

  /// Encode [turn] for `stream: true` clients (OpenCode).
  String encodeStreamingResponse({
    required ResolvedTurn turn,
    required String messageId,
    required String model,
  }) =>
      OpenAiChatSseEncoder.encodeTurn(
        messageId: messageId,
        model: model,
        turn: turn,
      );

  @override
  ResolvedTurn resolveInboundTurn(
    ResolvedTurn turn,
    Map<String, Object?>? requestBody,
  ) {
    if (turn is! ResolvedAssignedTaskUpdateTurn) return turn;
    final taskId = extractAssignedTaskIdFromOpenAiRequest(requestBody);
    if (taskId == null) {
      throw StateError(
        'AssignedTaskUpdateTurn ${turn.id}: no ASSIGNED TASK id in request body',
      );
    }
    return ResolvedToolUseTurn(
      id: turn.id,
      wireName: turn.wireName,
      input: {
        'task_id': taskId,
        'status': turn.status,
        if (turn.result != null) 'result': turn.result,
      },
    );
  }
}
