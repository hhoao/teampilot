import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import '../support/post_frame_test_harness.dart';

ChatCubit _cubit() => ChatCubit(
  executableResolver: () => '/bin/true',
  automationRepository: testAutomationRepository(),
);

ChatTab _tab(String id) => ChatTab(
  info: ChatTabInfo(id: id, title: id, subtitle: ''),
  cliTeamName: id,
);

class _RunningShell extends TerminalSession {
  _RunningShell() : super(executable: '/bin/true');

  @override
  bool get isRunning => true;
}

void main() {
  group('ChatCubit workspace scoping', () {
    test('setActiveWorkspace switches the foreground workspace', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('A');
      cubit.tabStore.registerSession(_tab('a1'));
      expect(cubit.tabStore.activeWorkspaceId, 'A');
      expect(cubit.tabStore.tabsForWorkspace('A').map((t) => t.info.id),
          ['a1']);

      cubit.setActiveWorkspace('B');
      expect(cubit.tabStore.activeWorkspaceId, 'B');
      // The registry is global; per-workspace scoping filters by workspaceId.
      expect(cubit.tabStore.tabsForWorkspace('A').map((t) => t.info.id),
          ['a1']);

      cubit.setActiveWorkspace('A');
      expect(cubit.tabStore.activeWorkspaceId, 'A');
    });

    test('switching workspaces preserves each workspace runtime set', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('A');
      cubit.tabStore.registerSession(_tab('a1'));
      cubit.tabStore.registerSession(_tab('a2'));
      cubit.setActiveWorkspace('B');
      cubit.tabStore.registerSession(_tab('b1'));

      expect(cubit.tabStore.sessionsForWorkspace('A'), ['a1', 'a2']);
      expect(cubit.tabStore.sessionsForWorkspace('B'), ['b1']);
    });

    test(
      'openTabCountForWorkspace counts only session tabs in that workspace',
      () {
        final cubit = _cubit();
        addTearDown(cubit.close);

        cubit.setActiveWorkspace('A');
        cubit.tabStore.registerSession(_tab('sess-1'));
        cubit.tabStore.registerSession(_tab('local-team'));
        cubit.setActiveWorkspace('B');
        cubit.tabStore.registerSession(_tab('sess-2'));
        expect(cubit.openTabCountForWorkspace('A'), 1);
        expect(cubit.openTabCountForWorkspace('B'), 1);
      },
    );

    test(
      'activateWorkspaceTab updates active workspace and scope together',
      () {
        final cubit = _cubit();
        addTearDown(cubit.close);

        cubit.setActiveWorkspace('A');
        cubit.tabStore.registerSession(_tab('a1'));
        expect(cubit.tabStore.activeWorkspaceId, 'A');

        cubit.activateWorkspaceTab(
          workspaceTabKey: 'B',
          scopeSessionsToSelectedTeam: true,
          selectedTeamId: 'team-1',
        );

        expect(cubit.tabStore.activeWorkspaceId, 'B');
      },
    );

    test('isMemberRunning finds shell on non-active workspace tab', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('A');
      cubit.tabStore.registerSession(_tab('a-session'));

      cubit.setActiveWorkspace('B');
      final bTab = _tab('b-session');
      const shellId = 'b-shell';
      bTab.memberShells[shellId] = _RunningShell();
      cubit.tabStore.registerSession(bTab);

      cubit.setActiveWorkspace('A');
      expect(cubit.tabStore.activeWorkspaceId, 'A');
      expect(
        cubit.isMemberRunning(sessionId: 'b-session', memberId: shellId),
        isTrue,
      );
    });

    test('closeSessionTab disposes history seats for that session', () async {
      final cubit = _cubit();
      addTearDown(cubit.close);

      final disposed = <String>[];
      cubit.onHistorySeatsDispose = disposed.add;

      cubit.setActiveWorkspace('A');
      cubit.tabStore.registerSession(_tab('sess-close'));

      cubit.closeSessionTab('sess-close');
      await drainPendingAsyncWork();

      expect(disposed, ['sess-close']);
    });
  });
}
