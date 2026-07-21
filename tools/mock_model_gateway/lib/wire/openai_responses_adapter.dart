import 'dart:convert';

import '../core/turns.dart';
import 'assigned_task_id_parser.dart';
import 'wire_adapter.dart';

/// OpenAI Responses (`/v1/responses`) wire adapter for Codex.
///
/// Codex providers set `wire_api = "responses"` and `requires_openai_auth =
/// true`, so the CLI posts to `{base_url}/responses` with
/// `Authorization: Bearer <OPENAI_API_KEY>`. Encodes non-streaming
/// `object: "response"` JSON that Codex accepts.
class OpenAiResponsesAdapter implements WireAdapter {
  @override
  bool matchesPath(String path) {
    return path == '/v1/responses' ||
        path == '/openai/v1/responses' ||
        path.endsWith('/v1/responses');
  }

  @override
  String encodeResponse({
    required ResolvedTurn turn,
    required String messageId,
    required String model,
  }) {
    final List<Map<String, Object?>> output;

    switch (turn) {
      case ResolvedTextTurn(:final text):
        output = [
          {
            'id': messageId,
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            'content': [
              {
                'type': 'output_text',
                'text': text,
                'annotations': <Object?>[],
              },
            ],
          },
        ];
      case ResolvedToolUseTurn(:final id, :final wireName, :final input):
        output = [
          {
            'id': id,
            'type': 'function_call',
            'call_id': id,
            'name': wireName,
            'arguments': jsonEncode(input),
            'status': 'completed',
          },
        ];
      case ResolvedAssignedTaskUpdateTurn():
        throw StateError(
          'ResolvedAssignedTaskUpdateTurn must be resolved before encoding',
        );
    }

    return jsonEncode({
      'id': messageId,
      'object': 'response',
      'created_at': 0,
      'status': 'completed',
      'model': model,
      'output': output,
      'usage': {
        'input_tokens': 1,
        'output_tokens': 1,
        'total_tokens': 2,
      },
    });
  }

  @override
  ResolvedTurn resolveInboundTurn(
    ResolvedTurn turn,
    Map<String, Object?>? requestBody,
  ) {
    if (turn is! ResolvedAssignedTaskUpdateTurn) return turn;
    final taskId = extractAssignedTaskIdFromOpenAiResponsesRequest(requestBody);
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
