import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/member_connector.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_materializer.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingConnector implements MemberConnector {
  var scheduleCalls = 0;
  String? lastMemberId;

  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {
    scheduleCalls++;
    lastMemberId = member.id;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('mixed materialize waits without duplicate connect while bus boots', () async {
    final store = ChatTabStore();
    store.setActiveWorkspaceId('ws-1');
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
    store.registerSession(tab);

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

  test(
    'materialize resolves numbered instance ids from session roster',
    () async {
      final store = ChatTabStore();
      store.setActiveWorkspaceId('ws-1');
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
          members: const [
            SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't1'),
            SessionMemberBinding(
              rosterMemberId: 'builder-1',
              taskId: 't2',
              typeId: 'builder',
            ),
          ],
        );
      store.registerSession(tab);

      // In-memory team still has type ids only (replicas may even be stale).
      // Use native mode so this unit test does not wait on TeamBus install.
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
        ],
      );

      final connector = _RecordingConnector();
      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => team,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: connector,
        activeTeam: () => team,
        isClosed: () => false,
        isMixedBusRegistered: (_) => true,
        isMemberConnectOwnedElsewhere: (_, _) => false,
      );

      final pending = materializer.materializeMember('sess-1', 'builder-1', '');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(connector.scheduleCalls, 1);
      expect(connector.lastMemberId, 'builder-1');

      materializer.markMemberReady('sess-1', 'builder-1');
      await pending;
    },
  );

  test(
    'personal materialize hangs until markMemberReady when shell not running',
    () async {
      final store = ChatTabStore();
      store.setActiveWorkspaceId('ws-1');
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        workspaceId: 'ws-1',
        cliTeamName: '',
      )..persistedSession = AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          sessionTeam: '',
          createdAt: 0,
        );
      store.registerSession(tab);

      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
          globalPresets: () => const [],
          activeTeam: () => null,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: _RecordingConnector(),
        activeTeam: () => null,
        isClosed: () => false,
        isMixedBusRegistered: (_) => false,
        isMemberConnectOwnedElsewhere: (_, _) => false,
      );

      final pending = materializer.materializeMember('sess-1', 'sess-1', '');
      var completed = false;
      unawaited(pending.then((_) => completed = true));
      // Yield so materialize can park on the ready completer without wall delay.
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      materializer.markMemberReady('sess-1', 'sess-1');
      await pending;
      expect(completed, isTrue);
    },
  );
}
