import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/team/team_roster_editor.dart';
import 'package:teampilot/models/default_team_roster.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';

TeamProfile teamWithRoster(List<TeamRosterSlot> roster) => TeamProfile(
  id: 'squad',
  name: 'Squad',
  createdAt: 1,
  roster: roster,
);

void main() {
  const editor = TeamRosterEditor();
  const expertKey = 'teampilot/builtin/developer';

  test('addExpertToTeam uniquifies slot id on collision', () {
    const existing = TeamRosterSlot(
      id: 'developer',
      expertKey: expertKey,
      joinedAt: 1,
    );

    final (team: updated, :added) = editor.addExpertToTeam(
      teamWithRoster([existing]),
      expertKey,
      slotIdHint: 'developer',
    );

    expect(updated.roster, hasLength(2));
    expect(updated.roster.map((s) => s.id), containsAll(['developer', 'developer-2']));
    expect(added.id, 'developer-2');
    expect(added.expertKey, expertKey);
  });

  test('addExpertToTeam uses default developer expert for generic addMember', () {
    final (team: updated, :added) = editor.addMember(
      teamWithRoster(const [
        TeamRosterSlot(
          id: 'team-lead',
          expertKey: 'teampilot/builtin/team-lead',
          joinedAt: 1,
        ),
      ]),
    );

    expect(updated.roster, hasLength(2));
    expect(added.expertKey, DefaultTeamRoster.expertKeyForSlug('developer'));
  });
}
