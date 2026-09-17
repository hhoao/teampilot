import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/workspace_base_info_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  test('claude headless workspace args come from registry capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final capability = registry.capability<WorkspaceBaseInfoCapability>(
      CliTool.claude,
    )!;
    final interactive = CliLaunchContext(
      team: TeamProfile(id: 't', name: 'T'),
      member: TeamMemberConfig(id: 'm', name: 'M'),
      additionalDirectories: const ['/repo/a'],
    );
    expect(
      capability.buildLaunchArgs(interactive).expand((c) => c.args).toList(),
      ['--add-dir', '/repo/a'],
    );
  });
}
