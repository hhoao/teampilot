import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps contiguous R|T runs in Cot; text stays outside', () {
    final nodes = groupMessageParts([
      const AiReasoningPart(text: 'r1'),
      AiToolCallPart(toolCallId: '1', toolName: 'shell_command'),
      const AiReasoningPart(text: 'r2'),
      AiToolCallPart(toolCallId: '2', toolName: 'shell_command'),
      const AiTextPart(text: 'done'),
    ]);
    expect(nodes, hasLength(2));
    expect(nodes[0], isA<AiRenderChainOfThought>());
    expect((nodes[0] as AiRenderChainOfThought).parts, hasLength(4));
    expect(nodes[1], isA<AiRenderPart>());
  });

  test('opens a second Cot after mid-turn text', () {
    final nodes = groupMessageParts([
      const AiReasoningPart(text: 'a'),
      const AiTextPart(text: 'mid'),
      AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      const AiTextPart(text: 'end'),
    ]);
    expect(nodes, hasLength(4));
    expect(nodes[0], isA<AiRenderChainOfThought>());
    expect(nodes[1], isA<AiRenderPart>());
    expect(nodes[2], isA<AiRenderChainOfThought>());
    expect(nodes[3], isA<AiRenderPart>());
  });

  test('pure text has no Cot', () {
    final nodes = groupMessageParts([const AiTextPart(text: 'hi')]);
    expect(nodes.single, isA<AiRenderPart>());
  });

  test('groupConsecutiveParts still groups tools and reasoning', () {
    final nodes = groupConsecutiveParts([
      AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      AiToolCallPart(toolCallId: '2', toolName: 'Grep'),
      const AiReasoningPart(text: 'a'),
      const AiReasoningPart(text: 'b'),
    ]);
    expect(nodes[0], isA<AiRenderToolGroup>());
    expect(nodes[1], isA<AiRenderReasoningGroup>());
  });
}
