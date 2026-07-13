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
    expect(text, 'hello\n\nUsed tool: Read (incomplete)\n\nthink');
  });

  test('markdownForExport wraps reasoning and tools', () {
    final md = markdownForExport(
      const AiMessage(
        id: '1',
        role: AiRole.assistant,
        parts: [
          AiTextPart(text: 'hello'),
          AiReasoningPart(text: 'think **hard**'),
          AiToolCallPart(
            toolCallId: 't',
            toolName: 'Read',
            args: {'path': '/tmp/a'},
            result: 'ok',
          ),
        ],
      ),
    );
    expect(md, contains('hello'));
    expect(md, contains('<details>'));
    expect(md, contains('think **hard**'));
    expect(md, contains('**Used tool: Read**'));
    expect(md, contains('"path"'));
    expect(md, contains('/tmp/a'));
    expect(md, contains('ok'));
  });
}
