import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/chat_page_structural_signal.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('rename-only session display keeps structural signal equal', () {
    final cubit = testChatCubit(executableResolver: () => '/bin/true');
    addTearDown(cubit.close);
    final workbench = WorkbenchCubit();
    addTearDown(workbench.close);

    cubit.setActiveWorkspace('ws');
    cubit.ingestWorkspaceSessionSnapshot(
      workspaces: cubit.state.workspaces,
      sessions: [
        AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws',
          folders: const [WorkspaceFolder(path: '/tmp')],
          display: 'Old title',
          createdAt: 1,
        ),
      ],
    );
    cubit.tabStore.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Old title', subtitle: ''),
        cliTeamName: 'sess-1',
      ),
    );
    workbench.openSession('ws', 'sess-1');

    final before = chatPageStructuralSignal(
      state: cubit.state,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: 'ws',
    );

    final session = cubit.state.sessions.first;
    cubit.emit(
      cubit.state.copyWith(
        sessions: [session.copyWith(display: 'Renamed title')],
      ),
    );

    final after = chatPageStructuralSignal(
      state: cubit.state,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: 'ws',
    );

    expect(before, equals(after));
  });

  test(
    'selectMember bump differs even when live tab already holds the new id',
    () {
      // Mirrors ChatPageShell.buildWhen: selectMember mutates ChatTab in place
      // before emit, so both prev/next signals read the same live selectedMemberId.
      // memberSelectionVersion on ChatState must still make the signals unequal.
      final cubit = testChatCubit(executableResolver: () => '/bin/true');
      addTearDown(cubit.close);
      final workbench = WorkbenchCubit();
      addTearDown(workbench.close);

      cubit.setActiveWorkspace('ws');
      cubit.ingestWorkspaceSessionSnapshot(
        workspaces: cubit.state.workspaces,
        sessions: [
          AppSession(
            sessionId: 'sess-1',
            workspaceId: 'ws',
            folders: const [WorkspaceFolder(path: '/tmp')],
            display: 'Team',
            createdAt: 1,
          ),
        ],
      );
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Team', subtitle: ''),
        cliTeamName: 'sess-1',
      )..selectedMemberId = 'lead';
      cubit.tabStore.registerSession(tab);
      workbench.openSession('ws', 'sess-1');

      final previousState = cubit.state;
      expect(previousState.memberSelectionVersion, 0);

      // In-place mutation then version bump — same order as ChatCubit.selectMember.
      tab.selectedMemberId = 'worker';
      cubit.emit(
        cubit.state.copyWith(
          memberSelectionVersion: cubit.state.memberSelectionVersion + 1,
        ),
      );

      final before = chatPageStructuralSignal(
        state: previousState,
        tabStore: cubit.tabStore,
        workbench: workbench,
        tabScopeId: 'ws',
      );
      final after = chatPageStructuralSignal(
        state: cubit.state,
        tabStore: cubit.tabStore,
        workbench: workbench,
        tabScopeId: 'ws',
      );

      expect(before.selectedMemberId, 'worker');
      expect(after.selectedMemberId, 'worker');
      expect(before, isNot(equals(after)));
    },
  );
}
