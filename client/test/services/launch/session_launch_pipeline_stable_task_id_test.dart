import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_create_request.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/cubits/chat/session_launch_service.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/launch_operation.dart';
import 'package:teampilot/services/launch/launch_outcome.dart';
import 'package:teampilot/services/launch/session_default_materializer.dart';
import 'package:teampilot/services/launch/session_launch_pipeline.dart';
import 'package:teampilot/services/launch/session_launch_workspace_index.dart';
import 'package:teampilot/services/launch/session_tab_surface_coordinator.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('stable member taskId staging', () {
    test('provisional team bindings use plan taskIds not sessionId', () async {
      final tabStore = ChatTabStore()..setActiveWorkspace('ws-1');
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
      );

      final host = _CapturingHost(
        ChatState(workspaces: [workspace]),
        tabStore: tabStore,
      );
      final pipeline = _pipelineForStaging(host: host, tabStore: tabStore);

      const fixedSessionId = 'sess-fixed-aaaaaaaaaaaaaaaa';
      final outcome = await pipeline.run(
        CreateSessionOperation(
          SessionCreateRequest(
            workspace: workspace,
            isPersonal: false,
            team: team,
            member: team.members.first,
            fixedSessionId: fixedSessionId,
          ),
        ),
      );

      expect(outcome, isA<LaunchOpened>());
      expect((outcome as LaunchOpened).status, SessionOpenStatus.opened);
      expect(host.appended, hasLength(1));

      final provisional = host.appended.single;
      expect(provisional.sessionId, fixedSessionId);
      expect(provisional.members, isNotEmpty);
      for (final binding in provisional.members) {
        expect(
          binding.taskId,
          isNot(equals(fixedSessionId)),
          reason: 'placeholder taskId=sessionId must not be used',
        );
        expect(binding.taskId, isNotEmpty);
      }
      expect(
        provisional.members.map((m) => m.taskId).toSet().length,
        provisional.members.length,
      );
      expect(
        provisional.members.any((m) => m.rosterMemberId == 'team-lead'),
        isTrue,
      );
      expect(provisional.memberTargets, isNotEmpty);
    });

    test('team provisional bindings keep taskIds through persist', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'pipeline_stable_task_id_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/proj'),
      ]);
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
      );

      final tabStore = ChatTabStore()..setActiveWorkspace(workspace.workspaceId);
      final host = _CapturingHost(
        ChatState(workspaces: [workspace]),
        tabStore: tabStore,
        lifecycle: SessionLifecycleService(loadPresets: () => const []),
        sessionRepository: repo,
      );
      final service = SessionLaunchService(host);

      const fixedSessionId = 'sess-persist-bbbbbbbbbbbbbbbb';
      final status = await service.requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: false,
          team: team,
          member: team.members.first,
          repo: repo,
          fixedSessionId: fixedSessionId,
        ),
      );
      expect(status, SessionOpenStatus.opened);
      expect(host.appended, hasLength(1));
      final provisional = host.appended.single;

      await _waitUntil(() => host.replaced.isNotEmpty);

      final persisted = host.replaced.single;
      expect(persisted.sessionId, fixedSessionId);
      expect(provisional.members, isNotEmpty);
      for (final p in provisional.members) {
        expect(p.taskId, isNot(equals(fixedSessionId)));
        final after = persisted.bindingFor(p.rosterMemberId);
        expect(after, isNotNull);
        expect(
          after!.taskId,
          p.taskId,
          reason: 'taskId must survive persist for ${p.rosterMemberId}',
        );
      }
    });

    test(
      'persistSessionIfNeeded forwards staged members to createSession',
      () async {
        final workspace = Workspace(
          workspaceId: 'ws-1',
          folders: const [WorkspaceFolder(path: '/proj')],
          createdAt: 1,
          updatedAt: 1,
        );
        final team = TeamProfile(
          id: 'team-1',
          name: 'Team',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'builder', name: 'Builder'),
          ],
          cli: CliTool.claude,
        );
        final capturer = _CapturingSessionRepository();
        final tabStore = ChatTabStore()..setActiveWorkspace('ws-1');
        final host = _CapturingHost(
          ChatState(workspaces: [workspace]),
          tabStore: tabStore,
          lifecycle: SessionLifecycleService(loadPresets: () => const []),
          sessionRepository: capturer,
        );
        final service = SessionLaunchService(host);

        const fixedSessionId = 'sess-forward-cccccccccccccccc';
        final status = await service.requestCreateAndOpenSession(
          SessionCreateRequest(
            workspace: workspace,
            isPersonal: false,
            team: team,
            member: team.members.first,
            repo: capturer,
            fixedSessionId: fixedSessionId,
          ),
        );
        expect(status, SessionOpenStatus.opened);
        expect(host.appended, hasLength(1));
        final provisional = host.appended.single;

        await _waitUntil(() => capturer.createCalls.isNotEmpty);

        final call = capturer.createCalls.single;
        expect(call.fixedSessionId, fixedSessionId);
        expect(call.members, isNotNull);
        expect(
          call.members!.map((m) => m.rosterMemberId).toSet(),
          provisional.members.map((m) => m.rosterMemberId).toSet(),
        );
        for (final p in provisional.members) {
          final forwarded = call.members!.firstWhere(
            (m) => m.rosterMemberId == p.rosterMemberId,
          );
          expect(forwarded.taskId, p.taskId);
        }
        expect(call.memberTargets, provisional.memberTargets);
      },
    );
  });
}

Future<void> _waitUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SessionLaunchPipeline _pipelineForStaging({
  required _CapturingHost host,
  required ChatTabStore tabStore,
}) {
  final materializer = SessionDefaultMaterializer(
    host: host,
    openSession: (_) async => SessionOpenStatus.opened,
    workspaceIndex: () => SessionLaunchWorkspaceIndex(
      workspaces: host.state.workspaces,
      sessions: host.state.sessions,
    ),
    isTabsEmpty: () => tabStore.activeTabsIsEmpty,
    activeBucketKey: () => tabStore.activeWorkspaceId,
  );
  final tabSurface = SessionTabSurfaceCoordinator(
    host: host,
    tabStore: tabStore,
    state: () => host.state,
    workspaceById: (id) {
      for (final w in host.state.workspaces) {
        if (w.workspaceId == id) return w;
      }
      return null;
    },
    shouldAutoConnect: (_) => false,
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
  return SessionLaunchPipeline(
    host: host,
    tabStore: tabStore,
    state: () => host.state,
    workspaceIndex: () => SessionLaunchWorkspaceIndex(
      workspaces: host.state.workspaces,
      sessions: host.state.sessions,
    ),
    tabSurface: tabSurface,
    materializer: materializer,
    scheduleMemberConnect: (_, __, ___) {},
    disconnectSession: () {},
    ensureSession: (_) => null,
    appendLocalTab: (_, {required emitChange}) =>
        throw UnsupportedError('unused'),
    ensureActiveSessionTab: (_, {required emitChange}) =>
        throw UnsupportedError('unused'),
    resetTeamConfigValidationSurface: () {},
    scheduleTeamConfigValidation: (_) async {},
    activeTab: () => host.activeTab,
    autoLaunchAllMembersOnConnect: () => false,
    uuid: const Uuid(),
  );
}

class _CreateSessionCall {
  const _CreateSessionCall({
    required this.fixedSessionId,
    required this.members,
    required this.memberTargets,
  });

  final String? fixedSessionId;
  final List<SessionMemberBinding>? members;
  final Map<String, String>? memberTargets;
}

class _CapturingSessionRepository extends Fake implements SessionRepository {
  final createCalls = <_CreateSessionCall>[];

  @override
  Future<AppSession> createSession(
    String workspaceId, {
    String sessionTeam = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    String? workingDirectory,
    String? fixedSessionId,
    String? expertKey,
    SessionContinueOverrides? continueOverrides,
    List<SessionMemberBinding>? members,
    Map<String, String>? memberTargets,
  }) async {
    createCalls.add(
      _CreateSessionCall(
        fixedSessionId: fixedSessionId,
        members: members,
        memberTargets: memberTargets,
      ),
    );
    return AppSession(
      sessionId: fixedSessionId ?? 'generated',
      workspaceId: workspaceId,
      sessionTeam: sessionTeam,
      members: members ?? const [],
      memberTargets: memberTargets ?? const {},
      createdAt: 1,
      updatedAt: 1,
    );
  }
}

class _CapturingHost implements SessionLaunchHost {
  _CapturingHost(
    this.state, {
    required ChatTabStore tabStore,
    SessionLifecycleService? lifecycle,
    SessionRepository? sessionRepository,
  }) : tabStore = tabStore,
       lifecycle =
           lifecycle ?? SessionLifecycleService(loadPresets: () => const []),
       sessionRepository = sessionRepository,
       shellFactory = ChatSessionShellFactory(
         executableResolver: () => 'true',
         terminalSessionFactory:
             ({required executable, scrollbackLines = 10000}) =>
                 TerminalSession(executable: executable),
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

  @override
  ChatState state;

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

  final appended = <AppSession>[];
  final replaced = <AppSession>[];

  @override
  bool get isClosed => false;

  @override
  ChatTab? get activeTab {
    final idx = state.activeTabIndex;
    if (idx == null || idx < 0 || idx >= tabStore.activeTabCount) {
      return null;
    }
    return tabStore.activeTabs[idx];
  }

  @override
  set activeTeam(TeamProfile? team) {}

  @override
  void applyState(ChatState next) => state = next;

  @override
  void appendSessionSnapshot(AppSession session) {
    appended.add(session);
    state = state.copyWith(sessions: [...state.sessions, session]);
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    replaced.add(session);
    final next = <AppSession>[
      for (final s in state.sessions)
        if (s.sessionId == session.sessionId) session else s,
    ];
    if (!next.any((s) => s.sessionId == session.sessionId)) {
      next.add(session);
    }
    state = state.copyWith(sessions: next);
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          if (s.sessionId != sessionId) s,
      ],
    );
  }

  @override
  void refreshActiveWorkspaceTabs() {}

  @override
  void pushPresenceTarget() {}

  @override
  void updateTabRunning(String tabId) {}

  @override
  void beginSessionConnect(String sessionId) {}

  @override
  void failSessionConnect(String sessionId, String rawMessage) {}

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  void clearLaunchError(String sessionId) {}

  @override
  void setLaunchError(String sessionId, String rawMessage) {}

  @override
  void selectMember(String memberId) {}

  @override
  void closeSessionTab(String sessionId) {}

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {}

  @override
  PostFrameScheduler get postFrameScheduler => (VoidCallback cb) => cb();

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
