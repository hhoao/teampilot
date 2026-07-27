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
}
