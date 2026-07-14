import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/installer_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('onboarding CLI step covers every launchable tool', () {
    final registry = CliToolRegistry.builtIn();
    final launchable = registry.launchable.map((d) => d.id).toSet();

    expect(
      launchable,
      containsAll({
        CliTool.claude,
        CliTool.codex,
        CliTool.opencode,
        CliTool.cursor,
        CliTool.flashskyai,
      }),
    );

    expect(
      registry.capability<InstallerCapability>(CliTool.claude)?.supportsInstaller,
      isTrue,
    );
    expect(
      registry
          .capability<InstallerCapability>(CliTool.flashskyai)
          ?.supportsInstaller,
      isFalse,
    );
  });
}
