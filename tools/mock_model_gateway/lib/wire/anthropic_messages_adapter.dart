import '../core/turns.dart';
import 'anthropic_sse_encoder.dart';
import 'assigned_task_id_parser.dart';
import 'wire_adapter.dart';

/// Anthropic Messages (`/v1/messages`) wire adapter.
class AnthropicMessagesAdapter implements WireAdapter {
  @override
  bool matchesPath(String path) {
    return path == '/v1/messages' ||
        path == '/anthropic/v1/messages' ||
        path.endsWith('/v1/messages');
  }

  @override
  String encodeResponse({
    required ResolvedTurn turn,
    required String messageId,
    required String model,
  }) {
    return AnthropicSseEncoder.encodeTurn(
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
    final taskId = extractAssignedTaskIdFromAnthropicRequest(requestBody);
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
