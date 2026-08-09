import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/expert_hub/expert_member_materializer.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

void main() {
  test('superpowers quartet roster references four builtin experts', () {
    final roster = kSuperpowersTrioTeamTemplate.roster;
    expect(roster, hasLength(4));
    expect(roster[0].id, TeamMemberNaming.teamLeadName);
    expect(roster[1].id, 'architect');
    expect(roster[2].id, 'builder');
    expect(roster[3].id, 'reviewer');
    for (final slot in roster) {
      expect(slot.expertKey, startsWith('teampilot/builtin/superpowers-'));
    }
  });

  test(
    'materialized superpowers roster carries prompts and inherit preset',
    () async {
      final team = TeamProfile(
        id: 'superpowers',
        name: 'Superpowers',
        roster: kSuperpowersTrioTeamTemplate.roster,
      );
      final configs = await ExpertMemberMaterializer.materializeRosterAsync(
        team: team,
      );
      expect(configs, hasLength(4));
      expect(configs[0].playbook, isNotEmpty);
      expect(configs[1].responsibilities, contains('Do NOT'));
      for (final member in configs) {
        expect(member.inheritsTeamPreset, isTrue);
        expect(member.activePresetId, TeamProfile.inheritPresetId);
      }
    },
  );

  test(
    'delegate-only lead is not told to brainstorm or dispatch agents',
    () async {
      final team = TeamProfile(
        id: 'superpowers',
        name: 'Superpowers',
        roster: kSuperpowersTrioTeamTemplate.roster,
      );
      final configs = await ExpertMemberMaterializer.materializeRosterAsync(
        team: team,
      );
      final lead = configs.firstWhere((m) => TeamMemberNaming.isTeamLead(m));
      final text = '${lead.responsibilities}\n${lead.playbook}';
      expect(text, isNot(contains('brainstorming')));
      expect(text, isNot(contains('dispatching-parallel-agents')));
    },
  );

  test(
    'materialized workers inherit capabilities from expert catalog',
    () async {
      final team = TeamProfile(
        id: 'superpowers',
        name: 'Superpowers',
        roster: kSuperpowersTrioTeamTemplate.roster,
      );
      final configs = await ExpertMemberMaterializer.materializeRosterAsync(
        team: team,
      );
      final architect = configs.firstWhere((m) => m.id == 'architect');
      expect(architect.capabilities, contains('design'));
      final builder = configs.firstWhere((m) => m.id == 'builder');
      expect(builder.capabilities, contains('implementation'));
    },
  );

  test('lead routes tasks to member types by name and gates review', () async {
    final team = TeamProfile(
      id: 'superpowers',
      name: 'Superpowers',
      roster: kSuperpowersTrioTeamTemplate.roster,
    );
    final configs = await ExpertMemberMaterializer.materializeRosterAsync(
      team: team,
    );
    final lead = configs.firstWhere((m) => TeamMemberNaming.isTeamLead(m));
    final text = '${lead.responsibilities}\n${lead.playbook}';
    expect(text, contains('architect'));
    expect(text, contains('builder'));
    expect(text, contains('reviewer'));
    expect(text, contains('phase gates'));
  });

  test('superpowers quartet declares claude as its base CLI', () {
    expect(kSuperpowersTrioTeamTemplate.cliDeclared, isTrue);
    expect(kSuperpowersTrioTeamTemplate.cli, CliTool.claude);
    expect(kSuperpowersTrioTeamTemplate.teamModeDeclared, isTrue);
    expect(kSuperpowersTrioTeamTemplate.teamMode, TeamMode.mixed);
  });
}
