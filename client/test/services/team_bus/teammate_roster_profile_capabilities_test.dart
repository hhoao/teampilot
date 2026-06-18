import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

void main() {
  TeamProfile team() => const TeamProfile(
        id: 'team-1',
        name: 'Team One',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      );

  TeammateRosterProfile profile(TeamMemberConfig m) =>
      TeammateRosterProfile.fromMember(
        member: m,
        team: team(),
        cliTeamName: 'team-1-1',
        cwd: '/tmp',
      );

  test('member id is always an implicit capability', () {
    expect(
      profile(const TeamMemberConfig(id: 'builder', name: 'Builder')).capabilities,
      {'builder'},
    );
  });

  test('explicit capabilities are unioned with the member id', () {
    final caps = profile(const TeamMemberConfig(
      id: 'dev',
      name: 'Dev',
      capabilities: {'backend', 'rust'},
    )).capabilities;
    expect(caps, {'dev', 'backend', 'rust'});
  });

  test('minimal profile carries its member id as a capability', () {
    expect(TeammateRosterProfile.minimal('reviewer').capabilities, {'reviewer'});
  });
}
