import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('AiToolCallPart.category defaults to other', () {
    const part = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    expect(part.category, AiToolCallCategory.other);
  });

  test('copyWith sets and preserves category', () {
    const part = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final edited = part.copyWith(category: AiToolCallCategory.command);
    expect(edited.category, AiToolCallCategory.command);
    expect(edited.toolName, 'bash');
    expect(part.copyWith(toolName: 'Read').category, AiToolCallCategory.other);
  });

  test('enum has all 12 categories', () {
    expect(AiToolCallCategory.values, hasLength(12));
    expect(AiToolCallCategory.values, containsAll([
      AiToolCallCategory.read,
      AiToolCallCategory.write,
      AiToolCallCategory.edit,
      AiToolCallCategory.command,
      AiToolCallCategory.search,
      AiToolCallCategory.browser,
      AiToolCallCategory.subagent,
      AiToolCallCategory.askUser,
      AiToolCallCategory.plan,
      AiToolCallCategory.task,
      AiToolCallCategory.mcp,
      AiToolCallCategory.other,
    ]));
  });
}
