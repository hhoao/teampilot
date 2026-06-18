import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_catalog_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('opencode tool is registered and launch-supported', () {
    final registry = CliToolRegistry.builtIn();

    final tool = registry.tryGet(CliTool.opencode);
    expect(tool, isNotNull);
    expect(tool!.isLaunchSupported, isTrue);
    expect(
      registry.capability<ProviderCatalogCapability>(CliTool.opencode),
      isNotNull,
    );
    expect(
      registry.launchable.map((d) => d.id),
      contains(CliTool.opencode),
    );
  });

  test('LaunchCommandBuilder builds opencode args end-to-end', () {
    const team = TeamProfile(id: 't', name: 'agent', cli: CliTool.opencode);
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      provider: 'anthropic',
      model: 'claude-sonnet-4',
      agent: 'build',
    );

    final args = LaunchCommandBuilder.buildArguments(
      team,
      member,
      workingDirectory: '/work',
    );

    expect(args, [
      '--model',
      'anthropic/claude-sonnet-4',
      '--agent',
      'build',
    ]);
  });
}
