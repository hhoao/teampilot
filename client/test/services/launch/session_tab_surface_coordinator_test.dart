import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/session_tab_surface_coordinator.dart';

void main() {
  group('SessionTabSurfaceCoordinator.surfaceExistingTab', () {
    late ChatTabStore tabStore;
    late ChatTab existing;
    late _FakeHost host;
    late SessionTabSurfaceCoordinator coordinator;
    late AppSession session;

    setUp(() {
      tabStore = ChatTabStore();
      tabStore.setActiveWorkspace('ws-1');
      session = AppSession(
        sessionId: 'sess-1',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/tmp')],
        createdAt: 1,
        updatedAt: 1,
      );
      existing = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 'Review', subtitle: '/tmp'),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
        workbenchView: SessionWorkbenchView.chat,
      )..persistedSession = session;
      tabStore.append(existing);
      host = _FakeHost(
        ChatState(activeTabIndex: 0, activeSessionId: 'sess-1'),
      );
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
        state: () => host.state,
        workspaceById: (_) => null,
        shouldAutoConnect: (_) => true,
        prepareNewTabConnect:
            ({
              required generation,
              required tab,
              required session,
              required request,
              required workspace,
              required connect,
            }) async {},
        prepareExistingTabConnect:
            ({
              required generation,
              required tab,
              required request,
              required connect,
            }) async {},
        prepareDeferredTeamTab:
            ({
              required generation,
              required tab,
              required session,
              required request,
            }) async {},
      );
    });

    test(
      'connectImmediately defaults to Terminal workbench view',
      () {
        final status = coordinator.surfaceExistingTab(
          request: SessionOpenRequest(
            session: session,
            connectImmediately: true,
          ),
          existingIdx: 0,
        );

        expect(status, SessionOpenStatus.opened);
        expect(existing.workbenchView, SessionWorkbenchView.terminal);
      },
    );

    test(
      'Chat continue connect preserves Chat when preserveWorkbenchView',
      () {
        final status = coordinator.surfaceExistingTab(
          request: SessionOpenRequest(
            session: session,
            connectImmediately: true,
            preserveWorkbenchView: true,
          ),
          existingIdx: 0,
        );

        expect(status, SessionOpenStatus.opened);
        expect(existing.workbenchView, SessionWorkbenchView.chat);
        expect(host.beginConnectIds, ['sess-1']);
      },
    );
  });
}

class _FakeHost implements SessionLaunchHost {
  _FakeHost(this.state);

  @override
  ChatState state;
  final beginConnectIds = <String>[];

  @override
  bool get isClosed => false;

  @override
  void applyState(ChatState next) => state = next;

  @override
  void refreshActiveWorkspaceTabs() {}

  @override
  void beginSessionConnect(String sessionId) {
    beginConnectIds.add(sessionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
