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
}
