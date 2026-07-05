import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/team/team_roster_editor.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/team_member_naming.dart';

TeamProfile teamWithMembers(List<TeamMemberConfig> members) => TeamProfile(
  id: 'squad',
  name: 'Squad',
  createdAt: 1,
  members: members,
);

void main() {
  const editor = TeamRosterEditor();

  test('addMemberFromConfig uniquifies slug id on collision', () {
    const existing = TeamMemberConfig(
      id: 'developer',
      name: 'Developer',
      joinedAt: 1,
    );
    const template = TeamMemberConfig(
      id: 'developer',
      name: 'Developer',
      prompt: 'Ship features.',
      joinedAt: 0,
    );

    final (team: updated, :added) = editor.addMemberFromConfig(
      teamWithMembers([existing]),
      template,
    );

    expect(updated.members, hasLength(2));
    expect(updated.members.map((m) => m.id), containsAll(['developer', 'developer-2']));
    expect(added.id, 'developer-2');
    expect(added.prompt, 'Ship features.');
    expect(added.activePresetId, TeamProfile.inheritPresetId);
  });

  test('addMemberFromConfig uniquifies display name on collision', () {
    const existing = TeamMemberConfig(
      id: 'dev-a',
      name: 'Developer',
      joinedAt: 1,
    );
    const template = TeamMemberConfig(
      id: 'developer',
      name: 'Developer',
      joinedAt: 0,
    );

    final result = editor.addMemberFromConfig(
      teamWithMembers([existing]),
      template,
    );

    expect(result.added.name, 'Developer (2)');
  });

  test('addMemberFromConfig slugs from name when template id is empty', () {
    const template = TeamMemberConfig(
      id: '',
      name: 'Product Manager',
      joinedAt: 0,
    );

    final (team: updated, :added) = editor.addMemberFromConfig(
      teamWithMembers(const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead', joinedAt: 1),
      ]),
      template,
    );

    expect(added.id, TeamMemberNaming.slugMemberName('Product Manager'));
    expect(updated.members, hasLength(2));
  });
}
