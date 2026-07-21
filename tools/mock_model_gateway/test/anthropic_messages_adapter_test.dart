import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/wire/anthropic_messages_adapter.dart';
import 'package:mock_model_gateway/wire/wire_adapter.dart';
import 'package:test/test.dart';

void main() {
  late AnthropicMessagesAdapter adapter;

  setUp(() {
    adapter = AnthropicMessagesAdapter();
  });

  group('matchesPath', () {
    test('accepts Anthropic Messages paths', () {
      expect(adapter.matchesPath('/v1/messages'), isTrue);
      expect(adapter.matchesPath('/anthropic/v1/messages'), isTrue);
      expect(adapter.matchesPath('/proxy/v1/messages'), isTrue);
      expect(adapter.matchesPath('/v1/chat/completions'), isFalse);
    });
  });

  group('encodeResponse', () {
    test('encodes ResolvedTextTurn as SSE with assistant text', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedTextTurn('hello from assistant'),
        messageId: 'msg_1',
        model: 'mock-model',
      );

      expect(body, contains('event: message_start'));
      expect(body, contains('"role":"assistant"'));
      expect(body, contains('text_delta'));
      expect(body, contains('hello from assistant'));
      expect(body, contains('end_turn'));
      expect(body, contains('event: message_stop'));
    });

    test('encodes ResolvedToolUseTurn as SSE tool_use block', () {
      final body = adapter.encodeResponse(
        turn: const ResolvedToolUseTurn(
          id: 'tu1',
          wireName: 'mcp__teammate-bus__send_message',
          input: {'to': 'worker-1', 'content': 'ping'},
        ),
        messageId: 'msg_2',
        model: 'mock-model',
      );

      expect(body, contains('event: message_start'));
      expect(body, contains('tool_use'));
      expect(body, contains('mcp__teammate-bus__send_message'));
      expect(body, contains('worker-1'));
      expect(body, contains('tool_use'));
      expect(body, contains('"stop_reason":"tool_use"'));
      expect(body, contains('event: message_stop'));
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
    test('resolves AssignedTaskUpdate from inbound tool_result', () {
      const body = {
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'tu_wait_task',
                'content':
                    'ASSIGNED TASK (claimed for you from the shared work queue):\n'
                    '--- 8ba4fa9c-a804-424e-9f91-ab9e2ca62fea [claimed] ---\n'
                    'title: complete-widget',
              },
            ],
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

    test('resolved AssignedTaskUpdate encodes as tool_use SSE', () {
      const body = {
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'tu_wait_task',
                'content':
                    '{"id":"8ba4fa9c-a804-424e-9f91-ab9e2ca62fea",'
                    '"status":"claimed","title":"complete-widget"}',
              },
            ],
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
      final sse = adapter.encodeResponse(
        turn: turn,
        messageId: 'msg_4',
        model: 'mock-model',
      );

      expect(sse, contains('tool_use'));
      expect(sse, contains('mcp__teammate-bus__update_task'));
      expect(sse, contains('8ba4fa9c-a804-424e-9f91-ab9e2ca62fea'));
      expect(sse, contains('completed'));
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
