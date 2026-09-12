import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
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

  test('built-in CLI capabilities suppress a proposed permission control', () {
    final registry = CliToolRegistry.builtIn();
    const control = ComposePermissionControl(
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      defaultLabel: 'Default',
      fullAccessLabel: 'Full',
      onSelected: _noopPolicy,
    );
    for (final definition in registry.launchable) {
      expect(
        permissionControlForCli(registry, definition.id, control),
        isNull,
        reason: definition.id.value,
      );
    }
  });
}

void _noop(Object? _) {}
void _noopPolicy(LaunchSecurityPolicy _) {}
