import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';

void main() {
  test('opencode tool is registered and launch-supported', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    final tool = registry.tryGet('opencode');
    expect(tool, isNotNull);
    expect(tool!.isLaunchSupported, isTrue);
    expect(tool.providerCatalogCli, isNull);
    expect(registry.launchable.map((d) => d.id), contains('opencode'));
  });

  test('LaunchCommandBuilder builds opencode args end-to-end', () {
    const team = TeamConfig(id: 't', name: 'agent', cli: TeamCli.opencode);
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
