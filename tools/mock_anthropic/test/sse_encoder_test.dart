import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/sse/anthropic_sse_encoder.dart';
import 'package:test/test.dart';

void main() {
  test('encodes tool_use turn as SSE events', () {
    const turn = ToolUseTurn(
      id: 'tu1',
      name: 'send_message',
      input: {'to': 'worker-1', 'content': 'ping'},
    );
    final body = AnthropicSseEncoder.encodeTurn(
      messageId: 'msg_1',
      model: 'mock-model',
      turn: turn,
    );
    expect(body, contains('event: message_start'));
    expect(body, contains('content_block_start'));
    expect(body, contains('tool_use'));
    expect(body, contains('send_message'));
    expect(body, contains('worker-1'));
    expect(body, contains('event: message_stop'));
  });

  test('encodes text turn as SSE events', () {
    final body = AnthropicSseEncoder.encodeTurn(
      messageId: 'msg_2',
      model: 'mock-model',
      turn: TextTurn('done'),
    );
    expect(body, contains('text'));
    expect(body, contains('done'));
    expect(body, contains('end_turn'));
  });
}
