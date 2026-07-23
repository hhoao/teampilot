import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
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
    cubit.tabStore.append(
      ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Old title', subtitle: ''),
        cliTeamName: 'sess-1',
      ),
    );
    cubit.tabStore.setNewChatActive('ws', false);
    cubit.refreshActiveWorkspaceTabs();

    final before = chatPageStructuralSignal(
      state: cubit.state,
      tabStore: cubit.tabStore,
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
      tabScopeId: 'ws',
    );

    expect(before, equals(after));
  });
}
