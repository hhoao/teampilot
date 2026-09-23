import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/session/session_workbench_view.dart';
import 'package:teampilot/services/chat/session/session_data_store.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/chat/launch/connect/launch_generation_store.dart';
import 'package:teampilot/services/chat/launch/session/session_tab_surface_coordinator.dart';

import '../../../support/fake_terminal_session.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  group('SessionTabSurfaceCoordinator.surfaceExistingTab', () {
    late ChatTabStore tabStore;
    late ChatTab existing;
    late _FakeHost host;
    late LaunchGenerationStore generations;
    late SessionTabSurfaceCoordinator coordinator;
    late AppSession session;
    late List<
      ({String workspaceId, String sessionId, bool preview, bool activate})
    >
    openedCalls;

    setUp(() {
      tabStore = ChatTabStore(storage: fakeHomeStorage());
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
      host = _FakeHost(const ChatState(), tabStore: tabStore);
      openedCalls = [];
      generations = LaunchGenerationStore();
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
        generations: generations,
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

    test('owns launch generation on the store, not ChatTab', () {
      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(session: session, connectImmediately: true),
        existing: existing,
        workspace: null,
        connect: true,
      );

      expect(result.generation, 1);
      expect(generations.current('sess-1'), 1);
    });

    test('does not bump generation when the session is already connecting', () {
      host.connectingSessionIds.add('sess-1');
      generations.bump('sess-1');

      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(session: session, connectImmediately: true),
        existing: existing,
        workspace: null,
        connect: true,
      );

      expect(result.generation, 1);
      expect(generations.current('sess-1'), 1);
    });

    test('connectImmediately defaults to Terminal workbench view', () {
      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(session: session, connectImmediately: true),
        existing: existing,
        workspace: null,
        connect: true,
      );

      expect(result.tab, same(existing));
      expect(result.connect, isTrue);
      expect(host.podViews['sess-1'], SessionWorkbenchView.terminal);
    });

    test('Chat continue connect preserves Chat when preserveWorkbenchView', () {
      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(
          session: session,
          connectImmediately: true,
          preserveWorkbenchView: true,
        ),
        existing: existing,
        workspace: null,
        connect: true,
      );

      expect(result.tab, same(existing));
      expect(result.connect, isTrue);
      expect(host.podViews['sess-1'], isNull);
      expect(host.beginConnectIds, isEmpty);
    });

    test('feeds onSessionTabOpened once when reusing an existing tab', () {
      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(session: session, connectImmediately: true),
        existing: existing,
        workspace: null,
        connect: true,
      );

      expect(result.generation, generations.current('sess-1'));
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-1',
          preview: false,
          activate: true,
        ),
      ]);
    });

    test('feeds preview: true when history-reviewing an existing tab', () {
      final result = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(
          session: session,
          connectImmediately: false,
        ),
        existing: existing,
        workspace: null,
        connect: false,
      );

      expect(result.connect, isFalse);
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-1',
          preview: true,
          activate: true,
        ),
      ]);
    });

    test(
      'does not suppress a distinct member while another member connects',
      () {
        final teamSession = AppSession(
          sessionId: 'sess-1',
          workspaceId: 'ws-1',
          sessionTeam: 'team-1',
          createdAt: 1,
        );
        existing.persistedSession = teamSession;
        existing.membersPendingConnect.add('member-a');
        host.connectingSessionIds.add('sess-1');

        final result = coordinator.surfaceExistingTab(
          request: SessionOpenRequest(
            session: teamSession,
            member: const TeamMemberConfig(id: 'member-b', name: 'Member B'),
            connectImmediately: true,
          ),
          existing: existing,
          workspace: null,
          connect: true,
        );

        expect(result.connect, isTrue);
        expect(existing.membersPendingConnect, contains('member-a'));
      },
    );

    test(
      'reuse of a RUNNING tab pins preview: false even when not connecting',
      () {
        final running = FakeTerminalSession(fs: InMemoryFilesystem());
        running.connect(workingDirectory: '/tmp');
        existing.resumeSession = running;

        final result = coordinator.surfaceExistingTab(
          request: SessionOpenRequest(
            session: session,
            connectImmediately: false,
          ),
          existing: existing,
          workspace: null,
          connect: false,
        );

        expect(result.connect, isFalse);
        expect(openedCalls, [
          (
            workspaceId: 'ws-1',
            sessionId: 'sess-1',
            preview: false,
            activate: true,
          ),
        ]);
      },
    );
  });

  group('SessionTabSurfaceCoordinator.surfaceNewTab', () {
    late ChatTabStore tabStore;
    late _FakeHost host;
    late LaunchGenerationStore generations;
    late SessionTabSurfaceCoordinator coordinator;
    late AppSession session;
    late Workspace workspace;
    late List<
      ({String workspaceId, String sessionId, bool preview, bool activate})
    >
    openedCalls;

    setUp(() {
      tabStore = ChatTabStore(storage: fakeHomeStorage());
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
      generations = LaunchGenerationStore();
      coordinator = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
        generations: generations,
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

    test('owns launch generation on the store, not ChatTab', () {
      final result = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: true,
        ),
        session: session,
        workspace: workspace,
        connect: true,
      );

      expect(result.generation, 1);
      expect(generations.current('sess-new'), 1);
    });

    test('connectImmediately defaults to Terminal workbench view', () {
      final result = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: true,
        ),
        session: session,
        workspace: workspace,
        connect: true,
      );

      expect(result.session, same(session));
      expect(result.connect, isTrue);
      final tab = tabStore.getOpenTabBySessionId('sess-new');
      expect(tab, isNotNull);
      expect(host.podViews['sess-new'], SessionWorkbenchView.terminal);
    });

    test('preserveWorkbenchView keeps Chat on new-tab create', () {
      final result = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: true,
          preserveWorkbenchView: true,
        ),
        session: session,
        workspace: workspace,
        connect: true,
      );

      expect(result.tab.info.id, session.sessionId);
      final tab = tabStore.getOpenTabBySessionId('sess-new');
      expect(tab, isNotNull);
      expect(result.connect, isTrue);
      expect(host.podViews['sess-new'], isNull);
      expect(host.beginConnectIds, isEmpty);
    });

    test('feeds onSessionTabOpened once with the tab id and activate', () {
      final result = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: true,
        ),
        session: session,
        workspace: workspace,
        connect: true,
      );

      expect(result.generation, generations.current('sess-new'));
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
      final result = coordinator.surfaceNewTab(
        request: SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: false,
        ),
        session: session,
        workspace: workspace,
        connect: false,
      );

      expect(result.connect, isFalse);
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

  ChatState state;

  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
    workspaces: state.workspaces,
    sessions: state.sessions,
    visibleWorkspaces: state.visibleWorkspaces,
    visibleSessions: state.visibleSessions,
  );

  final beginConnectIds = <String>[];
  final connectingSessionIds = <String>{};

  @override
  final TabSessionRuntimeCoordinator sessionRuntime;

  @override
  bool get isClosed => false;

  void applyState(ChatState next) => state = next;

  @override
  void refreshActiveWorkspaceTabs() {}

  @override
  void beginSessionConnect(String sessionId) {
    beginConnectIds.add(sessionId);
  }

  @override
  void assignSelectedMember(ChatTab tab, String memberId) {
    tab.selectedMemberId = memberId;
  }

  /// Records pod view writes so tests can assert the canonical source.
  final podViews = <String, SessionWorkbenchView>{};

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {
    podViews[sessionId] = view;
  }

  @override
  bool isSessionConnecting(String sessionId) =>
      connectingSessionIds.contains(sessionId);

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
