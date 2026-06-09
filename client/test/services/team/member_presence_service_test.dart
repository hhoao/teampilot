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

  test(
      'mixed workloadResolver overrides CLI capability: working unless '
      'parked in wait_for_message', () async {
    final service = MemberPresenceService();
    final waiting = _ConnectedShell();
    final working = _ConnectedShell();

    // teamCli=claude (usesClaudeRoster) would idle a non-claude member, but the
    // resolver (TeamBus truth) must win and key purely off wait_for_message.
    final presence = await service.compute(
      teamCli: CliTool.claude,
      members: const [
        TeamMemberConfig(id: 'waiter', name: 'waiter'),
        TeamMemberConfig(id: 'busy', name: 'busy'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: '/tmp/does-not-matter',
      memberShells: {'waiter': waiting, 'busy': working},
      workloadResolver: (id) =>
          id == 'waiter' ? MemberWorkload.idle : MemberWorkload.working,
    );

    expect(presence['waiter']!.workload, MemberWorkload.idle);
    expect(presence['busy']!.workload, MemberWorkload.working);
  });

  test('resolver only consulted for connected members', () async {
    final service = MemberPresenceService();
    final consulted = <String>[];

    final presence = await service.compute(
      teamCli: CliTool.codex,
      members: const [
        TeamMemberConfig(id: 'offline', name: 'offline'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: const {}, // no shell → offline
      workloadResolver: (id) {
        consulted.add(id);
        return MemberWorkload.working;
      },
    );

    expect(presence['offline']!.connection, MemberConnection.offline);
    expect(presence['offline']!.workload, isNull);
    expect(consulted, isEmpty);
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
