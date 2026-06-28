import 'package:teampilot/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips team config json with members', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      extraArgs: '--permission-mode acceptEdits',
      loop: true,
      members: [
        TeamMemberConfig(
          id: 'member-1',
          name: 'planner',
          provider: 'anthropic',
          model: 'sonnet',
          agent: 'builder',
          extraArgs: '--continue',
          dangerouslySkipPermissions: true,
        ),
        TeamMemberConfig(
          id: 'member-2',
          name: 'reviewer',
          provider: 'openai',
          model: 'gpt-5.4',
        ),
      ],
    );

    final decoded = TeamProfile.fromJson(team.toJson());

    expect(decoded, team);
  });

  test('round trips mcpServerIds', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      mcpServerIds: ['fetch', 'github'],
    );
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.mcpServerIds, ['fetch', 'github']);
  });

  test('round trips modelsByTool and defaults to empty for legacy json', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      modelsByTool: {'claude': 'sonnet'},
    );

    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.modelsByTool, team.modelsByTool);

    final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
    expect(legacy.modelsByTool, isEmpty);
  });

  test(
    'round trips providerIdsByTool and defaults to empty for legacy json',
    () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'hello',
        providerIdsByTool: {
          'flashskyai': 'deepseek',
          'codex': 'openai-official',
        },
      );

      final decoded = TeamProfile.fromJson(team.toJson());
      expect(decoded.providerIdsByTool, team.providerIdsByTool);

      final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
      expect(legacy.providerIdsByTool, isEmpty);
    },
  );

  test('decodeLoop accepts bool and string', () {
    expect(TeamProfile.decodeLoop(null), isNull);
    expect(TeamProfile.decodeLoop(true), isTrue);
    expect(TeamProfile.decodeLoop(false), isFalse);
    expect(TeamProfile.decodeLoop('true'), isTrue);
    expect(TeamProfile.decodeLoop('FALSE'), isFalse);
    expect(TeamProfile.decodeLoop('maybe'), isNull);
  });

  test('decodeDangerouslySkipPermissions accepts bool and string', () {
    expect(TeamMemberConfig.decodeDangerouslySkipPermissions(null), isTrue);
    expect(TeamMemberConfig.decodeDangerouslySkipPermissions(true), isTrue);
    expect(TeamMemberConfig.decodeDangerouslySkipPermissions('TRUE'), isTrue);
    expect(TeamMemberConfig.decodeDangerouslySkipPermissions(false), isFalse);
  });

  test('decodeForceTeamLeadDelegateMode accepts bool and string', () {
    expect(TeamProfile.decodeForceTeamLeadDelegateMode(null), isTrue);
    expect(TeamProfile.decodeForceTeamLeadDelegateMode(true), isTrue);
    expect(TeamProfile.decodeForceTeamLeadDelegateMode('true'), isTrue);
    expect(TeamProfile.decodeForceTeamLeadDelegateMode(false), isFalse);
  });

  test('toJson omits forceTeamLeadDelegateMode when false', () {
    const team = TeamProfile(id: 't', name: 'n');
    expect(team.toJson()['forceTeamLeadDelegateMode'], isTrue);
    const off = TeamProfile(
      id: 't',
      name: 'n',
      forceTeamLeadDelegateMode: false,
    );
    expect(off.toJson().containsKey('forceTeamLeadDelegateMode'), isFalse);
  });

  test('forceWaitBeforeStop defaults true and round-trips when false', () {
    const team = TeamProfile(id: 't', name: 'n');
    expect(team.forceWaitBeforeStop, isTrue);
    // Default true is omitted from JSON; only persisted when turned off.
    expect(team.toJson().containsKey('forceWaitBeforeStop'), isFalse);
    expect(TeamProfile.fromJson(team.toJson()).forceWaitBeforeStop, isTrue);

    const off = TeamProfile(id: 't', name: 'n', forceWaitBeforeStop: false);
    expect(off.toJson()['forceWaitBeforeStop'], isFalse);
    expect(TeamProfile.fromJson(off.toJson()).forceWaitBeforeStop, isFalse);
  });

  test('toJson omits loop when null', () {
    const team = TeamProfile(id: 't', name: 'n');
    expect(team.toJson().containsKey('loop'), isFalse);
    const withLoop = TeamProfile(id: 't', name: 'n', loop: false);
    expect(withLoop.toJson()['loop'], isFalse);
  });

  test('does not migrate legacy team model fields', () {
    final team = TeamProfile.fromJson({
      'id': 'team-1',
      'name': 'legacy',
      'workingDirectory': '/tmp/legacy',
      'provider': 'anthropic',
      'model': 'sonnet',
      'agent': 'builder',
    });

    expect(team.members, isEmpty);
  });

  test('is invalid when name is blank', () {
    expect(const TeamProfile(id: 'team-1', name: '').isValid, isFalse);
    expect(const TeamProfile(id: 'team-1', name: 'hello').isValid, isTrue);
  });

  test('member is invalid when name is blank', () {
    expect(const TeamMemberConfig(id: 'member-1', name: ' ').isValid, isFalse);
    expect(
      const TeamMemberConfig(id: 'member-1', name: 'planner').isValid,
      isTrue,
    );
  });

  test('copyWith updates team and member fields', () {
    const member = TeamMemberConfig(id: 'member-1', name: 'planner');
    final changedMember = member.copyWith(provider: 'openai', model: 'gpt-5.4');

    const team = TeamProfile(id: 'team-1', name: 'hello');
    final changedTeam = team.copyWith(
      extraArgs: '--continue',
      members: [changedMember],
    );

    expect(changedMember.provider, 'openai');
    expect(changedMember.model, 'gpt-5.4');
    expect(changedTeam.extraArgs, '--continue');
    expect(changedTeam.members.single, changedMember);
  });

  test('round trips cli and defaults to claude for legacy json', () {
    const team = TeamProfile(id: 'team-1', name: 'hello', cli: CliTool.codex);
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.cli, CliTool.codex);

    final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
    expect(legacy.cli, CliTool.claude);
    expect(legacy.toJson()['cli'], 'claude');
  });

  test('opencode round-trips through json', () {
    expect(CliTool.decode('opencode'), CliTool.opencode);

    const team = TeamProfile(id: 't', name: 'T', cli: CliTool.opencode);
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.cli, CliTool.opencode);
    expect(team.toJson()['cli'], 'opencode');
  });

  test('round trips skillIds', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      skillIds: ['local:foo', 'anthropics/skills:bar'],
    );
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.skillIds, team.skillIds);
    expect(team.toJson()['skillIds'], team.skillIds);
  });

  test('decodeSkillIds ignores invalid entries', () {
    expect(TeamProfile.decodeSkillIds(['a', '', null, '  ', 'b']), ['a', 'b']);
    expect(TeamProfile.decodeSkillIds(null), isEmpty);
  });

  test('toJson omits skillIds when empty', () {
    const team = TeamProfile(id: 't', name: 'n');
    expect(team.toJson().containsKey('skillIds'), isFalse);
  });

  test('copyWith updateLoop clears or sets loop', () {
    const team = TeamProfile(id: 't', name: 'n', loop: true);
    expect(team.copyWith(name: 'x').loop, isTrue);
    expect(team.copyWith(loop: null, updateLoop: true).loop, isNull);
    expect(team.copyWith(loop: false, updateLoop: true).loop, isFalse);
  });

  test('TeamProfile round-trips pluginIds', () {
    const team = TeamProfile(
      id: 't',
      name: 'T',
      pluginIds: ['acme/market/p1', 'beta/market/p2'],
    );
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.pluginIds, ['acme/market/p1', 'beta/market/p2']);
    expect(decoded, team);
  });

  test('TeamProfile omits pluginIds when empty', () {
    const team = TeamProfile(id: 't', name: 'T');
    expect(team.toJson().containsKey('pluginIds'), isFalse);
  });

  test('teamMode defaults to native, round-trips, omits native in json', () {
    expect(const TeamProfile(id: 't', name: 'T').teamMode, TeamMode.native);

    const mixed = TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed);
    final decoded = TeamProfile.fromJson(mixed.toJson());
    expect(decoded.teamMode, TeamMode.mixed);
    expect(mixed.toJson()['teamMode'], 'mixed');

    const native = TeamProfile(id: 't', name: 'T', teamMode: TeamMode.native);
    expect(native.toJson().containsKey('teamMode'), isFalse);

    final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
    expect(legacy.teamMode, TeamMode.native);
  });

  test('member.cli is honored only in mixed mode', () {
    const nativeTeam = TeamProfile(id: 't', name: 'T', cli: CliTool.claude);
    const mixedTeam = TeamProfile(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const m = TeamMemberConfig(id: 'm', name: 'a', cli: CliTool.flashskyai);
    const inherit = TeamMemberConfig(id: 'm2', name: 'b');

    expect(
      m.cliWithin(nativeTeam),
      CliTool.claude,
    ); // native ignores member.cli
    expect(m.cliWithin(mixedTeam), CliTool.flashskyai); // mixed honors it
    expect(inherit.cliWithin(mixedTeam), CliTool.claude); // mixed fallback

    expect(TeamMemberConfig.fromJson(m.toJson()).cli, CliTool.flashskyai);
    expect(m.toJson()['cli'], 'flashskyai');
    expect(inherit.toJson().containsKey('cli'), isFalse);
  });
}
