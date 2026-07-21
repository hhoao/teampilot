import 'dart:convert';

import '../core/turns.dart';

/// OpenAI Responses SSE encoder for Codex (`stream: true`).
///
/// Codex always posts with `Accept: text/event-stream` and requires a stream
/// that ends in `response.completed` (non-streaming JSON is rejected).
class OpenAiResponsesSseEncoder {
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
        return _encodeFunctionCall(
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
    final itemId = 'msg_$messageId';
    final completedItem = <String, Object?>{
      'id': itemId,
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
    };
    final completed = _responseEnvelope(
      messageId: messageId,
      model: model,
      status: 'completed',
      output: [completedItem],
    );
    final created = _responseEnvelope(
      messageId: messageId,
      model: model,
      status: 'in_progress',
      output: const [],
    );

    var seq = 0;
    final events = <String>[
      _event('response.created', {
        'type': 'response.created',
        'response': created,
      }, seq++),
      _event('response.output_item.added', {
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': {
          'id': itemId,
          'type': 'message',
          'role': 'assistant',
          'status': 'in_progress',
          'content': <Object?>[],
        },
      }, seq++),
      _event('response.content_part.added', {
        'type': 'response.content_part.added',
        'item_id': itemId,
        'output_index': 0,
        'content_index': 0,
        'part': {
          'type': 'output_text',
          'text': '',
          'annotations': <Object?>[],
        },
      }, seq++),
      _event('response.output_text.delta', {
        'type': 'response.output_text.delta',
        'item_id': itemId,
        'output_index': 0,
        'content_index': 0,
        'delta': text,
      }, seq++),
      _event('response.output_text.done', {
        'type': 'response.output_text.done',
        'item_id': itemId,
        'output_index': 0,
        'content_index': 0,
        'text': text,
      }, seq++),
      _event('response.content_part.done', {
        'type': 'response.content_part.done',
        'item_id': itemId,
        'output_index': 0,
        'content_index': 0,
        'part': {
          'type': 'output_text',
          'text': text,
          'annotations': <Object?>[],
        },
      }, seq++),
      _event('response.output_item.done', {
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': completedItem,
      }, seq++),
      _event('response.completed', {
        'type': 'response.completed',
        'response': completed,
      }, seq),
    ];
    return events.join();
  }

  /// Splits Codex namespaced MCP wire names (`mcp__teammate_bus::wait_for_message`)
  /// into Responses `namespace` + short `name`. Plain wire names are unchanged.
  static ({String name, String? namespace}) splitWireName(String wireName) {
    const sep = '::';
    final idx = wireName.indexOf(sep);
    if (idx <= 0) return (name: wireName, namespace: null);
    return (
      name: wireName.substring(idx + sep.length),
      namespace: wireName.substring(0, idx),
    );
  }

  static String _encodeFunctionCall({
    required String messageId,
    required String model,
    required String callId,
    required String name,
    required Map<String, Object?> input,
  }) {
    final parts = splitWireName(name);
    final toolName = parts.name;
    final namespace = parts.namespace;
    final argsJson = jsonEncode(input);
    final completedItem = <String, Object?>{
      'id': callId,
      'type': 'function_call',
      'call_id': callId,
      'name': toolName,
      if (namespace != null) 'namespace': namespace,
      'arguments': argsJson,
      'status': 'completed',
    };
    final completed = _responseEnvelope(
      messageId: messageId,
      model: model,
      status: 'completed',
      output: [completedItem],
    );
    final created = _responseEnvelope(
      messageId: messageId,
      model: model,
      status: 'in_progress',
      output: const [],
    );

    final inProgressItem = <String, Object?>{
      'id': callId,
      'type': 'function_call',
      'call_id': callId,
      'name': toolName,
      if (namespace != null) 'namespace': namespace,
      'arguments': '',
      'status': 'in_progress',
    };

    var seq = 0;
    final events = <String>[
      _event('response.created', {
        'type': 'response.created',
        'response': created,
      }, seq++),
      _event('response.output_item.added', {
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': inProgressItem,
      }, seq++),
      _event('response.function_call_arguments.delta', {
        'type': 'response.function_call_arguments.delta',
        'item_id': callId,
        'output_index': 0,
        'delta': argsJson,
      }, seq++),
      _event('response.function_call_arguments.done', {
        'type': 'response.function_call_arguments.done',
        'item_id': callId,
        'output_index': 0,
        'arguments': argsJson,
      }, seq++),
      _event('response.output_item.done', {
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': completedItem,
      }, seq++),
      _event('response.completed', {
        'type': 'response.completed',
        'response': completed,
      }, seq),
    ];
    return events.join();
  }

  static Map<String, Object?> _responseEnvelope({
    required String messageId,
    required String model,
    required String status,
    required List<Map<String, Object?>> output,
  }) =>
      {
        'id': messageId,
        'object': 'response',
        'created_at': 0,
        'status': status,
        'model': model,
        'output': output,
        'usage': {
          'input_tokens': 1,
          'output_tokens': 1,
          'total_tokens': 2,
        },
      };

  static String _event(
    String type,
    Map<String, Object?> data,
    int sequenceNumber,
  ) {
    final payload = <String, Object?>{
      ...data,
      'sequence_number': sequenceNumber,
    };
    return 'event: $type\ndata: ${jsonEncode(payload)}\n\n';
  }
}
