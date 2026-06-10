import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  test('superpowers trio clones to team-lead + slugged workers', () {
    final now = 1;
    final configs = kSuperpowersTrioTeamTemplate.members
        .map((m) => m.toMemberConfig(joinedAt: now))
        .toList();
    expect(configs[0].id, TeamMemberNaming.teamLeadName);
    expect(configs[1].id, 'builder');
    expect(configs[2].id, 'reviewer');
    expect(configs[0].playbook, isNotEmpty);
    expect(configs[1].prompt, contains('Do NOT'));
  });
}
