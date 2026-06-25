import 'dart:convert';

import 'package:mock_anthropic/scenario.dart';

class AnthropicSseEncoder {
  static String encodeTurn({
    required String messageId,
    required String model,
    required MockTurn turn,
  }) {
    final events = <String>[];

    events.add(_event('message_start', {
      'type': 'message_start',
      'message': {
        'id': messageId,
        'type': 'message',
        'role': 'assistant',
        'content': [],
        'model': model,
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {'input_tokens': 1, 'output_tokens': 1},
      },
    }));

    switch (turn) {
      case ToolUseTurn(:final id, :final name, :final input):
        events.add(_event('content_block_start', {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': id,
            'name': name,
            'input': <String, Object?>{},
          },
        }));
        events.add(_event('content_block_delta', {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(input),
          },
        }));
        events.add(_event('content_block_stop', {
          'type': 'content_block_stop',
          'index': 0,
        }));
        events.add(_event('message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        }));
      case TextTurn(:final text):
        events.add(_event('content_block_start', {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }));
        events.add(_event('content_block_delta', {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': text},
        }));
        events.add(_event('content_block_stop', {
          'type': 'content_block_stop',
          'index': 0,
        }));
        events.add(_event('message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        }));
    }

    events.add(_event('message_stop', {'type': 'message_stop'}));
    return events.join();
  }

  static String _event(String type, Map<String, Object?> data) {
    return 'event: $type\ndata: ${jsonEncode(data)}\n\n';
  }
}
