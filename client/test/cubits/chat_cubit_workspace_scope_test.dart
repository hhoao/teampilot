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
    test('setActiveWorkspace swaps the visible tab list', () {
      final cubit = _cubit();
      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      // Mirror into state the way the launch flow does:
      cubit.refreshActiveWorkspaceTabs();
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);

      cubit.setActiveWorkspace('B');
      expect(cubit.state.tabs, isEmpty);

      cubit.setActiveWorkspace('A');
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);
      addTearDown(cubit.close);
    });

    test('switching workspaces preserves each workspace active index', () {
      final cubit = _cubit();
      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.append(_tab('a3'));
      cubit.refreshActiveWorkspaceTabs();
      cubit.selectTab(2);
      expect(cubit.state.activeTabIndex, 2);

      cubit.setActiveWorkspace('B');
      cubit.setActiveWorkspace('A');
      expect(cubit.state.activeTabIndex, 2);
      addTearDown(cubit.close);
    });

    test(
      'openTabCountForWorkspace counts only session tabs in that bucket',
      () {
        final cubit = _cubit();
        cubit.setActiveWorkspace('A');
        cubit.tabStore.append(_tab('sess-1'));
        cubit.tabStore.append(_tab('local-team'));
        cubit.setActiveWorkspace('B');
        cubit.tabStore.append(_tab('sess-2'));
        expect(cubit.openTabCountForWorkspace('A'), 1);
        expect(cubit.openTabCountForWorkspace('B'), 1);
        addTearDown(cubit.close);
      },
    );

    test(
      'activateWorkspaceTab updates tab bucket and session scope together',
      () {
        final cubit = _cubit();
        addTearDown(cubit.close);

        cubit.setActiveWorkspace('A');
        cubit.tabStore.append(_tab('a1'));
        cubit.refreshActiveWorkspaceTabs();
        expect(cubit.state.tabs, isNotEmpty);

        cubit.activateWorkspaceTab(
          workspaceTabKey: 'B',
          scopeSessionsToSelectedTeam: true,
          selectedTeamId: 'team-1',
        );

        expect(cubit.tabStore.activeWorkspaceId, 'B');
        expect(cubit.state.tabs, isEmpty);
      },
    );

    test('isMemberRunning finds shell on non-active workspace tab', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('a-session'));
      cubit.refreshActiveWorkspaceTabs();

      cubit.setActiveWorkspace('B');
      final bTab = _tab('b-session');
      const shellId = 'b-shell';
      bTab.memberShells[shellId] = _RunningShell();
      cubit.tabStore.append(bTab);
      cubit.refreshActiveWorkspaceTabs();

      cubit.setActiveWorkspace('A');
      expect(cubit.tabStore.activeWorkspaceId, 'A');
      expect(
        cubit.isMemberRunning(sessionId: 'b-session', memberId: shellId),
        isTrue,
      );
    });

    test('closeTab disposes history seats for that session', () async {
      final cubit = _cubit();
      addTearDown(cubit.close);

      final disposed = <String>[];
      cubit.onHistorySeatsDispose = disposed.add;

      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('sess-close'));
      cubit.refreshActiveWorkspaceTabs();

      cubit.closeTab(0);
      await drainPendingAsyncWork();

      expect(disposed, ['sess-close']);
    });
  });
}
