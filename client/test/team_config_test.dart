import 'package:teampilot/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips team config json with members', () {
    const team = TeamConfig(
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

    final decoded = TeamConfig.fromJson(team.toJson());

    expect(decoded, team);
  });

  test('decodeLoop accepts bool and string', () {
    expect(TeamConfig.decodeLoop(null), isNull);
    expect(TeamConfig.decodeLoop(true), isTrue);
    expect(TeamConfig.decodeLoop(false), isFalse);
    expect(TeamConfig.decodeLoop('true'), isTrue);
    expect(TeamConfig.decodeLoop('FALSE'), isFalse);
    expect(TeamConfig.decodeLoop('maybe'), isNull);
  });

  test('decodeDangerouslySkipPermissions accepts bool and string', () {
    expect(
      TeamMemberConfig.decodeDangerouslySkipPermissions(null),
      isFalse,
    );
    expect(
      TeamMemberConfig.decodeDangerouslySkipPermissions(true),
      isTrue,
    );
    expect(
      TeamMemberConfig.decodeDangerouslySkipPermissions('TRUE'),
      isTrue,
    );
    expect(
      TeamMemberConfig.decodeDangerouslySkipPermissions(false),
      isFalse,
    );
  });

  test('toJson omits loop when null', () {
    const team = TeamConfig(id: 't', name: 'n');
    expect(team.toJson().containsKey('loop'), isFalse);
    const withLoop = TeamConfig(id: 't', name: 'n', loop: false);
    expect(withLoop.toJson()['loop'], isFalse);
  });

  test('does not migrate legacy team model fields', () {
    final team = TeamConfig.fromJson({
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
    expect(
      const TeamConfig(
        id: 'team-1',
        name: '',
      ).isValid,
      isFalse,
    );
    expect(
      const TeamConfig(
        id: 'team-1',
        name: 'hello',
      ).isValid,
      isTrue,
    );
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

    const team = TeamConfig(
      id: 'team-1',
      name: 'hello',
    );
    final changedTeam = team.copyWith(
      extraArgs: '--continue',
      members: [changedMember],
    );

    expect(changedMember.provider, 'openai');
    expect(changedMember.model, 'gpt-5.4');
    expect(changedTeam.extraArgs, '--continue');
    expect(changedTeam.members.single, changedMember);
  });

  test('round trips skillIds', () {
    const team = TeamConfig(
      id: 'team-1',
      name: 'hello',
      skillIds: ['local:foo', 'anthropics/skills:bar'],
    );
    final decoded = TeamConfig.fromJson(team.toJson());
    expect(decoded.skillIds, team.skillIds);
    expect(team.toJson()['skillIds'], team.skillIds);
  });

  test('decodeSkillIds ignores invalid entries', () {
    expect(
      TeamConfig.decodeSkillIds(['a', '', null, '  ', 'b']),
      ['a', 'b'],
    );
    expect(TeamConfig.decodeSkillIds(null), isEmpty);
  });

  test('toJson omits skillIds when empty', () {
    const team = TeamConfig(id: 't', name: 'n');
    expect(team.toJson().containsKey('skillIds'), isFalse);
  });

  test('copyWith updateLoop clears or sets loop', () {
    const team = TeamConfig(id: 't', name: 'n', loop: true);
    expect(team.copyWith(name: 'x').loop, isTrue);
    expect(
      team.copyWith(loop: null, updateLoop: true).loop,
      isNull,
    );
    expect(
      team.copyWith(loop: false, updateLoop: true).loop,
      isFalse,
    );
  });
}
