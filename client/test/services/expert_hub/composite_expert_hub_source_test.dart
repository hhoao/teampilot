import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';

void main() {
  test('fetchMembers includes builtin templates', () async {
    final source = CompositeExpertHubSource.withDefaults();
    final members = await source.fetchMembers();

    expect(members.length, greaterThanOrEqualTo(8));
    expect(
      members.any((m) => m.key == 'teampilot/builtin/developer'),
      isTrue,
    );
    expect(
      members.where((m) => m.source == ExpertMemberSource.builtin).length,
      8,
    );
  });

  test('team roster with builtin expert keys does not duplicate catalog', () async {
    final developerBuiltin = builtinExpertMembers().firstWhere(
      (m) => m.key == 'teampilot/builtin/developer',
    );

    final team = DiscoverableTeam(
      key: 'example/custom-team',
      name: 'Custom Team',
      description: 'Team referencing a builtin developer',
      category: 'Development',
      updatedAt: 1,
      cli: CliTool.claude,
      roster: [
        TeamRosterSlot(
          id: 'developer',
          expertKey: developerBuiltin.key,
        ),
      ],
    );

    final source = CompositeExpertHubSource.withDefaults(teams: [team]);
    final members = await source.fetchMembers();

    expect(
      members.any((m) => m.key == 'teampilot/builtin/developer'),
      isTrue,
    );
    expect(
      members.any((m) => m.key == 'example/custom-team#developer'),
      isFalse,
    );
    expect(
      members.where((m) => m.source == ExpertMemberSource.teamExtract),
      isEmpty,
    );
  });

  test('team roster with custom expert keys is indexed for discovery', () async {
    const customKey = 'example/custom-expert';
    final team = DiscoverableTeam(
      key: 'example/custom-team',
      name: 'Custom Team',
      description: 'Team with a custom expert reference',
      category: 'Development',
      updatedAt: 1,
      cli: CliTool.claude,
      roster: const [
        TeamRosterSlot(id: 'researcher', expertKey: customKey),
      ],
    );

    final source = CompositeExpertHubSource.withDefaults(teams: [team]);
    final members = await source.fetchMembers();

    expect(members.any((m) => m.key == customKey), isTrue);
    expect(
      members
          .where((m) => m.source == ExpertMemberSource.teamExtract)
          .map((m) => m.key),
      contains(customKey),
    );
  });
}
