import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_create_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/connect/member_connect_stage.dart';
import 'package:teampilot/services/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/launch/connect/session_connect_scheduler.dart';
import 'package:teampilot/services/launch/session/session_default_materializer.dart';
import 'package:teampilot/services/launch/session/session_launch_coordinator.dart';
import 'package:teampilot/services/launch/session/session_launch_workspace_index.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'openMemberTab enqueues a job consumed by the unified executor',
    () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/local')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: 'sess-1',
        workspaceId: workspace.workspaceId,
        sessionTeam: 'team-1',
        members: const [
          SessionMemberBinding(rosterMemberId: 'm1', taskId: 'task-m1'),
        ],
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Team', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: workspace.workspaceId,
      )..persistedSession = session;
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        members: const [TeamMemberConfig(id: 'm1', name: 'Member')],
      );
      final tabStore = ChatTabStore(storage: fakeHomeStorage())
        ..setActiveWorkspaceId(workspace.workspaceId)
        ..registerSession(tab);
      final host = _ImmediateFrameHost(tabStore);
      final launchIntent = _NoopLaunchIntent();
      final materializer = SessionDefaultMaterializer(
        host: host,
        coordinator: launchIntent,
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: [workspace],
          sessions: [session],
          usesPosixPaths: true,
        ),
        isTabsEmpty: () => false,
        activeBucketKey: () => workspace.workspaceId,
      );
      final executor = _RecordingExecutor();
      final scheduler = SessionConnectScheduler(
        executor: executor,
        postFrame: host.postFrameScheduler,
        isJobValid: (_) => true,
        onBegin: (_) {},
        onFinish: (_) {},
      );
      final repository = SessionRepository(storage: fakeHomeStorage());
      final stage = MemberConnectStage(
        host: host,
        tabStore: tabStore,
        state: () => host.state,
        materializer: materializer,
        coordinator: launchIntent,
        scheduler: scheduler,
        sessionForMemberConnect: (_, __) => session,
        disconnectSession: () {},
        ensureSession: (_) => null,
        appendLocalTab: (_, {required emitChange}) => tab,
        ensureActiveSessionTab: (_, {required emitChange}) => tab,
        resetTeamConfigValidationSurface: () {},
        scheduleTeamConfigValidation: (_) async {},
        activeTab: () => tab,
        autoLaunchAllMembersOnConnect: () => false,
        workspaceById: (id) => id == workspace.workspaceId ? workspace : null,
      );

      await stage.openMemberTab(
        team,
        team.members.single,
        repo: repository,
        scheduleTeamConfigValidation: false,
      );
      await pumpEventQueue();

      expect(executor.jobs.single.memberId, 'm1');
      expect(executor.jobs.single.reason, LaunchReason.memberSelected);
      expect(executor.jobs.single.request.repo, same(repository));
    },
  );

  test(
    'launchAllMembers resolves session pod placement in binding order',
    () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/local')],
        createdAt: 1,
      );
      final session = AppSession(
        sessionId: 'sess-1',
        workspaceId: workspace.workspaceId,
        sessionTeam: 'team-1',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'builder-1',
            typeId: 'builder',
            taskId: 'task-builder-1',
          ),
          SessionMemberBinding(
            rosterMemberId: 'lead',
            typeId: 'lead',
            taskId: 'task-lead',
          ),
          SessionMemberBinding(
            rosterMemberId: 'builder-0',
            typeId: 'builder',
            taskId: 'task-builder-0',
          ),
        ],
        createdAt: 1,
      );
      final tab = ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'Team', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: workspace.workspaceId,
      )..persistedSession = session;
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        members: const [
          TeamMemberConfig(id: 'lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
      );
      final tabStore = ChatTabStore(storage: fakeHomeStorage())
        ..setActiveWorkspaceId(workspace.workspaceId)
        ..registerSession(tab);
      final host = _ImmediateFrameHost(tabStore);
      final launchIntent = _NoopLaunchIntent();
      final materializer = SessionDefaultMaterializer(
        host: host,
        coordinator: launchIntent,
        workspaceIndex: () => SessionLaunchWorkspaceIndex(
          workspaces: [workspace],
          sessions: [session],
          usesPosixPaths: true,
        ),
        isTabsEmpty: () => false,
        activeBucketKey: () => workspace.workspaceId,
      );
      final executor = _RecordingExecutor();
      final scheduler = SessionConnectScheduler(
        executor: executor,
        postFrame: host.postFrameScheduler,
        isJobValid: (_) => true,
        onBegin: (_) {},
        onFinish: (_) {},
      );
      final stage = MemberConnectStage(
        host: host,
        tabStore: tabStore,
        state: () => host.state,
        materializer: materializer,
        coordinator: launchIntent,
        scheduler: scheduler,
        sessionForMemberConnect: (_, __) => session,
        disconnectSession: () {},
        ensureSession: (_) => null,
        appendLocalTab: (_, {required emitChange}) => tab,
        ensureActiveSessionTab: (_, {required emitChange}) => tab,
        resetTeamConfigValidationSurface: () {},
        scheduleTeamConfigValidation: (_) async {},
        activeTab: () => tab,
        autoLaunchAllMembersOnConnect: () => false,
        workspaceById: (id) => id == workspace.workspaceId ? workspace : null,
      );

      await stage.launchAllMembers(team);
      await pumpEventQueue();

      expect(
        executor.jobs.map((job) => job.memberId),
        orderedEquals(['builder-1', 'lead', 'builder-0']),
      );
      expect(
        executor.jobs.map((job) => job.member!.name),
        orderedEquals(['Builder #1', 'Lead', 'Builder #0']),
      );
      expect(
        executor.jobs.map((job) => job.member!.replicas),
        orderedEquals([1, 1, 1]),
      );
      expect(
        executor.jobs.map((job) => job.member!.capabilities.join('|')),
        orderedEquals(['builder', 'lead', 'builder']),
      );
    },
  );
}

class _NoopLaunchIntent implements SessionLaunchIntentPort {
  @override
  Future<SessionOpenStatus> createAndOpen(SessionCreateRequest request) async =>
      SessionOpenStatus.opened;

  @override
  Future<SessionOpenStatus> open(
    SessionOpenRequest request, {
    LaunchReason reason = LaunchReason.openExisting,
    bool waitForCompletion = false,
  }) async => SessionOpenStatus.opened;

  @override
  Future<void> openMember(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) async {}
}

class _RecordingExecutor implements SessionConnectExecutorPort {
  final jobs = <SessionConnectJob>[];

  @override
  Future<void> execute(SessionConnectJob job) async {
    jobs.add(job);
  }
}

class _ImmediateFrameHost implements SessionLaunchHost {
  _ImmediateFrameHost(this.tabStore)
    : lifecycle = SessionLifecycleService(
        storage: fakeHomeStorage(),
        loadPresets: () => const [],
      ),
      state = ChatState();

  @override
  final ChatTabStore tabStore;

  @override
  final SessionLifecycleService lifecycle;

  @override
  ChatState state;

  @override
  PostFrameScheduler get postFrameScheduler =>
      (cb) => cb();

  @override
  bool get hasConnectingSession => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
