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
      tabStore.setActiveWorkspaceId('ws-1');
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
      tabStore.registerSession(existing);
      host = _FakeHost(
        const ChatState(),
        tabStore: tabStore,
      );
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
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
          existing: existing,
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
          existing: existing,
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
    late List<({String workspaceId, String sessionId, bool preview, bool activate})>
        openedCalls;

    setUp(() {
      tabStore = ChatTabStore();
      tabStore.setActiveWorkspaceId('ws-1');
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
      openedCalls = [];
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
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
        onSessionTabOpened:
            (workspaceId, sessionId, {preview = false, activate = true}) {
          openedCalls.add((
            workspaceId: workspaceId,
            sessionId: sessionId,
            preview: preview,
            activate: activate,
          ));
        },
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

    test('feeds onSessionTabOpened once with the tab id and activate', () {
      final status = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: true,
        ),
        session: session,
      );

      expect(status, SessionOpenStatus.opened);
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-new',
          preview: false,
          activate: true,
        ),
      ]);
    });

    test('feeds preview: true when connectImmediately is false', () {
      final status = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: false,
        ),
        session: session,
      );

      expect(status, SessionOpenStatus.opened);
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-new',
          preview: true,
          activate: true,
        ),
      ]);
    });
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
  bool isSessionConnecting(String sessionId) => false;

  @override
  bool get hasConnectingSession => false;

  @override
  void setMaterializingInFlight(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
