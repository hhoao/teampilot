import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/launch/session_launch_connect_prep_runner.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('needsTeamRuntimeOnReuse', () {
    test('true for a team tab without a bus', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
      );
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: false), isTrue);
    });

    test('false when the bus is already installed', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
      )..teamBus = TeamBus(launcher: FakeMemberLauncher());
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: false), isFalse);
    });

    test('false for personal sessions', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: '',
        workspaceId: 'ws-1',
      );
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: true), isFalse);
    });
  });
}
