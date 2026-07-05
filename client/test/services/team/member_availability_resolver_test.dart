import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_availability_resolver.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('MemberAvailabilityResolver', () {
    test('booting until PTY frame is stable', () {
      final shell = _ConnectedShell();
      shell.activityTracker.reset();
      expect(_resolve(shell, bus: null), MemberAvailability.booting);

      shell.activityTracker.latchBootFrameReadyForTest();
      expect(_resolve(shell, bus: null), MemberAvailability.idle);
    });

    test('isReadyForAutomationInput false while booting', () {
      final shell = _ConnectedShell();
      shell.activityTracker.reset();
      expect(
        MemberAvailabilityResolver.isReadyForAutomationInput(
          shell: shell,
          member: const TeamMemberConfig(id: 'worker', name: 'worker'),
          team: const TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed),
          teamMode: TeamMode.mixed,
          globalPresets: const [],
          bus: null,
          claudeRosterWorking: false,
          usesClaudeRoster: false,
          usesShellActivity: true,
        ),
        isFalse,
      );
      shell.activityTracker.latchBootFrameReadyForTest();
      expect(
        MemberAvailabilityResolver.isReadyForAutomationInput(
          shell: shell,
          member: const TeamMemberConfig(id: 'worker', name: 'worker'),
          team: const TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed),
          teamMode: TeamMode.mixed,
          globalPresets: const [],
          bus: null,
          claudeRosterWorking: false,
          usesClaudeRoster: false,
          usesShellActivity: true,
        ),
        isTrue,
      );
    });

    test(
      'mixed forceWait: idle at prompt, automation waits for wait_for_message',
      () {
        final shell = _ConnectedShell()
          ..activityTracker.latchBootFrameReadyForTest();
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
          MemberAvailability.idle,
          reason: 'turnDoneReady at prompt is idle once TUI is stable',
        );
        expect(
          MemberAvailabilityResolver.isReadyForAutomationInput(
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
          ),
          isFalse,
          reason: 'scheduled inject still waits for wait_for_message',
        );

        bus.declareMember(
          AgentNode.test(
            memberId: 'worker',
            lifecycle: MemberLifecycle.running,
            activity: MemberActivity.turnDoneBusWait,
          ),
        );
        expect(_resolve(shell, bus: bus), MemberAvailability.idle);
        expect(
          MemberAvailabilityResolver.isReadyForAutomationInput(
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
          ),
          isTrue,
        );
      },
    );

    test('mixed in-turn is idle when PTY is quiet (e.g. unconsumed doorbell)', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(milliseconds: 3000)),
        );
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      expect(
        _resolve(shell, bus: bus),
        MemberAvailability.idle,
        reason: 'bus in-turn must not override a quiet terminal',
      );
    });

    test('mixed in-turn is working when PTY has recent activity', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
      shell.activityTracker.markActive();

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
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
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
        reason:
            'startup PTY activity must not flip working before a turn signal',
      );
    });

    test('push-CLI doorbell allows PTY working', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
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

    test('push-CLI doorbell is idle when PTY is quiet', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(milliseconds: 3000)),
        );

      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        cli: 'cursor',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      )..doorbelled = true;
      bus.declareMember(node);

      expect(
        _resolvePushCli(shell, bus: bus),
        MemberAvailability.idle,
        reason:
            'unconsumed doorbell must not pin working when terminal is still',
      );
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
