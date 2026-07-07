import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/member_coordination.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('MemberCoordination', () {
    test('personal: userTurnActive is working, PTY churn is idle', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(seconds: 5)),
        );

      final coordination = MemberCoordination.resolve(
        shell: shell,
        member: const TeamMemberConfig(id: 'solo', name: 'solo'),
        team: const TeamProfile(id: '', name: ''),
        teamMode: TeamMode.native,
        globalPresets: const [],
        isPersonalSession: true,
      );

      shell.activityTracker.markActive();
      expect(coordination.availability(), MemberAvailability.idle);

      shell.markUserTurnStarted();
      expect(coordination.availability(), MemberAvailability.working);
    });

    test('mixed: bus in-turn without PTY bytes is working', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.active,
        ),
      );

      final coordination = MemberCoordination.resolve(
        shell: shell,
        member: const TeamMemberConfig(id: 'worker', name: 'worker'),
        team: const TeamProfile(
          id: 't',
          name: 'T',
          teamMode: TeamMode.mixed,
        ),
        teamMode: TeamMode.mixed,
        globalPresets: const [],
        bus: bus,
        isPersonalSession: false,
      );

      expect(coordination.availability(), MemberAvailability.working);
      expect(coordination.inTurn(pendingDelivery: false), isTrue);
    });

    test('latchTurnStarted routes to bus or shell by kind', () {
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

      MemberCoordination.resolve(
        shell: shell,
        member: const TeamMemberConfig(id: 'worker', name: 'worker'),
        team: const TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed),
        teamMode: TeamMode.mixed,
        globalPresets: const [],
        bus: bus,
        isPersonalSession: false,
      ).latchTurnStarted();

      expect(bus.isMemberInTurn('worker'), isTrue);
      expect(shell.userTurnActive, isFalse);

      final solo = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest();
      MemberCoordination.resolve(
        shell: solo,
        member: const TeamMemberConfig(id: 'solo', name: 'solo'),
        team: const TeamProfile(id: '', name: ''),
        teamMode: TeamMode.native,
        globalPresets: const [],
        isPersonalSession: true,
      ).latchTurnStarted();
      expect(solo.userTurnActive, isTrue);
    });

    test('mixed latch with null shell only updates bus', () {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(
        AgentNode.test(
          memberId: 'worker',
          lifecycle: MemberLifecycle.running,
          activity: MemberActivity.turnDoneReady,
        ),
      );

      MemberCoordination.resolve(
        shell: _ConnectedShell()
          ..activityTracker.latchBootFrameReadyForTest(),
        member: const TeamMemberConfig(id: 'worker', name: 'worker'),
        team: const TeamProfile(id: 't', name: 'T', teamMode: TeamMode.mixed),
        teamMode: TeamMode.mixed,
        globalPresets: const [],
        bus: bus,
        isPersonalSession: false,
      ).latchTurnStarted();

      expect(bus.isMemberInTurn('worker'), isTrue);
    });
  });
}

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'true');

  @override
  bool get isRunning => true;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}
