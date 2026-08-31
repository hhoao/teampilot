import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_create_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/cubits/chat/session_launch_service.dart';
import 'package:teampilot/cubits/chat/tab_member_materializer.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/cubits/chat/tab_team_bus_coordinator.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/member_remote_provision_progress.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/launch/session_connect_orchestrator.dart';
import 'package:teampilot/services/launch/workspace_provision_coordinator.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_binding_resolver.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/team/team_config_launch_validator.dart';

class _CreateSessionCall {
  const _CreateSessionCall({
    required this.fixedSessionId,
    required this.purpose,
    required this.workflowId,
  });

  final String? fixedSessionId;
  final SessionPurpose purpose;
  final String workflowId;
}

class _CapturingSessionRepository extends Fake implements SessionRepository {
  final createCalls = <_CreateSessionCall>[];

  @override
  Future<void> renameSession(String sessionId, String newName) async {}

  Future<({AppSession session, Workspace workspace})> createSession(
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
    Workspace? knownWorkspace,
    SessionPurpose purpose = SessionPurpose.normal,
    String workflowId = '',
  }) async {
    createCalls.add(
      _CreateSessionCall(
        fixedSessionId: fixedSessionId,
        purpose: purpose,
        workflowId: workflowId,
      ),
    );
    final session = AppSession(
      sessionId: fixedSessionId ?? 'generated',
      workspaceId: workspaceId,
      sessionTeam: sessionTeam,
      purpose: purpose,
      workflowId: workflowId,
      expertKey: expertKey ?? '',
      members: members ?? const [],
      memberTargets: memberTargets ?? const {},
      createdAt: 1,
      updatedAt: 1,
    );
    return (
      session: session,
      workspace:
          knownWorkspace ??
          Workspace(workspaceId: workspaceId, createdAt: 1),
    );
  }
}

/// Shared harness for session-creation pipeline tests.
class SessionGenerationHarness {
  SessionGenerationHarness(Workspace workspace)
    : workspace = workspace,
      repository = _CapturingSessionRepository(),
      tabStore = ChatTabStore()..setActiveWorkspaceId(workspace.workspaceId) {
    host = _CapturingHost(
      ChatState(workspaces: [workspace]),
      tabStore: tabStore,
      lifecycle: SessionLifecycleService(loadPresets: () => const []),
      sessionRepository: repository,
    );
    service = SessionLaunchService(host);
  }

  final Workspace workspace;
  final _CapturingSessionRepository repository;
  final ChatTabStore tabStore;
  late final _CapturingHost host;
  late final SessionLaunchService service;

  Future<SessionOpenStatus> create(SessionCreateRequest request) =>
      service.requestCreateAndOpenSession(request);

  Future<void> waitUntilPersisted() async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (repository.createCalls.isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('timed out waiting for session persistence');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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
  final SessionRepository? sessionRepository;

  @override
  final ChatSessionShellFactory shellFactory;

  @override
  final TabSessionRuntimeCoordinator sessionRuntime;

  final appended = <AppSession>[];
  final replaced = <AppSession>[];

  @override
  bool get isClosed => false;

  @override
  ChatTab? get activeTab => tabStore.activeTab(0);

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
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
        workspaces: state.workspaces,
        sessions: state.sessions,
        visibleWorkspaces: state.visibleWorkspaces,
        visibleSessions: state.visibleSessions,
      );

  @override
  final SessionDataStore dataStore = SessionDataStore();

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
  void refreshActiveWorkspaceTabs() {}

  @override
  void pushPresenceTarget() {}

  @override
  void emitTeamConfigValidation(TeamConfigValidation validation) {}

  @override
  void assignSelectedMember(ChatTab tab, String memberId) {
    tab.selectedMemberId = memberId;
  }

  @override
  void selectMember(String memberId, {String? tabScopeId}) {}

  @override
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {}

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {}

  @override
  PostFrameScheduler get postFrameScheduler => (VoidCallback cb) => cb();

  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {}

  @override
  bool isSessionConnecting(String sessionId) => false;

  @override
  bool get hasConnectingSession => false;

  @override
  void setMaterializingInFlight(bool value) {}

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
  void emitLaunchWarnings(List<String> warnings) {}

  @override
  void setMemberRemoteProvisionProgress(
    String sessionId,
    String memberId,
    MemberRemoteProvisionProgress? progress,
  ) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  Workspace workspace() => Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );

  test('create request persists builder purpose and workflow', () async {
    final harness = SessionGenerationHarness(workspace());
    const fixedSessionId = 'builder-1';
    final status = await harness.create(
      SessionCreateRequest(
        workspace: harness.workspace,
        isPersonal: true,
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'workflow-1',
        fixedSessionId: fixedSessionId,
        emptyDisplayTitleFallback: 'Team Builder',
      ),
    );
    expect(status, SessionOpenStatus.opened);
    await harness.waitUntilPersisted();

    final call = harness.repository.createCalls.single;
    expect(call.fixedSessionId, fixedSessionId);
    expect(call.purpose, SessionPurpose.teamGeneration);
    expect(call.workflowId, 'workflow-1');
  });

  test('normal create requests default to normal purpose', () async {
    final harness = SessionGenerationHarness(workspace());
    final status = await harness.create(
      SessionCreateRequest(
        workspace: harness.workspace,
        isPersonal: true,
        fixedSessionId: 'normal-1',
      ),
    );
    expect(status, SessionOpenStatus.opened);
    await harness.waitUntilPersisted();

    final call = harness.repository.createCalls.single;
    expect(call.purpose, SessionPurpose.normal);
    expect(call.workflowId, isEmpty);
  });

  test('team generation purpose requires a valid workflow id', () async {
    final harness = SessionGenerationHarness(workspace());
    await expectLater(
      harness.create(
        SessionCreateRequest(
          workspace: harness.workspace,
          isPersonal: true,
          purpose: SessionPurpose.teamGeneration,
          workflowId: 'bad/../id',
          fixedSessionId: 'builder-x',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(harness.repository.createCalls, isEmpty);
  });
}
