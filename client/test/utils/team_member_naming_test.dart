import 'package:flutter_test/flutter_test.dart';
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
