import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_presence_service.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  test('compute maps connection and flashskyai availability', () async {
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
    expect(presence['team-lead']!.availability, isNull);
  });

  test('connected flashskyai shell uses activity tracker after boot frame', () async {
    final service = MemberPresenceService();
    final shell = _ConnectedShell();
    shell.activityTracker.reset();
    expect(
      shell.activityTracker.isBootFrameReady,
      isFalse,
      reason: 'no PTY bytes yet',
    );

    final booting = await service.compute(
      teamCli: CliTool.flashskyai,
      members: const [
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: {'dev': shell},
      session: _session(),
    );
    expect(booting['dev']!.availability, MemberAvailability.booting);

    shell.activityTracker.latchBootFrameReadyForTest();
    shell.activityTracker.markActive();
    expect(shell.activityTracker.isWorking, isTrue);

    final working = await service.compute(
      teamCli: CliTool.flashskyai,
      members: const [
        TeamMemberConfig(id: 'dev', name: 'developer'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: {'dev': shell},
      session: _session(),
    );
    expect(working['dev']!.availability, MemberAvailability.working);
  });

  test('mixed session: booting only until PTY frame is stable', () async {
    final service = MemberPresenceService();
    final shell = _ConnectedShell()..activityTracker.latchBootFrameReadyForTest();
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'waiter'));
    bus.markMemberRunning('waiter');

    final atPrompt = await service.compute(
      teamCli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'waiter', name: 'waiter')],
      cliTeamName: 't-1',
      memberToolConfigDir: '/tmp/cfg',
      memberShells: {'waiter': shell},
      session: PresenceSessionContext(
        team: const TeamProfile(
          id: 't',
          name: 'T',
          teamMode: TeamMode.mixed,
          members: [TeamMemberConfig(id: 'waiter', name: 'waiter')],
        ),
        teamBus: bus,
      ),
    );
    expect(atPrompt['waiter']!.availability, MemberAvailability.idle);

    shell.activityTracker.reset();
    final booting = await service.compute(
      teamCli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'waiter', name: 'waiter')],
      cliTeamName: 't-1',
      memberToolConfigDir: '/tmp/cfg',
      memberShells: {'waiter': shell},
      session: PresenceSessionContext(
        team: const TeamProfile(
          id: 't',
          name: 'T',
          teamMode: TeamMode.mixed,
          members: [TeamMemberConfig(id: 'waiter', name: 'waiter')],
        ),
        teamBus: bus,
      ),
    );
    expect(booting['waiter']!.availability, MemberAvailability.booting);

    shell.activityTracker.latchBootFrameReadyForTest();
    bus.declareMember(
      AgentNode.test(
        memberId: 'waiter',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait,
      ),
    );
    final idle = await service.compute(
      teamCli: CliTool.claude,
      members: const [TeamMemberConfig(id: 'waiter', name: 'waiter')],
      cliTeamName: 't-1',
      memberToolConfigDir: '/tmp/cfg',
      memberShells: {'waiter': shell},
      session: PresenceSessionContext(
        team: const TeamProfile(
          id: 't',
          name: 'T',
          teamMode: TeamMode.mixed,
          members: [TeamMemberConfig(id: 'waiter', name: 'waiter')],
        ),
        teamBus: bus,
      ),
    );
    expect(idle['waiter']!.availability, MemberAvailability.idle);
  });

  test('session context only consulted for connected members', () async {
    final service = MemberPresenceService();
    final bus = TeamBus(launcher: FakeMemberLauncher());

    final presence = await service.compute(
      teamCli: CliTool.codex,
      members: const [
        TeamMemberConfig(id: 'offline', name: 'offline'),
      ],
      cliTeamName: 't-1',
      memberToolConfigDir: null,
      memberShells: const {},
      session: PresenceSessionContext(
        team: const TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed),
        teamBus: bus,
      ),
    );

    expect(presence['offline']!.connection, MemberConnection.offline);
    expect(presence['offline']!.availability, isNull);
  });
}

PresenceSessionContext _session() => const PresenceSessionContext(
      team: TeamProfile(id: 't', name: 'T'),
    );

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'flashskyai', validateLaunch: false);

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  bool get isRunning => true;
}
