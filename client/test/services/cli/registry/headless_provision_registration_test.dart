import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_provision_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('CLIs that need credential/config provisioning expose a capability', () {
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.opencode,
      CliTool.flashskyai,
    ]) {
      expect(
        registry.capability<HeadlessProvisionCapability>(cli),
        isNotNull,
        reason: '${cli.value} should expose a HeadlessProvisionCapability',
      );
    }
  });

  test('cursor has no provisioning capability (falls back to default)', () {
    expect(
      registry.capability<HeadlessProvisionCapability>(CliTool.cursor),
      isNull,
    );
  });
}
