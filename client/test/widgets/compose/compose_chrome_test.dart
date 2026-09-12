import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';

void main() {
  test('ComposeChrome exhaustiveness covers unbound and bound', () {
    final ComposeChrome unbound = UnboundComposeChrome(
      conversationModeLabel: 'Simple',
      autoChipLabel: 'Preset',
      conversationModeSpecs: const [],
      autoChipSpecs: const [],
      onConversationModeSelected: _noop,
      onAutoChipSelected: _noop,
    );
    const ComposeChrome bound = BoundComposeChrome(identityLabel: 'Team');
    expect(unbound, isA<UnboundComposeChrome>());
    expect(bound, isA<BoundComposeChrome>());
  });
}

void _noop(Object? _) {}
