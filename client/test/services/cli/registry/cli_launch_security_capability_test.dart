import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_launch_security_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('PTY security stays full-access-only for every CLI', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      final capability = registry.launchSecurityFor(cli);
      expect(capability.supportsUserConfiguration, isFalse);
      expect(capability.supportedPolicies, {LaunchSecurityPolicy.fullAccess});
      expect(capability.policiesFor(acp: false), {
        LaunchSecurityPolicy.fullAccess,
      });
      expect(capability.supportsUserConfigurationFor(acp: false), isFalse);
    }
  });

  test('ACP-capable CLIs expose ask+fullAccess; others stay fullAccess', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      final capability = registry.launchSecurityFor(cli);
      final hasAcp = registry.capability<AcpCapability>(cli) != null;
      if (hasAcp) {
        expect(capability, isA<AcpAskFullAccessCliLaunchSecurityCapability>());
        expect(capability.policiesFor(acp: true), {
          LaunchSecurityPolicy.ask,
          LaunchSecurityPolicy.fullAccess,
        });
        expect(capability.supportsUserConfigurationFor(acp: true), isTrue);
      } else {
        expect(capability.policiesFor(acp: true), {
          LaunchSecurityPolicy.fullAccess,
        });
        expect(capability.supportsUserConfigurationFor(acp: true), isFalse);
      }
    }
  });
}
