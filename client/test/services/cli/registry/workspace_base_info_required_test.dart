import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/workspace_base_info.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  test('every built-in CLI registers WorkspaceBaseInfoCapability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    for (final cli in CliTool.values) {
      expect(
        registry.capability<WorkspaceBaseInfoCapability>(cli),
        isNotNull,
        reason: cli.value,
      );
    }
  });

  test('OpenCode workspace base info emits no argv', () {
    const capability = OpencodeWorkspaceBaseInfo();
    final context = CliLaunchContext(
      team: TeamProfile(id: 'team', name: 'Team'),
      member: TeamMemberConfig(id: 'member', name: 'Member'),
      workingDirectory: '/repo',
      additionalDirectories: const ['/repo/a'],
    );
    expect(capability.buildLaunchArgs(context), isEmpty);
  });
}
