import '../core/turns.dart';
import 'assigned_task_id_parser.dart';
import 'openai_responses_sse_encoder.dart';
import 'wire_adapter.dart';

/// OpenAI Responses (`/v1/responses`) wire adapter for Codex.
///
/// Codex providers set `wire_api = "responses"` and `requires_openai_auth =
/// true`, so the CLI posts to `{base_url}/responses` with
/// `Authorization: Bearer <OPENAI_API_KEY>` and **always** `stream: true`
/// (`Accept: text/event-stream`). Non-streaming JSON is rejected
/// (`stream closed before response.completed`).
class OpenAiResponsesAdapter implements WireAdapter {
  @override
  String get wireId => 'openai_responses';

  @override
  String get responseMimeType => 'text/event-stream';

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
    return OpenAiResponsesSseEncoder.encodeTurn(
      messageId: messageId,
      model: model,
      turn: turn,
    );
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
