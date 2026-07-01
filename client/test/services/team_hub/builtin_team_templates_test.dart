import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
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
    for (final member in configs) {
      expect(member.inheritsTeamPreset, isTrue);
      expect(member.activePresetId, TeamProfile.inheritPresetId);
    }
  });

  test('delegate-only lead is not told to brainstorm or dispatch agents', () {
    final lead = kSuperpowersTrioTeamTemplate.members
        .firstWhere((m) => TeamMemberNaming.isTeamLeadName(m.name));
    final text = '${lead.prompt}\n${lead.playbook}';
    expect(text, isNot(contains('brainstorming')));
    expect(text, isNot(contains('dispatching-parallel-agents')));
  });

  test('quartet workers carry no explicit capabilities (routed by type name)',
      () {
    for (final m in kSuperpowersTrioTeamTemplate.members) {
      expect(m.capabilities, isEmpty);
    }
  });

  test('lead routes tasks to member types by name and gates review', () {
    final lead = kSuperpowersTrioTeamTemplate.members
        .firstWhere((m) => TeamMemberNaming.isTeamLeadName(m.name));
    final text = '${lead.prompt}\n${lead.playbook}';
    expect(text, contains('["architect"]'));
    expect(text, contains('["builder"]'));
    expect(text, contains('["reviewer"]'));
    expect(text, contains('depends_on'));
  });
}
