import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('messageContentIdentity changes with deliveryChannel', () {
    const base = AiMessage(
      id: 'm-1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final mailbox = base.copyWith(deliveryChannel: 'mailbox');

    expect(
      messageContentIdentity(base),
      isNot(equals(messageContentIdentity(mailbox))),
    );
  });

  test('category is excluded from content identity', () {
    const base = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final other = base.copyWith(category: AiToolCallCategory.command);
    const m1 = AiMessage(id: 'm', role: AiRole.assistant, parts: [base]);
    final m2 = AiMessage(id: 'm', role: AiRole.assistant, parts: [other]);
    expect(messageContentIdentity(m1), messageContentIdentity(m2));
  });
}
