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
    test('encodes ResolvedTextTurn as response with output_text', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedTextTurn('hello from assistant'),
        messageId: 'resp_1',
        model: 'mock-model',
      );

      final decoded = jsonDecode(body) as Map<String, Object?>;
      expect(decoded['object'], 'response');
      expect(decoded['id'], 'resp_1');
      expect(decoded['model'], 'mock-model');
      expect(decoded['status'], 'completed');

      final output = decoded['output'] as List<Object?>;
      expect(output, hasLength(1));
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'message');
      expect(item['role'], 'assistant');
      expect(item['status'], 'completed');

      final content = item['content'] as List<Object?>;
      expect(content, hasLength(1));
      final part = content.single as Map<String, Object?>;
      expect(part['type'], 'output_text');
      expect(part['text'], 'hello from assistant');
    });

    test('encodes ResolvedToolUseTurn as function_call output item', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedToolUseTurn(
          id: 'tu1',
          wireName: 'mcp__teammate-bus__send_message',
          input: {'to': 'worker-1', 'content': 'ping'},
        ),
        messageId: 'resp_2',
        model: 'mock-model',
      );

      final decoded = jsonDecode(body) as Map<String, Object?>;
      expect(decoded['object'], 'response');
      expect(decoded['status'], 'completed');

      final output = decoded['output'] as List<Object?>;
      expect(output, hasLength(1));
      final item = output.single as Map<String, Object?>;
      expect(item['type'], 'function_call');
      expect(item['call_id'], 'tu1');
      expect(item['name'], 'mcp__teammate-bus__send_message');
      expect(item['status'], 'completed');
      final args =
          jsonDecode(item['arguments'] as String) as Map<String, Object?>;
      expect(args['to'], 'worker-1');
      expect(args['content'], 'ping');
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

    test('resolved AssignedTaskUpdate encodes as function_call JSON', () {
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

      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final output = decoded['output'] as List<Object?>;
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
