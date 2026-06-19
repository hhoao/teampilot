import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_effort_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/provider/claude/claude_effort_capability.dart';
import 'package:teampilot/services/provider/codex/codex_effort_capability.dart';

void main() {
  test('resolveLaunchEffort prefers member over team', () {
    const capability = ClaudeEffortCapability();
    final team = TeamProfile(
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
    final team = TeamProfile(
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

  // Guards the removal of the legacy `claudeEffortLevel` model field: claude is
  // now map-only like every other CLI, and its 'high' default comes solely from
  // ClaudeEffortCapability — never the model.
  test('claude effort is map-only; unset team is "" but launch defaults high', () {
    const capability = ClaudeEffortCapability();
    final team = TeamProfile(
      id: 't1',
      name: 'Team',
      cli: CliTool.claude,
      members: const [],
    );
    // No model-level claude default: unset reads empty, like codex/cursor/etc.
    expect(team.effortForCli(CliTool.claude), '');
    // …yet the launch resolver still supplies claude's 'high'.
    expect(
      resolveLaunchEffort(
        capability: capability,
        cli: CliTool.claude,
        context: const EffortResolveContext(model: 'sonnet'),
      ),
      'high',
    );
    // Clearing an entry removes it (no implicit 'high' write-back).
    final set = team.withEffortForCli(CliTool.claude, 'low');
    expect(set.effortForCli(CliTool.claude), 'low');
    expect(
      set.withEffortForCli(CliTool.claude, '').effortForCli(CliTool.claude),
      '',
    );
  });
}
