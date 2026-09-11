import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_launch_security_capability.dart';

void main() {
  test('all built-in CLIs expose a full-access-only security capability', () {
    final registry = CliToolRegistry.builtIn();

    for (final cli in CliTool.values) {
      final capability = registry.launchSecurityFor(cli);
      expect(capability, isA<CliLaunchSecurityCapability>());
      expect(capability.supportsUserConfiguration, isFalse);
      expect(capability.supportedPolicies, {LaunchSecurityPolicy.fullAccess});
    }
  });
}
