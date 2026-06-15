import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

void main() {
  TeamConfig team() => const TeamConfig(
        id: 'team-1',
        name: 'Team One',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      );

  test('explicit member capabilities flow into the roster profile', () {
    final member = const TeamMemberConfig(
      id: 'dev',
      name: 'Dev',
      capabilities: {'backend', 'rust'},
    );
    final profile = TeammateRosterProfile.fromMember(
      member: member,
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(profile.capabilities, {'backend', 'rust'});
  });

  test('empty capabilities derive from agentType then agent', () {
    final fromType = TeammateRosterProfile.fromMember(
      member: const TeamMemberConfig(id: 'fe', name: 'FE', agentType: 'frontend'),
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(fromType.capabilities, {'frontend'});

    final fromAgent = TeammateRosterProfile.fromMember(
      member: const TeamMemberConfig(id: 'qa', name: 'QA', agent: 'tester'),
      team: team(),
      cliTeamName: 'team-1-1',
      cwd: '/tmp',
    );
    expect(fromAgent.capabilities, {'tester'});
  });
}
