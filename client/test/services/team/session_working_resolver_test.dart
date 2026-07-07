import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  final resolver = SessionWorkingResolver();

  group('SessionWorkingResolver', () {
    test('personal active tab never uses team presence snapshot', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'personal-1', title: 'P', subtitle: ''),
        cliTeamName: '',
      )..persistedSession = AppSession(
          sessionId: 'personal-1',
          workspaceId: 'ws',
          folders: const [],
          createdAt: 0,
        );

      expect(
        resolver.usesPresenceSnapshotForTab(
          tab: tab,
          activeSessionId: 'personal-1',
          presenceNonEmpty: true,
        ),
        isFalse,
      );
    });

    test('mixed active tab uses presence snapshot when bus is installed', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'mixed-1', title: 'M', subtitle: ''),
        cliTeamName: 'team-a',
      )
        ..persistedSession = AppSession(
          sessionId: 'mixed-1',
          workspaceId: 'ws',
          folders: const [],
          sessionTeam: 'team-1',
          createdAt: 0,
        )
        ..teamBus = TeamBus(launcher: FakeMemberLauncher());

      expect(
        resolver.usesPresenceSnapshotForTab(
          tab: tab,
          activeSessionId: 'mixed-1',
          presenceNonEmpty: true,
        ),
        isTrue,
      );
    });

    test('personal userTurnActive is session-working when PTY is quiet', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(seconds: 5)),
        )
        ..markUserTurnStarted();

      final tab = ChatTab(
        info: ChatTabInfo(id: 'personal-1', title: 'P', subtitle: ''),
        cliTeamName: '',
      )
        ..persistedSession = AppSession(
          sessionId: 'personal-1',
          workspaceId: 'ws',
          folders: const [],
          createdAt: 0,
        )
        ..memberShells['agent'] = shell;

      expect(
        resolver.tabHasWorkingMember(
          tab: tab,
          team: null,
          globalPresets: const [],
        ),
        isTrue,
      );
    });

    test('personal PTY activity alone is not session-working', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(seconds: 5)),
        );
      shell.activityTracker.markActive();

      final tab = ChatTab(
        info: ChatTabInfo(id: 'personal-1', title: 'P', subtitle: ''),
        cliTeamName: '',
      )
        ..persistedSession = AppSession(
          sessionId: 'personal-1',
          workspaceId: 'ws',
          folders: const [],
          createdAt: 0,
        )
        ..memberShells['agent'] = shell;

      expect(
        resolver.tabHasWorkingMember(
          tab: tab,
          team: null,
          globalPresets: const [],
        ),
        isFalse,
        reason: 'personal working only follows userTurnActive latch',
      );
    });

    test('mixed bus in-turn is session-working after doorbell submitted', () {
      final shell = _ConnectedShell()
        ..activityTracker.latchBootFrameReadyForTest(
          DateTime.now().subtract(const Duration(milliseconds: 3000)),
        );
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode.test(
        memberId: 'worker',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneReady,
      )..doorbelled = true;
      bus.declareMember(node);
      bus.noteMailDeliverySubmitted('worker');

      final tab = ChatTab(
        info: ChatTabInfo(id: 'session-1', title: 'S', subtitle: ''),
        cliTeamName: 'team-a',
      )
        ..teamBus = bus
        ..memberShells['worker'] = shell;

      final team = const TeamProfile(
        id: 't',
        name: 'T',
        teamMode: TeamMode.mixed,
        cli: CliTool.cursor,
        members: [TeamMemberConfig(id: 'worker', name: 'worker')],
      );

      expect(
        resolver.tabHasWorkingMember(
          tab: tab,
          team: team,
          globalPresets: const [],
        ),
        isTrue,
        reason: 'submitted doorbell starts agent turn for session spinner',
      );
    });

    test('mixed operator turn is session-working when bus in-turn', () {
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

      final tab = ChatTab(
        info: ChatTabInfo(id: 'session-1', title: 'S', subtitle: ''),
        cliTeamName: 'team-a',
      )
        ..teamBus = bus
        ..memberShells['worker'] = shell;

      final team = const TeamProfile(
        id: 't',
        name: 'T',
        teamMode: TeamMode.mixed,
        cli: CliTool.cursor,
        members: [TeamMemberConfig(id: 'worker', name: 'worker')],
      );

      expect(
        resolver.tabHasWorkingMember(
          tab: tab,
          team: team,
          globalPresets: const [],
        ),
        isTrue,
      );
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
