import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/post_frame_test_harness.dart';

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

  test(
    'cursor provisioning is not ready without provider or global login',
    () async {
      setUpTestAppStorage();
      addTearDown(tearDownTestAppStorage);
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
      expect(result.credentialsReady, isFalse);
      expect(result.warnings, ['cursor_credentials_missing']);
      expect(result.extraEnvironment, isEmpty);
    },
  );
}
