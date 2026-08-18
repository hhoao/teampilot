import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';

void main() {
  test('ComposeChrome exhaustiveness covers unbound and bound', () {
    final ComposeChrome unbound = UnboundComposeChrome(
      conversationModeLabel: 'Simple',
      autoChipLabel: 'Preset',
      launchSecurityPolicy: const LaunchSecurityPolicy(),
      defaultPermissionsLabel: 'Default',
      fullAccessPermissionsLabel: 'Full',
      conversationModeSpecs: const [],
      autoChipSpecs: const [],
      onConversationModeSelected: _noop,
      onAutoChipSelected: _noop,
      onPermissionSelected: _noopPolicy,
    );
    const ComposeChrome bound = BoundComposeChrome(identityLabel: 'Team');
    expect(unbound, isA<UnboundComposeChrome>());
    expect(bound, isA<BoundComposeChrome>());
  });
}

void _noop(Object? _) {}
void _noopPolicy(LaunchSecurityPolicy _) {}
