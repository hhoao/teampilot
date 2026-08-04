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

    final bundle = resolveTeamLaunchBundle(team: team, globalPresets: const []);

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

  test(
    'resolveTeamLaunchBundle preset shape with missing preset returns unconfigured',
    () {
      const team = TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.claude,
        activePresetId: 'missing-preset',
        providerIdsByTool: {'claude': 'deepseek'},
        modelsByTool: {'claude': 'deepseek-v4-pro'},
        cliEffortLevels: {'claude': 'medium'},
      );

      final bundle = resolveTeamLaunchBundle(team: team, globalPresets: const []);

      expect(bundle.cli, CliTool.claude);
      expect(bundle.provider, isEmpty);
      expect(bundle.model, isEmpty);
      expect(bundle.effort, isEmpty);
      expect(bundle.sourcePreset, isNull);
      expect(bundle.isConfigured, isFalse);
    },
  );

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

  test('memberForLaunch keeps member preset provider under team preset', () {
    const teamPreset = CliPreset(
      id: 'preset-team',
      name: 'Team Default',
      cli: CliTool.claude,
      provider: 'team-provider',
      model: 'team-model',
      createdAt: 0,
      updatedAt: 0,
    );
    const memberPreset = CliPreset(
      id: 'preset-member',
      name: 'Member Override',
      cli: CliTool.claude,
      provider: 'member-provider',
      model: 'member-model',
      createdAt: 0,
      updatedAt: 0,
    );
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      teamMode: TeamMode.native,
      cli: CliTool.claude,
      activePresetId: 'preset-team',
      members: [
        TeamMemberConfig(
          id: 'inherit',
          name: 'inherit',
          activePresetId: TeamProfile.inheritPresetId,
        ),
        TeamMemberConfig(
          id: 'override',
          name: 'override',
          activePresetId: 'preset-member',
        ),
      ],
    );

    final inheritStaged = memberForLaunch(
      team: team,
      member: team.members.first,
      globalPresets: const [teamPreset, memberPreset],
    );
    final overrideStaged = memberForLaunch(
      team: team,
      member: team.members.last,
      globalPresets: const [teamPreset, memberPreset],
    );

    expect(inheritStaged.provider, 'team-provider');
    expect(inheritStaged.model, 'team-model');
    expect(overrideStaged.provider, 'member-provider');
    expect(overrideStaged.model, 'member-model');
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
    final items = presetsForCli(const [
      claudePreset,
      cursorPreset,
    ], CliTool.codex);
    expect(items, isEmpty);

    final claudeItems = presetsForCli(const [
      claudePreset,
      cursorPreset,
    ], CliTool.claude);
    expect(claudeItems, const [claudePreset]);
  });

  test('teamPresetPickerItems returns all presets for mixed teams', () {
    const team = TeamProfile(
      id: 'team',
      name: 'Mixed',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
    );

    final items = teamPresetPickerItems(
      team: team,
      allPresets: const [cursorPreset, claudePreset],
    );

    expect(items, const [claudePreset, cursorPreset]);
  });

  test('teamPresetPickerItems filters by team cli for native teams', () {
    const team = TeamProfile(id: 'team', name: 'Native', cli: CliTool.claude);

    final items = teamPresetPickerItems(
      team: team,
      allPresets: const [cursorPreset, claudePreset],
    );

    expect(items, const [claudePreset]);
  });

  test('cliForPresetId resolves CLI from global preset id', () {
    expect(
      cliForPresetId('preset-cursor', const [claudePreset, cursorPreset]),
      CliTool.cursor,
    );
    expect(
      cliForPresetId('preset-claude', const [claudePreset, cursorPreset]),
      CliTool.claude,
    );
    expect(cliForPresetId('missing', const [claudePreset]), isNull);
    expect(cliForPresetId('', const [claudePreset]), isNull);
  });
}
