import 'dart:convert';

import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/wire/openai_chat_adapter.dart';
import 'package:mock_model_gateway/wire/wire_adapter.dart';
import 'package:test/test.dart';

void main() {
  late OpenAiChatAdapter adapter;

  setUp(() {
    adapter = OpenAiChatAdapter();
  });

  group('matchesPath', () {
    test('accepts OpenAI Chat Completions paths', () {
      expect(adapter.matchesPath('/v1/chat/completions'), isTrue);
      expect(adapter.matchesPath('/openai/v1/chat/completions'), isTrue);
      expect(adapter.matchesPath('/proxy/v1/chat/completions'), isTrue);
      expect(adapter.matchesPath('/v1/messages'), isFalse);
      expect(adapter.matchesPath('/v1/responses'), isFalse);
    });
  });

  group('encodeResponse', () {
    test('encodes ResolvedTextTurn as non-streaming chat.completion JSON', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedTextTurn('hello from assistant'),
        messageId: 'msg_1',
        model: 'mock-model',
      );

      final decoded = jsonDecode(body) as Map<String, Object?>;
      expect(decoded['object'], 'chat.completion');
      expect(decoded['id'], 'msg_1');
      expect(decoded['model'], 'mock-model');

      final choices = decoded['choices'] as List<Object?>;
      expect(choices, hasLength(1));
      final choice = choices.single as Map<String, Object?>;
      expect(choice['finish_reason'], 'stop');
      final message = choice['message'] as Map<String, Object?>;
      expect(message['role'], 'assistant');
      expect(message['content'], 'hello from assistant');
      expect(message.containsKey('tool_calls'), isFalse);
    });

    test('encodes ResolvedToolUseTurn as tool_calls finish_reason', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedToolUseTurn(
          id: 'tu1',
          wireName: 'mcp__teammate-bus__send_message',
          input: {'to': 'worker-1', 'content': 'ping'},
        ),
        messageId: 'msg_2',
        model: 'mock-model',
      );

      final decoded = jsonDecode(body) as Map<String, Object?>;
      expect(decoded['object'], 'chat.completion');

      final choices = decoded['choices'] as List<Object?>;
      final choice = choices.single as Map<String, Object?>;
      expect(choice['finish_reason'], 'tool_calls');
      final message = choice['message'] as Map<String, Object?>;
      expect(message['role'], 'assistant');
      expect(message['content'], isNull);

      final toolCalls = message['tool_calls'] as List<Object?>;
      expect(toolCalls, hasLength(1));
      final call = toolCalls.single as Map<String, Object?>;
      expect(call['id'], 'tu1');
      expect(call['type'], 'function');
      final function = call['function'] as Map<String, Object?>;
      expect(function['name'], 'mcp__teammate-bus__send_message');
      final args =
          jsonDecode(function['arguments'] as String) as Map<String, Object?>;
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
          messageId: 'msg_3',
          model: 'mock-model',
        ),
        throwsStateError,
      );
    });
  });

  group('resolveInboundTurn', () {
    test('resolves AssignedTaskUpdate from inbound tool message content', () {
      const body = {
        'messages': [
          {
            'role': 'tool',
            'tool_call_id': 'tu_wait_task',
            'content':
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

    test('resolved AssignedTaskUpdate encodes as tool_calls JSON', () {
      const body = {
        'messages': [
          {
            'role': 'tool',
            'tool_call_id': 'tu_wait_task',
            'content':
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
        messageId: 'msg_4',
        model: 'mock-model',
      );

      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final choices = decoded['choices'] as List<Object?>;
      final choice = choices.single as Map<String, Object?>;
      expect(choice['finish_reason'], 'tool_calls');
      final message = choice['message'] as Map<String, Object?>;
      final toolCalls = message['tool_calls'] as List<Object?>;
      final call = toolCalls.single as Map<String, Object?>;
      final function = call['function'] as Map<String, Object?>;
      expect(function['name'], 'mcp__teammate-bus__update_task');
      final args =
          jsonDecode(function['arguments'] as String) as Map<String, Object?>;
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
          {'messages': []},
        ),
        throwsStateError,
      );
    });
  });

  test('implements WireAdapter', () {
    expect(adapter, isA<WireAdapter>());
  });
}
