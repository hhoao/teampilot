import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_effort_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/provider/claude/claude_effort_capability.dart';
import 'package:teampilot/services/provider/codex/codex_effort_capability.dart';

void main() {
  test('built-in claude and codex register CliEffortCapability', () {
    final registry = CliToolRegistry.builtIn();
    expect(registry.capability<CliEffortCapability>(CliTool.claude), isNotNull);
    expect(registry.capability<CliEffortCapability>(CliTool.codex), isNotNull);
    expect(registry.capability<CliEffortCapability>(CliTool.opencode), isNull);
  });

  test('resolveLaunchEffort prefers member over team', () {
    const capability = ClaudeEffortCapability();
    final team = TeamConfig(
      id: 't1',
      name: 'Team',
      cli: CliTool.claude,
      members: const [],
      cliEffortLevels: const {'claude': 'low'},
    );
    final member = TeamMemberConfig(
      id: 'm1',
      name: 'M',
      effort: 'max',
    );
    expect(
      resolveLaunchEffort(
        capability: capability,
        cli: CliTool.claude,
        context: EffortResolveContext(
          team: team,
          member: member,
          model: 'sonnet',
        ),
      ),
      'max',
    );
  });

  test('resolveLaunchEffort falls back to team then default', () {
    const capability = CodexEffortCapability();
    final team = TeamConfig(
      id: 't1',
      name: 'Team',
      cli: CliTool.codex,
      members: const [],
      cliEffortLevels: const {'codex': 'minimal'},
    );
    expect(
      resolveLaunchEffort(
        capability: capability,
        cli: CliTool.codex,
        context: EffortResolveContext(team: team, model: 'gpt-5.4'),
      ),
      'minimal',
    );
    expect(
      resolveLaunchEffort(
        capability: capability,
        cli: CliTool.codex,
        context: const EffortResolveContext(model: 'gpt-5.4'),
      ),
      'high',
    );
  });
}
