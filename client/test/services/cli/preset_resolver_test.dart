import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/preset_resolver.dart';

void main() {
  const preset = CliPreset(
    id: 'preset-1',
    name: 'Claude Default',
    cli: CliTool.claude,
    provider: 'deepseek',
    model: 'deepseek-v4-pro',
    effort: 'high',
    createdAt: 0,
    updatedAt: 0,
  );

  test('resolveMemberLaunchConfig merges team custom defaults for empty member', () {
    const team = TeamConfig(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'deepseek'},
      modelsByTool: {'claude': 'deepseek-v4-pro'},
      cliEffortLevels: {'claude': 'medium'},
      members: [
        TeamMemberConfig(id: 'alice', name: 'Alice'),
      ],
    );
    const member = TeamMemberConfig(id: 'alice', name: 'Alice');

    final resolved = resolveMemberLaunchConfig(
      team: team,
      member: member,
      globalPresets: const [],
    );

    expect(resolved.provider, 'deepseek');
    expect(resolved.model, 'deepseek-v4-pro');
    expect(resolved.effort, 'medium');
  });

  test('inherits team preset only when CLI matches member effective CLI', () {
    const team = TeamConfig(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-1',
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          cli: CliTool.codex,
          activePresetId: TeamConfig.inheritPresetId,
        ),
      ],
    );
    const member = TeamMemberConfig(
      id: 'alice',
      name: 'Alice',
      cli: CliTool.codex,
      activePresetId: TeamConfig.inheritPresetId,
    );

    final resolved = resolveMemberLaunchConfig(
      team: team,
      member: member,
      globalPresets: const [preset],
    );

    expect(resolved.provider, isEmpty);
    expect(resolved.model, isEmpty);
  });

  test('inherits team preset when CLI matches', () {
    const team = TeamConfig(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-1',
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          activePresetId: TeamConfig.inheritPresetId,
        ),
      ],
    );

    final resolved = resolveMemberLaunchConfig(
      team: team,
      member: team.members.single,
      globalPresets: const [preset],
    );

    expect(resolved.provider, 'deepseek');
    expect(resolved.model, 'deepseek-v4-pro');
    expect(resolved.sourcePreset, preset);
  });
}
