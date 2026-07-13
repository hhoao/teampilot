import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups consecutive tools and reasoning', () {
    final nodes = groupMessageParts([
      const AiTextPart(text: 'hi'),
      const AiToolCallPart(toolCallId: '1', toolName: 'Read'),
      const AiToolCallPart(toolCallId: '2', toolName: 'Grep'),
      const AiTextPart(text: 'done'),
      const AiReasoningPart(text: 'a'),
      const AiReasoningPart(text: 'b'),
    ]);

    expect(nodes, hasLength(4));
    expect(nodes[0], isA<AiRenderPart>());
    expect(nodes[1], isA<AiRenderToolGroup>());
    expect((nodes[1] as AiRenderToolGroup).tools, hasLength(2));
    expect(nodes[2], isA<AiRenderPart>());
    expect(nodes[3], isA<AiRenderReasoningGroup>());
    expect((nodes[3] as AiRenderReasoningGroup).parts, hasLength(2));
  });

  test('single tool stays a part node', () {
    final nodes = groupMessageParts([
      const AiToolCallPart(toolCallId: '1', toolName: 'Shell'),
    ]);
    expect(nodes.single, isA<AiRenderPart>());
  });
}
