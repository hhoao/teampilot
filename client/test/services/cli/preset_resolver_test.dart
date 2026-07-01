import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/preset_resolver.dart';

void main() {
  const claudePreset = CliPreset(
    id: 'preset-claude',
    name: 'Claude Default',
    cli: CliTool.claude,
    provider: 'deepseek',
    model: 'deepseek-v4-pro',
    effort: 'high',
    createdAt: 0,
    updatedAt: 0,
  );

  const cursorPreset = CliPreset(
    id: 'preset-cursor',
    name: 'Cursor',
    cli: CliTool.cursor,
    provider: 'cursor-account',
    model: 'composer-2.5',
    createdAt: 0,
    updatedAt: 0,
  );

  test('resolveTeamLaunchBundle reads team custom defaults', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'deepseek'},
      modelsByTool: {'claude': 'deepseek-v4-pro'},
      cliEffortLevels: {'claude': 'medium'},
    );

    final bundle = resolveTeamLaunchBundle(
      team: team,
      globalPresets: const [],
    );

    expect(bundle.cli, CliTool.claude);
    expect(bundle.provider, 'deepseek');
    expect(bundle.model, 'deepseek-v4-pro');
    expect(bundle.effort, 'medium');
  });

  test('resolveTeamLaunchBundle reads active team preset', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      cli: CliTool.claude,
      activePresetId: 'preset-cursor',
    );

    final bundle = resolveTeamLaunchBundle(
      team: team,
      globalPresets: const [cursorPreset],
    );

    expect(bundle.cli, CliTool.cursor);
    expect(bundle.provider, 'cursor-account');
    expect(bundle.model, 'composer-2.5');
    expect(bundle.sourcePreset, cursorPreset);
  });

  test('inherit member uses full team bundle including preset CLI', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-cursor',
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          activePresetId: TeamProfile.inheritPresetId,
        ),
      ],
    );

    final resolved = resolveMemberLaunch(
      team: team,
      member: team.members.single,
      globalPresets: const [cursorPreset],
    );

    expect(resolved.mode, MemberLaunchMode.inheritTeam);
    expect(resolved.cli, CliTool.cursor);
    expect(resolved.provider, 'cursor-account');
    expect(resolved.model, 'composer-2.5');
  });

  test('custom member does not inherit team provider or model', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'deepseek'},
      modelsByTool: {'claude': 'deepseek-v4-pro'},
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          cli: CliTool.codex,
          provider: 'codex-p',
          model: 'codex-m',
        ),
      ],
    );

    final resolved = resolveMemberLaunch(
      team: team,
      member: team.members.single,
      globalPresets: const [],
    );

    expect(resolved.mode, MemberLaunchMode.custom);
    expect(resolved.cli, CliTool.codex);
    expect(resolved.provider, 'codex-p');
    expect(resolved.model, 'codex-m');
  });

  test('member explicit preset overrides team bundle', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-cursor',
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          activePresetId: 'preset-claude',
        ),
      ],
    );

    final resolved = resolveMemberLaunch(
      team: team,
      member: team.members.single,
      globalPresets: const [claudePreset, cursorPreset],
    );

    expect(resolved.mode, MemberLaunchMode.memberPreset);
    expect(resolved.cli, CliTool.claude);
    expect(resolved.provider, 'deepseek');
    expect(resolved.model, 'deepseek-v4-pro');
  });

  test('memberForLaunch copies resolved CLI for mixed teams', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-cursor',
      members: [
        TeamMemberConfig(
          id: 'alice',
          name: 'Alice',
          activePresetId: TeamProfile.inheritPresetId,
        ),
      ],
    );

    final staged = memberForLaunch(
      team: team,
      member: team.members.single,
      globalPresets: const [cursorPreset],
    );

    expect(staged.cli, CliTool.cursor);
    expect(staged.provider, 'cursor-account');
    expect(staged.model, 'composer-2.5');
  });

  test('presetsForCli filters by catalog CLI', () {
    final items = presetsForCli(
      const [claudePreset, cursorPreset],
      CliTool.codex,
    );
    expect(items, isEmpty);

    final claudeItems = presetsForCli(
      const [claudePreset, cursorPreset],
      CliTool.claude,
    );
    expect(claudeItems, const [claudePreset]);
  });
}
