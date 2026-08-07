import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
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
        tabStore: tabStore,
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

    tearDown(() {
      host.sessionRuntime.disposeIdleWatch();
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
        expect(host.podViews['sess-1'], SessionWorkbenchView.terminal);
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
        expect(host.podViews['sess-1'], isNull);
        expect(host.beginConnectIds, ['sess-1']);
      },
    );
  });

  group('SessionTabSurfaceCoordinator.surfaceNewTab', () {
    late ChatTabStore tabStore;
    late _FakeHost host;
    late SessionTabSurfaceCoordinator coordinator;
    late AppSession session;
    late Workspace workspace;

    setUp(() {
      tabStore = ChatTabStore();
      tabStore.setActiveWorkspace('ws-1');
      workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/tmp')],
        createdAt: 1,
      );
      session = AppSession(
        sessionId: 'sess-new',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/tmp')],
        createdAt: 1,
        updatedAt: 1,
      );
      host = _FakeHost(const ChatState(), tabStore: tabStore);
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
        state: () => host.state,
        workspaceById: (_) => workspace,
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

    tearDown(() {
      host.sessionRuntime.disposeIdleWatch();
    });

    test(
      'connectImmediately defaults to Terminal workbench view',
      () {
        final status = coordinator.surfaceNewTab(
          request: SessionOpenRequest(
            session: session,
            workspace: workspace,
            connectImmediately: true,
          ),
          session: session,
        );

        expect(status, SessionOpenStatus.opened);
        final tab = tabStore.openTabBySessionId('sess-new');
        expect(tab, isNotNull);
        expect(host.podViews['sess-new'], SessionWorkbenchView.terminal);
      },
    );

    test(
      'preserveWorkbenchView keeps Chat on new-tab create',
      () {
        final status = coordinator.surfaceNewTab(
          request: SessionOpenRequest(
            session: session,
            workspace: workspace,
            connectImmediately: true,
            preserveWorkbenchView: true,
          ),
          session: session,
        );

        expect(status, SessionOpenStatus.opened);
        final tab = tabStore.openTabBySessionId('sess-new');
        expect(tab, isNotNull);
        expect(host.podViews['sess-new'], isNull);
        expect(host.beginConnectIds, ['sess-new']);
      },
    );
  });
}

class _FakeHost implements SessionLaunchHost {
  _FakeHost(this.state, {required ChatTabStore tabStore})
    : sessionRuntime = TabSessionRuntimeCoordinator(
        tabStore: tabStore,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => null,
        isClosed: () => false,
      );

  @override
  ChatState state;
  final beginConnectIds = <String>[];

  @override
  final TabSessionRuntimeCoordinator sessionRuntime;

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

  /// Records pod view writes so tests can assert the canonical source.
  final podViews = <String, SessionWorkbenchView>{};

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {
    podViews[sessionId] = view;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
