import 'package:flashskyai_client/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips team config json with members', () {
    const team = TeamConfig(
      id: 'team-1',
      name: 'hello',
      workingDirectory: '/home/hhoa/project',
      extraArgs: '--permission-mode acceptEdits',
      members: [
        TeamMemberConfig(
          id: 'member-1',
          name: 'planner',
          provider: 'anthropic',
          model: 'sonnet',
          agent: 'builder',
          extraArgs: '--continue',
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

  test('is invalid when name or directory is blank', () {
    expect(
      const TeamConfig(
        id: 'team-1',
        name: '',
        workingDirectory: '/tmp',
      ).isValid,
      isFalse,
    );
    expect(
      const TeamConfig(
        id: 'team-1',
        name: 'hello',
        workingDirectory: '   ',
      ).isValid,
      isFalse,
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
      workingDirectory: '/tmp',
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
}
