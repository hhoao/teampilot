import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('AiMessage carries deliveryChannel through copyWith', () {
    const msg = AiMessage(
      id: 'mailbox:m1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
      deliveryChannel: 'mailbox',
    );
    expect(msg.deliveryChannel, 'mailbox');
    expect(msg.copyWith(deliveryChannel: null).deliveryChannel, isNull);
    expect(
      msg.copyWith(clearDeliveryChannel: true).deliveryChannel,
      isNull,
    );
  });
}
