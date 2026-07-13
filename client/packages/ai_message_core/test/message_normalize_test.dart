import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalize merges string content into AiTextPart', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: 'hello',
      ),
    ]);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.user);
    expect(messages.single.parts, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, 'hello');
    expect(messages.single.status, AiMessageStatus.complete);
  });

  test('normalize keeps tool-call parts on assistant messages', () {
    final messages = normalizeThreadMessages([
      ThreadMessageLike(
        id: 'a1',
        role: AiRole.assistant,
        content: [
          const AiTextPart(text: 'Using tool'),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            args: {'cmd': 'ls'},
          ),
        ],
      ),
    ]);
    expect(messages.single.parts, hasLength(2));
    final tool = messages.single.parts[1] as AiToolCallPart;
    expect(tool.toolName, 'Bash');
    expect(tool.result, isNull);
  });
}
