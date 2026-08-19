import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/teambus_prompt.dart';

void main() {
  test('formats a teambus element with type first', () {
    expect(
      TeamBusPrompt.format(type: 'mail', content: 'Read the inbox.'),
      '<teambus type="mail">Read the inbox.</teambus>',
    );
  });

  test('preserves attribute order and escapes XML values', () {
    expect(
      TeamBusPrompt.format(
        type: 'message',
        attributes: {'message_id': 'm&1', 'from': 'a"b'},
        content: 'A & <B>',
      ),
      '<teambus type="message" message_id="m&amp;1" from="a&quot;b">'
      'A &amp; &lt;B&gt;</teambus>',
    );
  });
}
