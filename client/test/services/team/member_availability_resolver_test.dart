import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_availability_resolver.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/member_state.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('MemberAvailabilityResolver', () {
    test('booting until PTY frame is stable', () {
      final shell = _ConnectedShell();
      shell.activityTracker.reset();
      expect(
        _resolve(shell, bus: null),
        MemberAvailability.booting,
      );

      shell.activityTracker.latchBootFrameReadyForTest();
      expect(_resolve(shell, bus: null), MemberAvailability.idle);
    });

    test('mixed forceWait: idle only in wait_for_message', () {
      final shell = _ConnectedShell()..activityTracker.latchBootFrameReadyForTest();
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );

      expect(
        _resolve(shell, bus: bus),
        MemberAvailability.booting,
        reason: 'turnDoneReady without wait is still booting',
      );

      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneBusWait,
        ),
      );
      expect(_resolve(shell, bus: bus), MemberAvailability.idle);
    });

    test('mixed in-turn is working regardless of PTY quiet', () {
      final shell = _ConnectedShell()..activityTracker.latchBootFrameReadyForTest();
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      expect(_resolve(shell, bus: bus), MemberAvailability.working);
    });

    test('push-CLI PTY churn without turn signal stays idle', () {
      final shell = _ConnectedShell()..activityTracker.latchBootFrameReadyForTest();
      shell.activityTracker.markActive();
      expect(shell.activityTracker.isWorking, isTrue);

      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          cli: 'cursor',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );

      expect(
        _resolvePushCli(shell, bus: bus),
        MemberAvailability.idle,
        reason: 'startup PTY activity must not flip working before a turn signal',
      );
    });

    test('push-CLI doorbell allows PTY working', () {
      final shell = _ConnectedShell()..activityTracker.latchBootFrameReadyForTest();
      shell.activityTracker.markActive();

      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        cli: 'cursor',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      )..doorbelled = true;
      bus.declareMember(node);

      expect(_resolvePushCli(shell, bus: bus), MemberAvailability.working);
    });
  });
}

MemberAvailability _resolve(TerminalSession shell, {required TeamBus? bus}) {
  return MemberAvailabilityResolver.forConnected(
    shell: shell,
    member: const TeamMemberConfig(id: 'worker', name: 'worker'),
    team: const TeamProfile(
      id: 't',
      name: 'T',
      teamMode: TeamMode.mixed,
      members: [TeamMemberConfig(id: 'worker', name: 'worker')],
    ),
    teamMode: TeamMode.mixed,
    globalPresets: const [],
    bus: bus,
    claudeRosterWorking: false,
    usesClaudeRoster: false,
    usesShellActivity: false,
  );
}

MemberAvailability _resolvePushCli(
  TerminalSession shell, {
  required TeamBus bus,
}) {
  return MemberAvailabilityResolver.forConnected(
    shell: shell,
    member: const TeamMemberConfig(
      id: 'worker',
      name: 'worker',
      cli: CliTool.cursor,
    ),
    team: const TeamProfile(
      id: 't',
      name: 'T',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      members: [
        TeamMemberConfig(id: 'worker', name: 'worker', cli: CliTool.cursor),
      ],
    ),
    teamMode: TeamMode.mixed,
    globalPresets: const [],
    bus: bus,
    claudeRosterWorking: false,
    usesClaudeRoster: false,
    usesShellActivity: false,
  );
}

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'claude', validateLaunch: false);

  @override
  bool get isConnecting => false;

  @override
  bool get isConnected => true;

  @override
  bool get isRunning => true;
}
