import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  test('superpowers quartet clones to team-lead + slugged workers', () {
    final now = 1;
    final configs = kSuperpowersTrioTeamTemplate.members
        .map((m) => m.toMemberConfig(joinedAt: now))
        .toList();
    expect(configs, hasLength(4));
    expect(configs[0].id, TeamMemberNaming.teamLeadName);
    expect(configs[1].id, 'architect');
    expect(configs[2].id, 'builder');
    expect(configs[3].id, 'reviewer');
    expect(configs[0].playbook, isNotEmpty);
    expect(configs[1].prompt, contains('Do NOT'));
  });

  test('delegate-only lead is not told to brainstorm or dispatch agents', () {
    final lead = kSuperpowersTrioTeamTemplate.members
        .firstWhere((m) => TeamMemberNaming.isTeamLeadName(m.name));
    final text = '${lead.prompt}\n${lead.playbook}';
    expect(text, isNot(contains('brainstorming')));
    expect(text, isNot(contains('dispatching-parallel-agents')));
  });

  test('quartet members carry routing capabilities', () {
    final byId = {
      for (final m in kSuperpowersTrioTeamTemplate.members)
        m.toMemberConfig(joinedAt: 1).id: m.toMemberConfig(joinedAt: 1),
    };
    // team-lead never auto-claims; capabilities are for the workers.
    expect(byId['architect']!.capabilities, contains('design'));
    expect(byId['builder']!.capabilities, {'implement'});
    expect(byId['reviewer']!.capabilities, {'review'});
  });

  test('lead routes tasks by required_capabilities and gates review', () {
    final lead = kSuperpowersTrioTeamTemplate.members
        .firstWhere((m) => TeamMemberNaming.isTeamLeadName(m.name));
    final text = '${lead.prompt}\n${lead.playbook}';
    expect(text, contains('required_capabilities'));
    expect(text, contains('depends_on'));
  });
}
