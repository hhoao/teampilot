import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_presence_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  test('compute maps connection and flashskyai workload', () async {
    final service = MemberPresenceService();
    final shell = TerminalSession(executable: 'flashskyai', validateLaunch: false);
    shell.activityTracker.markActive();

    final presence = await service.compute(
      teamCli: CliTool.flashskyai,
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: {'team-lead': shell},
    );

    expect(presence['team-lead']!.connection, MemberConnection.offline);
    expect(presence['team-lead']!.workload, isNull);
  });

  test('connected flashskyai shell uses activity tracker', () async {
    final service = MemberPresenceService();
    final shell = _ConnectedShell();
    shell.activityTracker.reset();
    expect(shell.activityTracker.isWorking, isFalse);
    shell.activityTracker.markActive();
    expect(shell.activityTracker.isWorking, isTrue);

    final presence = await service.compute(
      teamCli: CliTool.flashskyai,
      members: const [
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: {'dev': shell},
    );

    expect(presence['dev']!.connection, MemberConnection.connected);
    expect(presence['dev']!.workload, MemberWorkload.working);
  });
}

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'flashskyai', validateLaunch: false);

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  bool get isRunning => true;
}
