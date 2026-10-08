import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/cubits/chat_state.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/session_connect_request.dart';
import 'package:teampilot/services/chat/session/session_create_request.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/session/session_open_status.dart';
import 'package:teampilot/services/chat/session/session_workbench_view.dart';
import 'package:teampilot/services/chat/session/session_data_store.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/connect/member_connect_stage.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_scheduler.dart';
import 'package:teampilot/services/chat/launch/session/session_default_materializer.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_coordinator.dart';
import 'package:teampilot/services/chat/launch/session/session_launch_workspace_index.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  TeamProfile team(TeamMode mode) => TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ],
    cli: CliTool.claude,
    teamMode: mode,
  );

  group('shouldLaunchAllMembers', () {
    test('native team launches all members regardless of preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: false,
        ),
        isTrue,
        reason: 'native teams break when members are missing',
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.native),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
    });

    test('mixed team honors the preference', () {
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchAllMembers(
          team: team(TeamMode.mixed),
          autoLaunchAllMembersOnConnect: false,
        ),
        isFalse,
      );
    });
  });

  group('native team connect schedules every valid member', () {
    test(
      'TeamSessionConnect with pref off still launches all members',
      () async {
        final tabStore = ChatTabStore(storage: fakeHomeStorage())
          ..setActiveWorkspaceId('ws-1');
        final workspace = Workspace(
          workspaceId: 'ws-1',
          folders: const [WorkspaceFolder(path: '/proj')],
          createdAt: 1,
          updatedAt: 1,
        );
        final nativeTeam = TeamProfile(
          id: 'team-1',
          name: 'Team',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'builder', name: 'Builder'),
          ],
          cli: CliTool.claude,
        );
        final scheduled = <String>[];

        final stage = _stageForAllMembers(
          tabStore: tabStore,
          workspace: workspace,
          team: nativeTeam,
          autoLaunchAllMembersOnConnect: () => false,
          onScheduleMemberConnect: (member) => scheduled.add(member.id),
        );

        await stage.run(TeamSessionConnect(nativeTeam));

        expect(
          scheduled,
          containsAll(['team-lead', 'builder']),
          reason: 'native connect must schedule every valid member',
        );
      },
    );

    test(
      'mixed team with pref off schedules only via single-member path',
      () async {
        final mixedTeam = TeamProfile(
          id: 'team-1',
          name: 'Team',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'builder', name: 'Builder'),
          ],
          cli: CliTool.claude,
          teamMode: TeamMode.mixed,
        );
        final scheduled = <String>[];

        final stage = _stageForAllMembers(
          tabStore: ChatTabStore(storage: fakeHomeStorage())
            ..setActiveWorkspaceId('ws-1'),
          workspace: Workspace(
            workspaceId: 'ws-1',
            folders: const [WorkspaceFolder(path: '/proj')],
            createdAt: 1,
            updatedAt: 1,
          ),
          team: mixedTeam,
          autoLaunchAllMembersOnConnect: () => false,
          onScheduleMemberConnect: (member) => scheduled.add(member.id),
        );

        await stage.run(TeamSessionConnect(mixedTeam));

        expect(
          scheduled,
          isNot(contains('builder')),
          reason: 'mixed pref-off starts only the selected member',
        );
      },
    );
  });
}

MemberConnectStage _stageForAllMembers({
  required ChatTabStore tabStore,
  required Workspace workspace,
  required TeamProfile team,
  required bool Function() autoLaunchAllMembersOnConnect,
  required void Function(TeamMemberConfig member) onScheduleMemberConnect,
}) {
  final host = _CapturingHost(
    ChatState(workspaces: [workspace]),
    tabStore: tabStore,
  );
  // Register an open session tab for the team so `activeTabsIsEmpty` is false
  // and `_runLaunchAllMembers` takes the `_ensureActiveSessionTab` path
  // (no repository / materialization needed).
  final tab = tabStore.appendLocalTab(team, cliTeamName: 'cli-team-1');
  tab.persistedSession = AppSession(
    sessionId: tab.info.id,
    workspaceId: workspace.workspaceId,
    sessionTeam: team.id,
    members: [
      for (final member in team.members)
        SessionMemberBinding(rosterMemberId: member.id, taskId: member.id),
    ],
    createdAt: 1,
  );
  final coordinator = _NoopLaunchCoordinator();
  final scheduler = _RecordingScheduler(onScheduleMemberConnect);

  final materializer = SessionDefaultMaterializer(
    host: host,
    coordinator: coordinator,
    workspaceIndex: () => SessionLaunchWorkspaceIndex(
      workspaces: host.state.workspaces,
      sessions: host.state.sessions,
      usesPosixPaths: false,
    ),
    isTabsEmpty: () => tabStore.activeTabsIsEmpty,
    activeBucketKey: () => tabStore.activeWorkspaceId,
  );
  return MemberConnectStage(
    host: host,
    tabStore: tabStore,
    state: () => host.stateSnapshot(),
    materializer: materializer,
    coordinator: coordinator,
    scheduler: scheduler,
    sessionForMemberConnect: (_, __) => tab.persistedSession,
    disconnectSession: () {},
    ensureSession: (_) => null,
    appendLocalTab: (_, {required emitChange}) =>
        throw UnsupportedError('unused'),
    ensureActiveSessionTab: (_, {required emitChange}) => tab,
    resetTeamConfigValidationSurface: () {},
    scheduleTeamConfigValidation: (_) async {},
    activeTab: () => host.activeTab,
    autoLaunchAllMembersOnConnect: autoLaunchAllMembersOnConnect,
    workspaceById: (id) {
      for (final w in host.state.workspaces) {
        if (w.workspaceId == id) return w;
      }
      return null;
    },
  );
}

class _RecordingScheduler implements SessionConnectSchedulerPort {
  _RecordingScheduler(this.onSchedule);

  final void Function(TeamMemberConfig member) onSchedule;

  @override
  Future<void> enqueue(
    SessionConnectJob job, {
    bool waitForCompletion = false,
  }) async {
    onSchedule(job.member!);
  }

  @override
  void cancelForSession(String sessionId) {}
}

class _NoopLaunchCoordinator implements SessionLaunchIntentPort {
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

// Fake host copied (minimally) from the stable-task-id launch test.
class _CapturingHost implements SessionLaunchHost {
  _CapturingHost(
    this.state, {
    required ChatTabStore tabStore,
    SessionLifecycleService? lifecycle,
    SessionRepository? sessionRepository,
  }) : tabStore = tabStore,
       lifecycle =
           lifecycle ??
           SessionLifecycleService(
             storage: fakeHomeStorage(),
             loadPresets: () => const [],
           ),
       // ignore: prefer_initializing_formals
       sessionRepository = sessionRepository,
       shellFactory = ChatSessionShellFactory(
         executableResolver: () => 'true',
         terminalSessionFactory:
             ({required executable, scrollbackLines = 10000}) =>
                 TerminalSession(
                   executable: executable,
                   fs: InMemoryFilesystem(),
                 ),
         defaultTargetResolver: RuntimeTarget.local,
       ),
       sessionRuntime = TabSessionRuntimeCoordinator(
         tabStore: tabStore,
         shellFactory: ChatSessionShellFactory(
           executableResolver: () => 'true',
         ),
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

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) {
    state = state.copyWith(
      workspaces: snapshot.workspaces,
      sessions: snapshot.sessions,
      visibleWorkspaces: snapshot.visibleWorkspaces,
      visibleSessions: snapshot.visibleSessions,
    );
  }

  @override
  final ChatTabStore tabStore;

  @override
  final SessionLifecycleService lifecycle;

  @override
  final ChatSessionShellFactory shellFactory;

  @override
  final TabSessionRuntimeCoordinator sessionRuntime;

  @override
  final SessionRepository? sessionRepository;

  @override
  bool get isClosed => false;

  @override
  ChatTab? get activeTab => tabStore.activeTab(0);

  @override
  set activeTeam(TeamProfile? team) {}

  void applyState(ChatState next) => state = next;

  @override
  void appendSessionSnapshot(AppSession session) {
    state = state.copyWith(sessions: [...state.sessions, session]);
  }

  @override
  void replaceSessionSnapshot(AppSession session) {}

  @override
  void removeSessionSnapshot(String sessionId) {}

  @override
  void refreshActiveWorkspaceTabs() {}

  @override
  void pushPresenceTarget() {}

  @override
  void updateTabRunning(String tabId) {}

  @override
  void beginSessionConnect(String sessionId) {}

  @override
  void failSessionConnect(
    String sessionId,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  void clearLaunchError(String sessionId) {}

  @override
  void setLaunchError(String sessionId, String rawMessage) {}

  @override
  void assignSelectedMember(ChatTab tab, String memberId) {
    tab.selectedMemberId = memberId;
  }

  @override
  void selectMember(String memberId, {String? tabScopeId}) {}

  @override
  void closeSessionTab(String sessionId) {}

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {}

  @override
  PostFrameScheduler get postFrameScheduler =>
      (VoidCallback cb) => cb();

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {}

  @override
  bool isSessionConnecting(String sessionId) => false;

  @override
  bool get hasConnectingSession => false;

  @override
  void setMaterializingInFlight(bool value) {}

  @override
  final SessionDataStore dataStore = SessionDataStore(
    storage: fakeHomeStorage(),
  );

  @override
  bool get isMaterializingInFlight => false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
