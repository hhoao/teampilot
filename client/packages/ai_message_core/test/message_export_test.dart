import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('plainTextForCopy joins text and tool labels', () {
    final text = plainTextForCopy(
      const AiMessage(
        id: '1',
        role: AiRole.assistant,
        parts: [
          AiTextPart(text: 'hello'),
          AiToolCallPart(toolCallId: 't', toolName: 'Read'),
          AiReasoningPart(text: 'think'),
        ],
      ),
    );
    expect(text, 'hello\n\nUsed tool: Read\n\nthink');
  });
}
