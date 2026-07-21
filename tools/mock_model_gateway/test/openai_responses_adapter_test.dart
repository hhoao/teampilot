import 'dart:convert';

import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/wire/openai_responses_adapter.dart';
import 'package:mock_model_gateway/wire/wire_adapter.dart';
import 'package:test/test.dart';

void main() {
  late OpenAiResponsesAdapter adapter;

  setUp(() {
    adapter = OpenAiResponsesAdapter();
  });

  group('matchesPath', () {
    test('accepts OpenAI Responses paths', () {
      expect(adapter.matchesPath('/v1/responses'), isTrue);
      expect(adapter.matchesPath('/openai/v1/responses'), isTrue);
      expect(adapter.matchesPath('/proxy/v1/responses'), isTrue);
      expect(adapter.matchesPath('/v1/chat/completions'), isFalse);
      expect(adapter.matchesPath('/v1/messages'), isFalse);
    });
  });

  group('encodeResponse', () {
    test('encodes ResolvedTextTurn as SSE ending in response.completed', () {
      expect(adapter.responseMimeType, 'text/event-stream');

      final body = adapter.encodeResponse(
        turn: const ResolvedTextTurn('hello from assistant'),
        messageId: 'resp_1',
        model: 'mock-model',
      );

      expect(body, contains('event: response.created'));
      expect(body, contains('event: response.output_text.delta'));
      expect(body, contains('event: response.completed'));
      expect(body, contains('hello from assistant'));
      expect(body, contains('"object":"response"'));

      final completed = _lastEventData(body, 'response.completed');
      final response = completed['response'] as Map<String, Object?>;
      expect(response['id'], 'resp_1');
      expect(response['model'], 'mock-model');
      expect(response['status'], 'completed');
      final output = response['output'] as List<Object?>;
      expect(output, hasLength(1));
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'message');
      final content = item['content'] as List<Object?>;
      final part = content.single as Map<String, Object?>;
      expect(part['type'], 'output_text');
      expect(part['text'], 'hello from assistant');
    });

    test('encodes ResolvedToolUseTurn as function_call SSE', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedToolUseTurn(
          id: 'tu1',
          wireName: 'mcp__teammate-bus__send_message',
          input: {'to': 'worker-1', 'content': 'ping'},
        ),
        messageId: 'resp_2',
        model: 'mock-model',
      );

      expect(body, contains('event: response.function_call_arguments.done'));
      expect(body, contains('event: response.completed'));
      expect(body, contains('mcp__teammate-bus__send_message'));

      final completed = _lastEventData(body, 'response.completed');
      final response = completed['response'] as Map<String, Object?>;
      final output = response['output'] as List<Object?>;
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'function_call');
      expect(item['call_id'], 'tu1');
      expect(item['name'], 'mcp__teammate-bus__send_message');
      expect(item.containsKey('namespace'), isFalse);
      final args =
          jsonDecode(item['arguments'] as String) as Map<String, Object?>;
      expect(args['to'], 'worker-1');
      expect(args['content'], 'ping');
    });

    test('splits Codex namespaced wire names into namespace + short name', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedToolUseTurn(
          id: 'tu_wait',
          wireName: 'mcp__teammate_bus::wait_for_message',
          input: {},
        ),
        messageId: 'resp_ns',
        model: 'mock-model',
      );

      final completed = _lastEventData(body, 'response.completed');
      final response = completed['response'] as Map<String, Object?>;
      final output = response['output'] as List<Object?>;
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'function_call');
      expect(item['name'], 'wait_for_message');
      expect(item['namespace'], 'mcp__teammate_bus');
    });

    test('rejects unresolved AssignedTaskUpdateTurn', () {
      expect(
        () => adapter.encodeResponse(
          turn: const ResolvedAssignedTaskUpdateTurn(
            id: 'upd1',
            wireName: 'mcp__teammate-bus__update_task',
            status: 'completed',
          ),
          messageId: 'resp_3',
          model: 'mock-model',
        ),
        throwsStateError,
      );
    });
  });

  group('resolveInboundTurn', () {
    test('resolves AssignedTaskUpdate from function_call_output', () {
      const body = {
        'input': [
          {
            'type': 'function_call_output',
            'call_id': 'tu_wait_task',
            'output':
                'ASSIGNED TASK (claimed for you from the shared work queue):\n'
                '--- 8ba4fa9c-a804-424e-9f91-ab9e2ca62fea [claimed] ---\n'
                'title: complete-widget',
          },
        ],
      };

      final resolved = adapter.resolveInboundTurn(
        const ResolvedAssignedTaskUpdateTurn(
          id: 'upd1',
          wireName: 'mcp__teammate-bus__update_task',
          status: 'completed',
          result: 'done',
        ),
        body,
      );

      expect(resolved, isA<ResolvedToolUseTurn>());
      final tool = resolved as ResolvedToolUseTurn;
      expect(tool.id, 'upd1');
      expect(tool.wireName, 'mcp__teammate-bus__update_task');
      expect(tool.input['task_id'], '8ba4fa9c-a804-424e-9f91-ab9e2ca62fea');
      expect(tool.input['status'], 'completed');
      expect(tool.input['result'], 'done');
    });

    test('resolved AssignedTaskUpdate encodes as function_call SSE', () {
      const body = {
        'input': [
          {
            'type': 'function_call_output',
            'call_id': 'tu_wait_task',
            'output':
                '{"id":"8ba4fa9c-a804-424e-9f91-ab9e2ca62fea",'
                '"status":"claimed","title":"complete-widget"}',
          },
        ],
      };

      final turn = adapter.resolveInboundTurn(
        const ResolvedAssignedTaskUpdateTurn(
          id: 'upd1',
          wireName: 'mcp__teammate-bus__update_task',
          status: 'completed',
        ),
        body,
      );
      final encoded = adapter.encodeResponse(
        turn: turn,
        messageId: 'resp_4',
        model: 'mock-model',
      );

      expect(encoded, contains('event: response.completed'));
      final completed = _lastEventData(encoded, 'response.completed');
      final response = completed['response'] as Map<String, Object?>;
      final output = response['output'] as List<Object?>;
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'function_call');
      expect(item['name'], 'mcp__teammate-bus__update_task');
      final args =
          jsonDecode(item['arguments'] as String) as Map<String, Object?>;
      expect(args['task_id'], '8ba4fa9c-a804-424e-9f91-ab9e2ca62fea');
      expect(args['status'], 'completed');
    });

    test('passes through non-AssignedTaskUpdate turns', () {
      const text = ResolvedTextTurn('noop');
      expect(adapter.resolveInboundTurn(text, null), same(text));
    });

    test('throws when AssignedTaskUpdate has no task id in body', () {
      expect(
        () => adapter.resolveInboundTurn(
          const ResolvedAssignedTaskUpdateTurn(
            id: 'upd1',
            wireName: 'mcp__teammate-bus__update_task',
            status: 'completed',
          ),
          {'input': []},
        ),
        throwsStateError,
      );
    });
  });

  test('implements WireAdapter', () {
    expect(adapter, isA<WireAdapter>());
  });
}

Map<String, Object?> _lastEventData(String sse, String eventType) {
  final chunks = sse.split('\n\n');
  Map<String, Object?>? last;
  for (final chunk in chunks) {
    if (!chunk.contains('event: $eventType')) continue;
    final dataLine = chunk
        .split('\n')
        .firstWhere((l) => l.startsWith('data: '), orElse: () => '');
    if (dataLine.isEmpty) continue;
    last = jsonDecode(dataLine.substring('data: '.length))
        as Map<String, Object?>;
  }
  expect(last, isNotNull, reason: 'missing event $eventType in SSE');
  return last!;
}
