import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../team_bus/support/fake_member_launcher.dart';

void main() {
  final resolver = SessionWorkingResolver();

  group('SessionWorkingResolver.isMemberWorking', () {
    test('presence snapshot true for working member, false for idle peer', () {
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
        ..teamBus = TeamBus(launcher: FakeMemberLauncher())
        ..memberShells['worker'] = _ConnectedShell()
        ..memberShells['idle-peer'] = _ConnectedShell();

      const team = TeamProfile(
        id: 'team-1',
        name: 'T',
        teamMode: TeamMode.mixed,
        cli: CliTool.cursor,
        members: [
          TeamMemberConfig(id: 'worker', name: 'worker'),
          TeamMemberConfig(id: 'idle-peer', name: 'idle-peer'),
        ],
      );

      final presence = {
        'worker': const MemberPresence(
          connection: MemberConnection.connected,
          availability: MemberAvailability.working,
        ),
        'idle-peer': const MemberPresence(
          connection: MemberConnection.connected,
          availability: MemberAvailability.idle,
        ),
      };

      expect(
        resolver.isMemberWorking(
          tab: tab,
          memberId: 'worker',
          team: team,
          globalPresets: const [],
          presence: presence,
          usePresenceSnapshot: true,
        ),
        isTrue,
      );

      expect(
        resolver.isMemberWorking(
          tab: tab,
          memberId: 'idle-peer',
          team: team,
          globalPresets: const [],
          presence: presence,
          usePresenceSnapshot: true,
        ),
        isFalse,
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
