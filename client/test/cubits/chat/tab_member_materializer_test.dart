import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/member_connector.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_materializer.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingConnector implements MemberConnector {
  var scheduleCalls = 0;

  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {
    scheduleCalls++;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('mixed materialize waits without duplicate connect while bus boots', () async {
    final store = ChatTabStore();
    store.setActiveWorkspace('ws-1');
    final tab = ChatTab(
      info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
      workspaceId: 'ws-1',
      cliTeamName: 'team-runtime',
    )..persistedSession = AppSession(
        sessionId: 'sess-1',
        workspaceId: 'ws-1',
        sessionTeam: 'team-1',
        cliTeamName: 'team-runtime',
        createdAt: 0,
      );
    store.append(tab);

    const team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      cli: CliTool.cursor,
      teamMode: TeamMode.mixed,
      members: [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );

    final connector = _RecordingConnector();
    final materializer = TabMemberMaterializer(
      runtime: TabSessionRuntimeCoordinator(
        tabStore: store,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => team,
        isClosed: () => false,
      ),
      tabStore: store,
      connector: connector,
      activeTeam: () => team,
      isClosed: () => false,
      isMixedBusRegistered: (_) => false,
      isMemberConnectOwnedElsewhere: (_, _) => true,
    );

    final pending = materializer.materializeMember('sess-1', 'team-lead', '');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(connector.scheduleCalls, 0);

    materializer.markMemberReady('sess-1', 'team-lead');
    await pending;
  });
}
