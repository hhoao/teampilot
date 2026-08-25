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

  test('selectMember bumps memberSelectionVersion in structural signal', () {
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
          display: 'Title',
          createdAt: 1,
        ),
      ],
    );
    cubit.tabStore.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Title', subtitle: ''),
        cliTeamName: 'sess-1',
        selectedMemberId: 'm-lead',
      ),
    );
    workbench.openSession('ws', 'sess-1');

    final before = chatPageStructuralSignal(
      state: cubit.state,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: 'ws',
    );

    cubit.selectMember('m-worker');

    final after = chatPageStructuralSignal(
      state: cubit.state,
      tabStore: cubit.tabStore,
      workbench: workbench,
      tabScopeId: 'ws',
    );

    expect(before.memberSelectionVersion, 0);
    expect(after.memberSelectionVersion, 1);
    expect(before, isNot(equals(after)));
    expect(after.selectedMemberId, 'm-worker');
  });
}
