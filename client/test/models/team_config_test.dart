import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips team config json with roster', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      extraArgs: '--permission-mode acceptEdits',
      loop: true,
      roster: [
        TeamRosterSlot(
          id: 'member-1',
          expertKey: 'teampilot/builtin/developer',
          overrides: TeamRosterSlotOverrides(
            provider: 'anthropic',
            model: 'sonnet',
            extraArgs: '--continue',
          ),
        ),
        TeamRosterSlot(
          id: 'member-2',
          expertKey: 'teampilot/builtin/reviewer',
          overrides: TeamRosterSlotOverrides(
            provider: 'openai',
            model: 'gpt-5.4',
          ),
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

  test('member security policy serializes under its normalized object', () {
    const member = TeamMemberConfig(
      id: 'builder-0',
      name: 'Builder',
      launchSecurityPolicy: LaunchSecurityPolicy(
        approval: LaunchApprovalPolicy.ask,
        sandbox: LaunchSandboxPolicy.workspaceWrite,
        hookTrust: LaunchHookTrustPolicy.trustedOnly,
      ),
    );
    final json = member.toJson();
    expect(json['launchSecurityPolicy'], isA<Map<String, Object?>>());
    expect(json.containsKey('dangerouslySkipPermissions'), isFalse);
    expect(
      TeamMemberConfig.fromJson({
        ...json,
        'dangerouslySkipPermissions': true,
      }).launchSecurityPolicy,
      equals(member.launchSecurityPolicy),
    );
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

  test('forceWaitBeforeStop defaults false and round-trips when true', () {
    const team = TeamProfile(id: 't', name: 'n');
    expect(team.forceWaitBeforeStop, isFalse);
    // Default false is omitted from JSON; only persisted when turned on.
    expect(team.toJson().containsKey('forceWaitBeforeStop'), isFalse);
    expect(TeamProfile.fromJson(team.toJson()).forceWaitBeforeStop, isFalse);

    const on = TeamProfile(id: 't', name: 'n', forceWaitBeforeStop: true);
    expect(on.toJson()['forceWaitBeforeStop'], isTrue);
    expect(TeamProfile.fromJson(on.toJson()).forceWaitBeforeStop, isTrue);
  });

  test(
    'effectiveForceWaitBeforeStop prefers member, then CLI veto, then team',
    () {
      const memberOn = TeamMemberConfig(
        id: 'm',
        name: 'm',
        forceWaitBeforeStop: true,
      );
      const memberUnset = TeamMemberConfig(id: 'm', name: 'm');
      const teamOff = TeamProfile(id: 't', name: 'n');
      const teamOn = TeamProfile(id: 't', name: 'n', forceWaitBeforeStop: true);

      expect(
        memberOn.effectiveForceWaitBeforeStop(teamOff, cliDefault: false),
        isTrue,
      );
      expect(
        memberUnset.effectiveForceWaitBeforeStop(teamOn, cliDefault: false),
        isFalse,
        reason: 'doorbell CLI cannot park even when the team switch is on',
      );
      expect(
        memberUnset.effectiveForceWaitBeforeStop(teamOff, cliDefault: true),
        isFalse,
      );
      expect(
        memberUnset.effectiveForceWaitBeforeStop(teamOn, cliDefault: true),
        isTrue,
      );
    },
  );

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

    expect(team.roster, isEmpty);
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

  test('copyWith updates team roster and runtime members', () {
    const slot = TeamRosterSlot(
      id: 'member-1',
      expertKey: 'teampilot/builtin/developer',
    );
    const member = TeamMemberConfig(id: 'member-1', name: 'planner');
    const team = TeamProfile(id: 'team-1', name: 'hello');
    final changedTeam = team.copyWith(
      extraArgs: '--continue',
      roster: [slot],
      members: [member],
    );

    expect(changedTeam.extraArgs, '--continue');
    expect(changedTeam.roster.single, slot);
    expect(changedTeam.members.single, member);
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

  test('round trips hubSourceKey and defaults missing to null', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'hello',
      hubSourceKey: 'owner/repo/slug',
    );
    final decoded = TeamProfile.fromJson(team.toJson());
    expect(decoded.hubSourceKey, 'owner/repo/slug');
    expect(decoded, team);

    final legacy = TeamProfile.fromJson({'id': 't', 'name': 'T'});
    expect(legacy.hubSourceKey, isNull);
  });

  test('member.cli is stored for mixed custom overrides', () {
    const m = TeamMemberConfig(id: 'm', name: 'a', cli: CliTool.flashskyai);
    const inherit = TeamMemberConfig(
      id: 'm2',
      name: 'b',
      activePresetId: TeamProfile.inheritPresetId,
    );

    expect(m.cli, CliTool.flashskyai);
    expect(inherit.cli, isNull);
    expect(inherit.inheritsTeamPreset, isTrue);

    expect(TeamMemberConfig.fromJson(m.toJson()).cli, CliTool.flashskyai);
    expect(m.toJson()['cli'], 'flashskyai');
    expect(inherit.toJson().containsKey('cli'), isFalse);
  });
}
