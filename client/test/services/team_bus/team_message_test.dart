import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

void main() {
  test('copyWith overrides only given fields', () {
    const m = TeamMessage(id: '1', from: 'a', to: 'b', content: 'hi');
    final forwarded = m.copyWith(to: 'c', hop: m.hop + 1);

    expect(forwarded.id, '1');
    expect(forwarded.from, 'a');
    expect(forwarded.to, 'c');
    expect(forwarded.content, 'hi');
    expect(forwarded.hop, 1);
    expect(m.hop, 0); // original unchanged
  });
}
