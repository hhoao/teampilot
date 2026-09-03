import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/session_launch_pipeline.dart';

void main() {
  TeamProfile team(TeamMode mode) => TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ],
    cli: CliTool.claude,
    teamMode: mode,
  );

  group('shouldLaunchAllMembers', () {
    test('native team launches all members regardless of preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: false,
        ),
        isTrue,
        reason: 'native teams break when members are missing',
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
    });

    test('mixed team honors the preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: false,
        ),
        isFalse,
      );
    });
  });
}
