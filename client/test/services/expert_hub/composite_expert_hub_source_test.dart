import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';

void main() {
  test('fetchMembers includes builtin templates', () async {
    final source = CompositeExpertHubSource.withDefaults();
    final members = await source.fetchMembers();

    expect(members.length, greaterThanOrEqualTo(12));
    expect(
      members.any((m) => m.key == 'teampilot/builtin/developer'),
      isTrue,
    );
    expect(
      members.where((m) => m.source == ExpertMemberSource.builtin).length,
      greaterThanOrEqualTo(12),
    );
  });

  test('team extract dedupes when prompt+playbook matches builtin', () async {
    final developerBuiltin = builtinExpertMembers().firstWhere(
      (m) => m.key == 'teampilot/builtin/developer',
    );

    final team = DiscoverableTeam(
      key: 'example/custom-team',
      name: 'Custom Team',
      description: 'Team with a developer clone',
      category: 'Development',
      updatedAt: 1,
      cli: CliTool.claude,
      members: [
        DiscoverableTeamMember(
          name: 'developer',
          prompt: developerBuiltin.member.prompt,
          playbook: developerBuiltin.member.playbook,
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
}
