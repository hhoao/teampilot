import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('CLIs with real credential/config provisioning expose a capability', () {
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.opencode,
      CliTool.flashskyai,
    ]) {
      expect(
        registry.capability<HeadlessCapability>(cli),
        isNotNull,
        reason: '${cli.value} should expose a HeadlessCapability',
      );
    }
  });

  test('cursor provisioning returns the default result (no storage writes)',
      () async {
    final cap = registry.capability<HeadlessCapability>(CliTool.cursor);
    expect(cap, isNotNull);
    final result = await cap!.provision(
      const HeadlessProvisionContext(
        provider: null,
        providerId: 'cursor-official',
        model: '',
        effort: '',
        configDir: '/tmp/cfg',
      ),
    );
    expect(result.credentialsReady, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.extraEnvironment, isEmpty);
  });
}
