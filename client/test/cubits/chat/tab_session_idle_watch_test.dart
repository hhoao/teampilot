import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/runtime/tab_member_coordination_factory.dart';
import 'package:teampilot/services/chat/runtime/tab_session_idle_watch.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/session/session_working_resolver.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/rust_lib_test_init.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  setUpAll(initRustLibForTests);

  test('onAfterTurnEnded fires on PTY-quiet turn end for Cursor', () async {
    final store = ChatTabStore(storage: fakeHomeStorage());
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''),
      cliTeamName: 's1',
    );
    tab.persistedSession = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.cursor,
      createdAt: 1,
    );
    store.registerSession(tab);

    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells['s1'] = shell.session;

    final coordination = TabMemberCoordinationFactory(
      tabStore: store,
      globalPresets: () => const [],
      activeTeam: () => null,
      sessionWorking: SessionWorkingResolver(),
    );
    String? endedSession;
    String? endedMember;
    final watch = TabSessionIdleWatch(
      tabStore: store,
      coordinationFactory: coordination,
      isClosed: () => false,
      memberCli: (_, __) => CliTool.cursor,
      onAfterTurnEnded: (sid, mid) {
        endedSession = sid;
        endedMember = mid;
      },
    );

    shell.session.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    shell.session.markUserTurnStarted();
    watch.tick();
    shell.simulateQuietGap();
    watch.tick();
    await Future<void>.delayed(Duration.zero);

    expect(endedSession, 's1');
    expect(endedMember, 's1');
    watch.dispose();
  });

  test(
    'a quiet end publishes idle only after onBeforeTurnEnded finishes',
    () async {
      final store = ChatTabStore(storage: fakeHomeStorage());
      final tab = ChatTab(
        info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''),
        cliTeamName: 's1',
      );
      tab.persistedSession = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.cursor,
        createdAt: 1,
      );
      store.registerSession(tab);

      final shell = await ConnectedRecordingShell.connect();
      tab.memberShells['s1'] = shell.session;

      final coordination = TabMemberCoordinationFactory(
        tabStore: store,
        globalPresets: () => const [],
        activeTeam: () => null,
        sessionWorking: SessionWorkingResolver(),
      );
      final gate = Completer<void>();
      var prepared = 0;
      var ended = false;
      final watch = TabSessionIdleWatch(
        tabStore: store,
        coordinationFactory: coordination,
        isClosed: () => false,
        memberCli: (_, __) => CliTool.cursor,
        onBeforeTurnEnded: (_, __) {
          prepared++;
          return gate.future;
        },
        onAfterTurnEnded: (_, __) => ended = true,
      );

      shell.session.activityTracker.latchBootFrameReadyForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      );
      shell.session.markUserTurnStarted();
      watch.tick();
      shell.simulateQuietGap();
      watch.tick();
      await Future<void>.delayed(Duration.zero);

      expect(prepared, 1);
      expect(ended, isFalse);
      expect(shell.session.userTurnActive, isTrue);

      // A later quiet tick must not start a second preparation.
      watch.tick();
      await Future<void>.delayed(Duration.zero);
      expect(prepared, 1);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ended, isTrue);
      expect(shell.session.userTurnActive, isFalse);
      watch.dispose();
    },
  );

  test('PTY-quiet does not end turn for Claude (default CLI)', () async {
    final store = ChatTabStore(storage: fakeHomeStorage());
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''),
      cliTeamName: 's1',
    );
    store.registerSession(tab);

    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells['s1'] = shell.session;

    final coordination = TabMemberCoordinationFactory(
      tabStore: store,
      globalPresets: () => const [],
      activeTeam: () => null,
      sessionWorking: SessionWorkingResolver(),
    );
    var turnEnded = false;
    final watch = TabSessionIdleWatch(
      tabStore: store,
      coordinationFactory: coordination,
      isClosed: () => false,
      memberCli: (_, __) => CliTool.claude,
      onAfterTurnEnded: (_, __) => turnEnded = true,
    );

    shell.session.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    shell.session.markUserTurnStarted();
    watch.tick();
    shell.simulateQuietGap();
    watch.tick();
    await Future<void>.delayed(Duration.zero);

    expect(turnEnded, isFalse);
    expect(shell.session.userTurnActive, isTrue);
    watch.dispose();
  });
}
