import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/session_create_request.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/session/session_open_status.dart';
import 'package:teampilot/services/chat/session/session_workbench_view.dart';
import 'package:teampilot/services/chat/session/session_data_store.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/chat/launch/connect/launch_flow.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_scheduler.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_coordinator.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_workspace_index.dart';
import 'package:teampilot/services/chat/launch/session/session_tab_surface_coordinator.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('SessionLaunchCoordinator', () {
    late Workspace workspace;
    late ChatTabStore tabStore;
    late _CoordinatorHost host;
    late _RecordingScheduler scheduler;
    late List<String> openedSessionIds;
    late SessionLaunchCoordinator coordinator;

    setUp(() {
      workspace = Workspace(
        workspaceId: 'workspace-1',
        folders: const [WorkspaceFolder(path: '/workspace')],
        createdAt: 1,
      );
      tabStore = ChatTabStore(storage: fakeHomeStorage());
      tabStore.setActiveWorkspaceId(workspace.workspaceId);
      host = _CoordinatorHost(
        ChatState(workspaces: [workspace]),
        tabStore: tabStore,
      );
      scheduler = _RecordingScheduler();
      openedSessionIds = <String>[];
      final surface = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
        onSessionTabOpened:
            (workspaceId, sessionId, {preview = false, activate = true}) {
              openedSessionIds.add(sessionId);
            },
      );
      coordinator = SessionLaunchCoordinator(
        host: host,
        tabStore: tabStore,
        tabSurface: surface,
        scheduler: scheduler,
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: host.state.workspaces,
          sessions: host.state.sessions,
          usesPosixPaths: false,
        ),
      );
    });

    tearDown(() => host.sessionRuntime.disposeIdleWatch());

    test('create surfaces provisional tab before async connection', () async {
      final request = SessionCreateRequest(
        workspace: workspace,
        isPersonal: true,
        fixedSessionId: 'session-create',
      );

      final status = await coordinator.createAndOpen(request);

      expect(status, SessionOpenStatus.opened);
      expect(openedSessionIds, contains('session-create'));
      expect(tabStore.getOpenTabBySessionId('session-create'), isNotNull);
      expect(host.snapshotSessionIds, contains('session-create'));
      expect(scheduler.jobs, hasLength(1));
      final job = scheduler.jobs.single;
      expect(job.reason, LaunchReason.create);
      expect(job.sessionId, 'session-create');
      expect(job.workspace, same(workspace));
      expect(host.podViews['session-create'], SessionWorkbenchView.terminal);
    });

    test('create persists the runtime-expanded roster for replicas', () async {
      const team = TeamProfile(
        id: 'team-replicas',
        name: 'Replicas',
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
      );

      final status = await coordinator.createAndOpen(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: false,
          team: team,
          member: team.members.first,
          fixedSessionId: 'session-replicas',
        ),
      );

      expect(status, SessionOpenStatus.opened);
      expect(
        scheduler.jobs.single.request.persistParams!.rosterMembers.map(
          (member) => member.id,
        ),
        orderedEquals(['team-lead', 'builder-0', 'builder-1']),
      );
    });

    test('history-only open surfaces a tab without enqueueing a job', () async {
      final session = _session('session-history', workspace);

      final status = await coordinator.open(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          connectImmediately: false,
        ),
      );

      expect(status, SessionOpenStatus.opened);
      expect(openedSessionIds, contains(session.sessionId));
      expect(tabStore.getOpenTabBySessionId(session.sessionId), isNotNull);
      expect(scheduler.jobs, isEmpty);
    });

    test(
      'deferred team open enqueues preparation without shell connect',
      () async {
        const member = TeamMemberConfig(id: 'team-lead', name: 'Lead');
        const team = TeamProfile(
          id: 'team-1',
          name: 'Team',
          teamMode: TeamMode.mixed,
          members: [member],
        );
        final session = AppSession(
          sessionId: 'session-team-deferred',
          workspaceId: workspace.workspaceId,
          folders: workspace.folders,
          sessionTeam: team.id,
          cliTeamName: team.id,
          createdAt: 1,
          updatedAt: 1,
        );

        final status = await coordinator.open(
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            team: team,
            member: member,
            connectImmediately: false,
          ),
        );

        expect(status, SessionOpenStatus.opened);
        expect(openedSessionIds, contains(session.sessionId));
        expect(scheduler.jobs, hasLength(1));
        expect(scheduler.jobs.single.connectShell, isFalse);
        expect(scheduler.jobs.single.team, same(team));
        expect(scheduler.jobs.single.member, same(member));
        expect(scheduler.waitForCompletionValues.single, isFalse);
      },
    );

    test('immediate open enqueues exactly one job', () async {
      final session = _session('session-open', workspace);

      final status = await coordinator.open(
        SessionOpenRequest(session: session, workspace: workspace),
      );

      expect(status, SessionOpenStatus.opened);
      expect(scheduler.jobs, hasLength(1));
      expect(scheduler.jobs.single.reason, LaunchReason.openExisting);
      expect(scheduler.jobs.single.session, same(session));
    });

    test('existing tab is reused with the expected generation', () async {
      final session = _session('session-reuse', workspace);
      final reused = ChatTab(
        info: ChatTabInfo(
          id: session.sessionId,
          title: 'Existing',
          subtitle: '/workspace',
        ),
        cliTeamName: '',
        workspaceId: workspace.workspaceId,
      )..persistedSession = session;
      tabStore.registerSession(reused);

      final status = await coordinator.open(
        SessionOpenRequest(session: session, workspace: workspace),
      );

      expect(status, SessionOpenStatus.opened);
      expect(tabStore.getOpenTabBySessionId(session.sessionId), same(reused));
      expect(openedSessionIds, [session.sessionId]);
      expect(scheduler.jobs, hasLength(1));
      expect(scheduler.jobs.single.sessionId, reused.info.id);
      expect(scheduler.jobs.single.generation, 1);
    });

    test('retry open records the retry launch reason', () async {
      final session = _session('session-retry', workspace);

      await coordinator.open(
        SessionOpenRequest(session: session, workspace: workspace),
        reason: LaunchReason.retry,
      );

      expect(scheduler.jobs.single.reason, LaunchReason.retry);
    });

    test(
      'SSH reconnect replaces queued work with one job per request',
      () async {
        final session = _session('session-ssh', workspace);
        final tab = ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'SSH',
            subtitle: '/workspace',
          ),
          cliTeamName: '',
          workspaceId: workspace.workspaceId,
        )..persistedSession = session;
        tabStore.registerSession(tab);

        await coordinator.reconnectTab(tab.info.id, [
          SessionOpenRequest(session: session, workspace: workspace),
        ]);

        expect(scheduler.cancelledSessionIds, [tab.info.id]);
        expect(scheduler.jobs, hasLength(1));
        expect(scheduler.jobs.single.reason, LaunchReason.sshReconnect);
        expect(scheduler.jobs.single.generation, 1);
        expect(scheduler.jobs.single.propagateErrors, isTrue);
        expect(scheduler.waitForCompletionValues.single, isTrue);
      },
    );

    test(
      'SSH reconnect waits for scheduler completion and propagates failure',
      () async {
        final session = _session('session-ssh-fail', workspace);
        final tab = ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'SSH',
            subtitle: '/workspace',
          ),
          cliTeamName: '',
          workspaceId: workspace.workspaceId,
        )..persistedSession = session;
        tabStore.registerSession(tab);
        final entered = Completer<void>();
        final release = Completer<void>();
        scheduler
          ..entered = entered
          ..release = release
          ..error = StateError('connect failed');

        final reconnect = coordinator.reconnectTab(tab.info.id, [
          SessionOpenRequest(session: session, workspace: workspace),
        ]);
        var completed = false;
        final observed = reconnect.then<void>(
          (_) => completed = true,
          onError: (_) => completed = true,
        );
        await entered.future;
        await pumpEventQueue();

        expect(completed, isFalse);
        release.complete();
        await expectLater(reconnect, throwsA(isA<StateError>()));
        await observed;
        expect(scheduler.waitForCompletionValues.single, isTrue);
      },
    );

    test('SSH reconnect executes each affected member exactly once', () async {
      final members = const [
        TeamMemberConfig(id: 'lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder'),
      ];
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: members,
        teamMode: TeamMode.native,
      );
      final session = AppSession(
        sessionId: 'session-ssh-batch',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        sessionTeam: team.id,
        members: const [
          SessionMemberBinding(rosterMemberId: 'lead', taskId: 'task-lead'),
          SessionMemberBinding(
            rosterMemberId: 'builder',
            taskId: 'task-builder',
          ),
        ],
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(
          id: 'session-ssh-batch',
          title: 'SSH',
          subtitle: '/workspace',
        ),
        cliTeamName: team.id,
        workspaceId: workspace.workspaceId,
      )..persistedSession = session;
      tabStore.registerSession(tab);

      late SessionConnectScheduler batchScheduler;
      final executed = <String>[];
      final executor = _ReconnectBatchExecutor(
        team: team,
        scheduler: () => batchScheduler,
        executed: executed,
      );
      batchScheduler = SessionConnectScheduler(
        executor: executor,
        postFrame: (callback) => callback(),
        isJobValid: (_) => true,
        listener: const NoopLaunchFlowListener(),
      );
      final surface = SessionTabSurfaceCoordinator(
        host: host,
        tabStore: tabStore,
      );
      final batchCoordinator = SessionLaunchCoordinator(
        host: host,
        tabStore: tabStore,
        tabSurface: surface,
        scheduler: batchScheduler,
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: host.state.workspaces,
          sessions: host.state.sessions,
          usesPosixPaths: false,
        ),
      );

      await batchCoordinator.reconnectTab(tab.info.id, [
        for (final member in members)
          SessionOpenRequest(
            session: session,
            workspace: workspace,
            team: team,
            member: member,
          ),
      ]);

      expect(executed, ['lead', 'builder']);
    });
  });
}

AppSession _session(String id, Workspace workspace) => AppSession(
  sessionId: id,
  workspaceId: workspace.workspaceId,
  folders: workspace.folders,
  createdAt: 1,
  updatedAt: 1,
);

class _RecordingScheduler implements SessionConnectSchedulerPort {
  final jobs = <SessionConnectJob>[];
  final cancelledSessionIds = <String>[];
  final waitForCompletionValues = <bool>[];
  Completer<void>? entered;
  Completer<void>? release;
  Object? error;

  @override
  Future<void> enqueue(
    SessionConnectJob job, {
    bool waitForCompletion = false,
  }) async {
    jobs.add(job);
    waitForCompletionValues.add(waitForCompletion);
    entered?.complete();
    if (waitForCompletion) {
      await release?.future;
      final failure = error;
      if (failure != null) throw failure;
    }
  }

  @override
  void cancelForSession(String sessionId) {
    cancelledSessionIds.add(sessionId);
  }
}

class _ReconnectBatchExecutor implements SessionConnectExecutorPort {
  _ReconnectBatchExecutor({
    required this.team,
    required this.scheduler,
    required this.executed,
  });

  final TeamProfile team;
  final SessionConnectScheduler Function() scheduler;
  final List<String> executed;

  @override
  Future<void> execute(SessionConnectJob job) async {
    executed.add(job.memberId);
    if (!shouldFanOutRemainingMembers(job, team: team)) return;
    for (final member in team.members) {
      if (member.id == job.memberId) continue;
      await scheduler().enqueue(
        SessionConnectJob(
          session: job.session,
          request: SessionOpenRequest(
            session: job.session,
            workspace: job.workspace,
            team: team,
            member: member,
          ),
          generation: job.generation,
          workspace: job.workspace,
          team: team,
          member: member,
          reason: LaunchReason.restore,
        ),
        waitForCompletion: true,
      );
    }
  }
}

class _CoordinatorHost implements SessionLaunchHost {
  _CoordinatorHost(this.state, {required this.tabStore})
    : lifecycle = SessionLifecycleService(storage: fakeHomeStorage()),
      dataStore = SessionDataStore(storage: fakeHomeStorage()),
      sessionRuntime = TabSessionRuntimeCoordinator(
        tabStore: tabStore,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => null,
        isClosed: () => false,
      );

  ChatState state;

  @override
  final ChatTabStore tabStore;

  @override
  final SessionLifecycleService lifecycle;

  @override
  final SessionDataStore dataStore;

  @override
  final TabSessionRuntimeCoordinator sessionRuntime;

  final podViews = <String, SessionWorkbenchView>{};
  final connecting = <String>{};

  Iterable<String> get snapshotSessionIds =>
      state.sessions.map((session) => session.sessionId);

  @override
  bool get isClosed => false;

  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
    workspaces: state.workspaces,
    sessions: state.sessions,
    visibleWorkspaces: state.visibleWorkspaces,
    visibleSessions: state.visibleSessions,
  );

  @override
  void appendSessionSnapshot(AppSession session) {
    state = state.copyWith(sessions: [...state.sessions, session]);
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    state = state.copyWith(
      sessions: [
        for (final existing in state.sessions)
          if (existing.sessionId == session.sessionId) session else existing,
      ],
    );
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    state = state.copyWith(
      sessions: state.sessions
          .where((session) => session.sessionId != sessionId)
          .toList(),
    );
  }

  @override
  void assignSelectedMember(ChatTab tab, String memberId) {
    tab.selectedMemberId = memberId;
  }

  @override
  bool isSessionConnecting(String sessionId) => connecting.contains(sessionId);

  @override
  void beginSessionConnect(String sessionId) => connecting.add(sessionId);

  @override
  void finishSessionConnect(String sessionId) => connecting.remove(sessionId);

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {
    podViews[sessionId] = view;
  }

  @override
  void refreshActiveWorkspaceTabs() {}

  @override
  void updateTabRunning(String tabId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
