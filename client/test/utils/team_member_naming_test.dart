import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  test('slugMemberName normalizes spaces and case', () {
    expect(TeamMemberNaming.slugMemberName('Developer One'), 'developer-one');
    expect(TeamMemberNaming.slugMemberName('team-lead'), 'team-lead');
  });

  test('formatAgentId strips @ from name', () {
    expect(
      TeamMemberNaming.formatAgentId('bad@name', 'team-x'),
      'bad-name@team-x',
    );
  });

  test('validateMemberName rejects @', () {
    expect(TeamMemberNaming.validateMemberName('a@b'), 'at_sign');
    expect(TeamMemberNaming.validateMemberName('ok'), isNull);
  });

  test('leadAgentId stays bare team-lead for Claude leader detection', () {
    expect(TeamMemberNaming.leadAgentId('my-team'), 'team-lead');
  });

  test('defaultRoster creates team-lead and member', () {
    final roster = TeamMemberNaming.defaultRoster(joinedAt: 42);
    expect(roster.map((m) => m.name).toList(), ['team-lead', 'member']);
    expect(roster.every((m) => m.joinedAt == 42), isTrue);
  });

  test('isTeamLead detects team-lead member', () {
    expect(
      TeamMemberNaming.isTeamLead(
        const TeamMemberConfig(id: 'lead', name: 'team-lead'),
      ),
      isTrue,
    );
    expect(
      TeamMemberNaming.isTeamLead(
        const TeamMemberConfig(id: 'member', name: 'member'),
      ),
      isFalse,
    );
  });

  test('cliAgentId uses bare id for team-lead only', () {
    expect(
      TeamMemberNaming.cliAgentId(
        memberName: 'team-lead',
        cliTeamName: 'my-team',
      ),
      'team-lead',
    );
    expect(
      TeamMemberNaming.cliAgentId(
        memberName: 'developer',
        cliTeamName: 'my-team',
      ),
      'developer@my-team',
    );
  });
}
