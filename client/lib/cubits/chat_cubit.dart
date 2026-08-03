import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/workspace.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_launch_context.dart';
import '../models/app_session.dart';
import '../services/team/member_presence_service.dart';
import '../models/workspace_icon_picker_result.dart';
import '../models/workspace_icon_ref.dart';
import '../models/team_config.dart';
import '../models/runtime_target.dart';
import '../../repositories/launch_profile_repository.dart';
import '../repositories/automation_repository.dart';
import '../repositories/session_repository.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/session/session_member_cli_locks.dart';
import '../services/remote/remote_cli_readiness.dart';
import '../services/team_bus/artifacts/artifact_registry.dart';
import '../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_status_event.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import 'agent_attention_cubit.dart';
import '../services/launch/launch_factory.dart';
import '../services/launch/session_connect_orchestrator.dart';
import '../services/launch/workspace_provision_coordinator.dart';
import '../services/progress_activity/cli_provision_activity_adapter.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/ask_user_question_answer_service.dart';
import '../services/terminal/member_turn_interrupt_service.dart';
import '../services/terminal/session_member_cli_resolver.dart';
import '../services/termux/termux_connection_gate.dart';
import '../services/terminal/terminal_theme_for_launch.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/follow_up/follow_up_queue.dart';
import '../services/follow_up/follow_up_queue_drainer.dart';
import '../pages/chat/history_continue_delivery.dart';
import '../pages/chat/session_chat_continue_seat.dart';
import '../pages/chat/session_history_review_submit.dart';
import '../utils/session/workspace_sessions.dart';
import '../../widgets/workspace_icon_picker_dialog.dart';
import '../utils/logging/logger_utils.dart';
import 'chat/session_launch_retry.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/session_launch_host.dart';
import 'chat/session_launch_service.dart';
import 'chat/tab_member_materializer.dart';
import 'chat/tab_session_runtime_coordinator.dart';
import 'chat/tab_team_bus_coordinator.dart';
import 'layout_cubit.dart';
import 'member_presence_cubit.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/session_connect_request.dart';
import 'chat/model/session_create_request.dart';
import 'chat/model/session_open_request.dart';
import 'chat/model/session_open_status.dart';
import 'chat/model/session_workbench_view.dart';
import 'chat/session_continue_overrides_controller.dart';
import '../models/cli_preset.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';
export 'chat/model/session_create_request.dart';
export 'chat/model/session_open_request.dart';
export 'chat/model/session_open_status.dart';
export 'chat/model/session_workbench_view.dart';

class ChatCubit extends Cubit<ChatState>
    with ChatConnectStateMixin
    implements SessionLaunchHost {
  ChatCubit({
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TerminalSessionFactory terminalSessionFactory =
        defaultTerminalSessionFactory,
    PostFrameScheduler? postFrameScheduler,
    bool Function()? autoLaunchAllMembersOnConnect,
    SessionLifecycleService? lifecycleService,
    SessionRepository? sessionRepository,
    TerminalTransportFactory? transportFactory,
    SshActiveProfileResolver? sshProfileResolver,
    SshProfileByIdResolver? sshProfileById,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    RuntimeTarget Function()? defaultTargetResolver,
    int Function()? terminalScrollbackLinesResolver,
    RemoteBusBindingResolver? remoteBusResolver,
    SessionConnectOrchestrator? sessionConnect,
    TeammateBusMcpGateway? teammateBusMcpGateway,
    AgentStatusSeatLookup? agentStatusSeatLookup,
    AgentAttentionCubit? agentAttentionCubit,
    AskUserQuestionAnswerService? askUserQuestionAnswerService,
    InMemoryFollowUpQueueStore? followUpQueueStore,
    FollowUpQueueDrainer? followUpQueueDrainer,
    Future<TeamProfile?> Function(String teamId)? teamById,
    required AutomationRepository automationRepository,
    LayoutCubit? layoutCubit,
    RemoteCliReadinessService? remoteCliReadiness,
    CliProvisionActivityAdapter? cliProvisionActivity,
    bool Function()? termuxConnectedResolver,
    String Function()? termuxDisconnectedWorkOpsMessageResolver,
    RuntimeTarget Function()? termuxGateHomeResolver,
  }) : _remoteBusResolver = remoteBusResolver,
       _remoteCliReadiness = remoteCliReadiness,
       _sessionConnect = sessionConnect,
       _cliProvisionActivity = cliProvisionActivity,
       _teamById = teamById,
       _teammateBusMcpGateway =
           teammateBusMcpGateway ?? TeammateBusMcpGateway(),
       _agentStatusSeatLookup = agentStatusSeatLookup,
       _agentAttentionCubit = agentAttentionCubit,
       _automationRepository = automationRepository,
       _layoutCubit = layoutCubit,
       _shellFactory = ChatSessionShellFactory(
         executableResolver: executableResolver,
         cliExecutableResolver: cliExecutableResolver,
         terminalSessionFactory: terminalSessionFactory,
         transportFactory: transportFactory,
         sshProfileResolver: sshProfileResolver,
         sshProfileById: sshProfileById,
         sshDefaultWorkingDirectoryResolver: sshDefaultWorkingDirectoryResolver,
         sshUseLoginShellResolver: sshUseLoginShellResolver,
         defaultTargetResolver: defaultTargetResolver,
         terminalScrollbackLinesResolver: terminalScrollbackLinesResolver,
       ),
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       _followUpQueue = followUpQueueStore ?? InMemoryFollowUpQueueStore(),
       _termuxConnectedResolver = termuxConnectedResolver,
       _termuxDisconnectedWorkOpsMessageResolver =
           termuxDisconnectedWorkOpsMessageResolver,
       _termuxGateHomeResolver = termuxGateHomeResolver,
       super(const ChatState()) {
    _askUserAnswer = askUserQuestionAnswerService ?? AskUserQuestionAnswerService();
    _followUpDrainer =
        followUpQueueDrainer ??
        FollowUpQueueDrainer(
          store: _followUpQueue,
          deliver: (seat, content) => _deliverFollowUpAtSeat(seat, content),
        );
    final attention = _agentAttentionCubit;
    if (attention != null) {
      _agentAttentionSub = attention.stream.listen((_) {
        if (!isClosed) _recomputeWorkingSessions();
      });
    }
  }

  /// Fired when History should drop cache / reload (disconnect or switch back).
  void Function(String sessionId)? onSessionHistoryStale;

  /// Fired when a session tab is torn down so History can dispose its seats.
  void Function(String sessionId)? onHistorySeatsDispose;

  final RemoteBusBindingResolver? _remoteBusResolver;
  final RemoteCliReadinessService? _remoteCliReadiness;
  final CliProvisionActivityAdapter? _cliProvisionActivity;
  final SessionConnectOrchestrator? _sessionConnect;

  /// User-driven remote CLI locate/install (Machines panel + landing gate).
  RemoteCliReadinessService? get remoteCliReadiness => _remoteCliReadiness;
  final Future<TeamProfile?> Function(String teamId)? _teamById;
  final bool Function()? _termuxConnectedResolver;
  final String Function()? _termuxDisconnectedWorkOpsMessageResolver;
  final RuntimeTarget Function()? _termuxGateHomeResolver;
  final TeammateBusMcpGateway _teammateBusMcpGateway;
  final AgentStatusSeatLookup? _agentStatusSeatLookup;
  final AgentAttentionCubit? _agentAttentionCubit;
  StreamSubscription<AgentAttentionState>? _agentAttentionSub;
  final AutomationRepository _automationRepository;
  final LayoutCubit? _layoutCubit;
  final InMemoryFollowUpQueueStore _followUpQueue;
  late final FollowUpQueueDrainer _followUpDrainer;
  VoidCallback? _onAutomationsChanged;
  SessionConnectOrchestrator? _defaultSessionConnect;

  InMemoryFollowUpQueueStore get followUpQueue => _followUpQueue;

  void bindAutomationsChangeNotifier(VoidCallback listener) {
    _onAutomationsChanged = listener;
  }

  void _notifyAutomationsChanged() => _onAutomationsChanged?.call();

  String? _termuxWorkOpsBlockFor(RuntimeTarget target) {
    final connected = _termuxConnectedResolver?.call();
    final message = _termuxDisconnectedWorkOpsMessageResolver?.call();
    final home = _termuxGateHomeResolver?.call();
    if (connected == null || message == null || home == null) return null;
    return termuxWorkOpsBlockMessage(
      target: target,
      home: home,
      termuxConnected: connected,
      message: message,
    );
  }

  final ChatTabStore _tabStore = ChatTabStore();
  final SessionDataStore _dataStore = SessionDataStore();
  static const _continueOverridesController =
      SessionContinueOverridesController();
  final Map<String, Future<void>> _sessionHydrationByWorkspace = {};
  late final SessionLaunchService _launchService = SessionLaunchService(
    this,
    termuxWorkOpsBlockFor: _termuxWorkOpsBlockFor,
  );
  late final TabSessionRuntimeCoordinator _sessionRuntime =
      TabSessionRuntimeCoordinator(
        tabStore: _tabStore,
        shellFactory: _shellFactory,
        activeTeam: () => _activeTeam,
        isClosed: () => isClosed,
        globalPresets: () => _lifecycle.globalPresets,
        activeSessionId: () => state.activeSessionId,
        presence: () => _presenceCubit?.state.presence ?? const {},
        sessionBusyFromAttention: (sessionId) {
          final attention = _agentAttentionCubit;
          if (attention == null) return false;
          final bus = _tabStore.openTabBySessionId(sessionId)?.teamBus;
          // Why: WaitEntered clears hook working, but a late PreToolUse can
          // re-stamp attention while the member is still bus-parked.
          if (bus != null) {
            return attention.state.sessionIsAgentActive(
              sessionId,
              includeMember: (id) => !bus.isWaitingForMessage(id),
            );
          }
          return attention.state.sessionIsAgentActive(sessionId);
        },
        onAfterIdleWatchTick: () => unawaited(_onIdleWatchTick()),
        onAfterTurnLatched: _onOperatorTurnLatched,
      );
  late final MemberTurnInterruptService _turnInterrupt =
      MemberTurnInterruptService(
        cliToolRegistry: CliToolRegistry.builtIn(),
        abortMemberInject: _sessionRuntime.abortMemberInject,
      );
  late final AskUserQuestionAnswerService _askUserAnswer;
  late final TabMemberMaterializer _memberMaterializer = TabMemberMaterializer(
    runtime: _sessionRuntime,
    tabStore: _tabStore,
    connector: _launchService,
    activeTeam: () => _activeTeam,
    isClosed: () => isClosed,
    isMixedBusRegistered: _teammateBusMcpGateway.isSessionRegistered,
    isMemberConnectOwnedElsewhere: _launchService.isMemberConnectOwnedElsewhere,
    isDirectPtyLifecycleReady: _launchService.isMemberDirectPtyLifecycleReady,
  );
  late final TabTeamBusCoordinator _teamBus = TabTeamBusCoordinator(
    gateway: _teammateBusMcpGateway,
    tabStore: _tabStore,
    materializer: _memberMaterializer,
    globalPresets: () => _lifecycle.globalPresets,
    onAfterTurnLatched: _onOperatorTurnLatched,
    onMemberWaitEntered: _onMemberWaitEntered,
    artifactServiceFactory: _buildArtifactService,
    launchWorkTarget: (session, {String? memberId}) =>
        _lifecycle.launchWorkTarget(
          _launchService.launchContextFor(session),
          memberId: memberId,
        ),
    memberWorkDirs: (session, memberId) => _lifecycle.memberWorkDirs(
      _launchService.launchContextFor(session),
      memberId,
    ),
    sshProfileById: _shellFactory.profileById,
  );

  /// P3d: a per-session cross-machine artifact transfer service. The registry is
  /// session-scoped (one per bus install), so published handles live only as
  /// long as the session. Resolvers reuse the launch path's member→target and
  /// work-context seams so publisher/fetcher bytes move on the right machines.
  ArtifactTransferService _buildArtifactService(AppSession session) {
    return ArtifactTransferService(
      registry: ArtifactRegistry(),
      resolveFs: (targetId) async =>
          (await _lifecycle.resolveWorkContextForTargetId(targetId)).filesystem,
      targetForMember: (memberId) {
        final workspace = state.workspaces
            .where((w) => w.workspaceId == session.workspaceId)
            .firstOrNull;
        return _lifecycle
            .launchWorkTarget(
              WorkspaceLaunchContext(
                session: session,
                workspace:
                    workspace ??
                    Workspace(
                      workspaceId: session.workspaceId,
                      folders: session.folders,
                      createdAt: 0,
                    ),
              ),
              memberId: memberId,
            )
            .id;
      },
      inboxDirFor: (memberId) {
        final workspace = state.workspaces
            .where((w) => w.workspaceId == session.workspaceId)
            .firstOrNull;
        final ctx = WorkspaceLaunchContext(
          session: session,
          workspace:
              workspace ??
              Workspace(
                workspaceId: session.workspaceId,
                folders: session.folders,
                createdAt: 0,
              ),
        );
        final cwd = _lifecycle.memberWorkDirs(ctx, memberId).workingDirectory;
        return cwd.isEmpty ? '.teampilot-inbox' : '$cwd/.teampilot-inbox';
      },
    );
  }

  MemberPresenceCubit? _presenceCubit;
  TeamProfile? _activeTeam;
  final ChatSessionShellFactory _shellFactory;
  final PostFrameScheduler _postFrameScheduler;
  final bool Function()? _autoLaunchAllMembersOnConnect;
  final SessionLifecycleService _lifecycle;
  final SessionRepository? _sessionRepository;

  @override
  ChatTabStore get tabStore => _tabStore;

  @override
  void onTabRunningChanged() => _pushPresenceTarget();

  // ===== SessionLaunchHost =====

  @override
  void applyState(ChatState next) {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (next.newChatActive) {
      _tabStore.setNewChatActive(workspaceId, true);
    } else {
      _tabStore.setNewChatActive(workspaceId, false);
    }
    emit(next);
  }

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => _emitSnapshot(snapshot);

  @override
  void appendSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.replaceSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    _emitSnapshot(
      _dataStore.removeSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        sessionId,
      ),
    );
  }

  @override
  void closeSessionTab(String sessionId) {
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) closeTab(idx);
  }

  @override
  void pushPresenceTarget() => _pushPresenceTarget();

  @override
  ChatTab? get activeTab => _activeTab;

  @override
  set activeTeam(TeamProfile? team) => _activeTeam = team;

  @override
  ChatSessionShellFactory get shellFactory => _shellFactory;

  @override
  TabSessionRuntimeCoordinator get sessionRuntime => _sessionRuntime;

  @override
  TabTeamBusCoordinator get teamBus => _teamBus;

  @override
  TabMemberMaterializer get memberMaterializer => _memberMaterializer;

  @override
  TeammateBusMcpGateway get teammateBusMcpGateway => _teammateBusMcpGateway;

  @override
  AgentStatusSeatLookup? get agentStatusSeatLookup => _agentStatusSeatLookup;

  @override
  AgentAttentionCubit? get agentAttentionCubit => _agentAttentionCubit;

  @override
  SessionLifecycleService get lifecycle => _lifecycle;

  @override
  SessionDataStore get dataStore => _dataStore;

  /// True once [ensureSessionsForWorkspace] has loaded this workspace's
  /// sessions from disk. The UI uses this to tell "still loading" apart from
  /// "genuinely empty" so a cold tab switch shows a skeleton, not a flash of
  /// the empty-conversations placeholder.
  bool sessionsLoadedForWorkspace(String workspaceId) =>
      _dataStore.sessionsLoadedForWorkspace(workspaceId);

  @override
  SessionRepository? get sessionRepository => _sessionRepository;

  @override
  PostFrameScheduler get postFrameScheduler => _postFrameScheduler;

  @override
  bool Function()? get autoLaunchAllMembersOnConnect =>
      _autoLaunchAllMembersOnConnect;

  @override
  RemoteBusBindingResolver? get remoteBusResolver => _remoteBusResolver;

  @override
  SessionConnectOrchestrator get sessionConnect =>
      _sessionConnect ??
      (_defaultSessionConnect ??= buildDefaultSessionConnectOrchestrator(
        lifecycle: _lifecycle,
        localCliPath: (cli) async => _shellFactory.executableFor(cli),
        sshClientFactory: _shellFactory.sshClientFactory,
        profileById: _shellFactory.profileById,
      ));

  @override
  WorkspaceProvisionCoordinator get workspaceProvision =>
      sessionConnect.workspaceProvision;

  @override
  CliProvisionActivityAdapter? get cliProvisionActivity => _cliProvisionActivity;

  @override
  CliToolRegistry get cliRegistry => _lifecycle.cliToolRegistry;

  @override
  Future<TeamProfile?> teamProfileById(String teamId) async {
    final id = teamId.trim();
    if (id.isEmpty) return null;
    if (_activeTeam?.id == id) return _activeTeam;
    return _teamById?.call(id);
  }

  @override
  Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return false;
    for (final w in state.workspaces) {
      if (w.workspaceId == id) return w.rootSandboxEnvOptIn;
    }
    return false;
  }

  @override
  TerminalTheme? resolveTerminalThemeForLaunch() {
    final layout = _layoutCubit;
    if (layout == null) return null;
    return resolveTerminalThemeFromLayout(
      preferences: layout.state.preferences,
      platformBrightness:
          SchedulerBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  /// Drops cached Phase A provision for [workspace] (e.g. after folder/target edits).
  void invalidateWorkspaceProvision(Workspace workspace) {
    sessionConnect.invalidateWorkspaceProvision(workspace);
  }

  /// Wired by app_shell after both cubits are constructed.
  void bindPresenceCubit(MemberPresenceCubit cubit) => _presenceCubit = cubit;

  /// Pushed after each idle-watch tick once member presence has been refreshed.
  /// Session spinners follow the members panel ([MemberAvailability.working]).
  void _updateWorkingSessions(Set<String> ids) {
    if (isClosed || setEquals(ids, state.workingSessionIds)) return;
    emit(state.copyWith(workingSessionIds: ids));
  }

  Future<void> _onIdleWatchTick() async {
    await _presenceCubit?.tickFromIdleWatch();
    if (isClosed) return;
    _recomputeWorkingSessions();
  }

  void _recomputeWorkingSessions() {
    _updateWorkingSessions(_sessionRuntime.recomputeWorkingSessions());
    _syncFollowUpQueuesWithWorking();
  }

  void _syncFollowUpQueuesWithWorking() {
    if (isClosed) return;
    final seen = <String>{};
    void notifySeat(String sessionId, String memberId) {
      final seat = followUpSeatKey(sessionId, memberId);
      if (!seen.add(seat)) return;
      final q = _followUpQueue.queueFor(seat);
      if (q.items.isEmpty && q.drain == FollowUpDrainMode.armed) return;
      notifyFollowUpMemberWorking(
        sessionId,
        memberId,
        working: isMemberWorking(sessionId, memberId),
      );
    }

    for (final tab in _tabStore.activeTabs) {
      final mid = tab.selectedMemberId.trim();
      if (mid.isNotEmpty) notifySeat(tab.info.id, mid);
    }
    for (final seat in _followUpQueue.seats) {
      final parsed = parseFollowUpSeatKey(seat);
      if (parsed == null) continue;
      notifySeat(parsed.$1, parsed.$2);
    }
  }

  void pauseFollowUpQueue(String sessionId, String memberId) {
    _followUpQueue.pause(followUpSeatKey(sessionId, memberId));
  }

  Future<void> resumeFollowUpQueue(String sessionId, String memberId) =>
      _followUpDrainer.resumeAndMaybeDrain(
        followUpSeatKey(sessionId, memberId),
      );

  void notifyFollowUpMemberWorking(
    String sessionId,
    String memberId, {
    required bool working,
  }) {
    unawaited(
      _followUpDrainer.onMemberWorkingChanged(
        followUpSeatKey(sessionId, memberId),
        working: working,
      ),
    );
  }

  /// History continue, follow-up drain, and Terminal deliver share this path.
  Future<HistoryContinueSubmitResult> submitSessionOperatorMessage({
    required String sessionId,
    required String memberId,
    required String message,
    bool preserveWorkbenchView = true,
  }) async {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final session = tab?.persistedSession;
    if (session == null) {
      return const HistoryContinueSubmitResult.failed();
    }

    final isPersonal = session.sessionTeam.trim().isEmpty;
    TeamProfile? team;
    if (!isPersonal) {
      team = await teamProfileById(session.sessionTeam);
    }

    TeamMemberConfig? connectMember;
    if (!isPersonal && team != null) {
      connectMember = resolveSessionChatContinueMember(
        session: session,
        team: team,
        selectedMemberId: memberId,
      );
    }
    final shellMemberId = isPersonal
        ? session.sessionId
        : (connectMember?.id ?? memberId);

    HistoryContinueChannel resolveChannel() {
      final bus = _sessionRuntime.busForSession(sessionId);
      return resolveHistoryContinueChannel(
        teamBusInstalled: bus != null,
        memberWaitingForMessage:
            bus?.isWaitingForMessage(shellMemberId) ?? false,
        memberInTurn: bus?.isMemberInTurn(shellMemberId) ?? false,
      );
    }

    return submitSessionHistoryReviewMessage(
      sessionId: sessionId,
      memberId: shellMemberId,
      message: message,
      connectRequest: ExistingSessionConnect(
        session: session,
        team: team,
        member: connectMember,
        preserveWorkbenchView: preserveWorkbenchView,
      ),
      resolveChannel: resolveChannel,
      connectWorkspaceSession: connectWorkspaceSession,
      ensureMemberInputReady:
          (sid, mid, {bool directToPty = false}) =>
              _memberMaterializer.ensureMemberInputReady(
                sid,
                mid,
                directToPty: directToPty,
              ),
      deliverUserCommandToMember:
          (sid, mid, text, {bool directToPty = false}) =>
              _sessionRuntime.deliverUserCommandToMember(
                sid,
                mid,
                text,
                directToPty: directToPty,
              ),
      applyFirstPromptTitle: applyFirstPromptTitle,
    );
  }

  Future<HistoryContinueSubmitResult> _deliverFollowUpAtSeat(
    String seat,
    String content,
  ) async {
    final parsed = parseFollowUpSeatKey(seat);
    if (parsed == null) return const HistoryContinueSubmitResult.failed();
    return submitSessionOperatorMessage(
      sessionId: parsed.$1,
      memberId: parsed.$2,
      message: content,
    );
  }

  /// History / Terminal operator submit latched a seat turn — refresh session
  /// working and clear sticky permission waiting so the sidebar spinner can show.
  void _onOperatorTurnLatched(String sessionId, String memberId) {
    final attention = _agentAttentionCubit;
    if (attention != null && memberId.trim().isNotEmpty) {
      // Why: [userTurnActive] already lights the spinner. Stamping
      // attention.working here pins [sessionIsAgentActive] for CLIs without
      // Stop/done (Cursor simple), so the sidebar stays busy after PTY quiet.
      // Clear any prior waiting/working seat so a fresh submit is not locked.
      attention.clearSeat(sessionId: sessionId, memberId: memberId);
    }
    _recomputeWorkingSessions();
  }

  /// Mixed `wait_for_message` park — drop PreToolUse working so the sidebar
  /// spinner matches member presence (bus idle while the MCP tool blocks).
  void _onMemberWaitEntered(String sessionId, String memberId) {
    final attention = _agentAttentionCubit;
    if (attention == null || memberId.trim().isEmpty) return;
    attention.clearSeat(sessionId: sessionId, memberId: memberId);
    attention.applyEvent(
      sessionId: sessionId,
      memberId: memberId,
      event: const AgentStatusEvent(state: AgentSeatAttention.done),
      skipPermissions: false,
    );
  }

  @visibleForTesting
  void updateWorkingSessionsForTest(Set<String> ids) =>
      _updateWorkingSessions(ids);

  @visibleForTesting
  void debugTickIdleWatch() => _sessionRuntime.debugTickIdleWatch();

  @visibleForTesting
  void debugRecomputeWorkingSessions() => _recomputeWorkingSessions();

  /// Seat-level working for compose stop button (mirrors members panel rules).
  bool isMemberWorking(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return false;

    final presence = _presenceCubit?.state.presence ?? const {};
    final sessionWorking = _sessionRuntime.sessionWorking;
    final usesPresenceSnapshot = sessionWorking.usesPresenceSnapshotForTab(
      tab: tab,
      activeSessionId: state.activeSessionId,
      presenceNonEmpty: presence.isNotEmpty,
    );

    return sessionWorking.isMemberWorking(
      tab: tab,
      memberId: memberId,
      team: _teamForSessionTab(tab),
      globalPresets: _lifecycle.globalPresets,
      presence: presence,
      usePresenceSnapshot: usesPresenceSnapshot,
    );
  }

  /// Cancels in-flight PTY inject and sends CLI turn-interrupt bytes to the seat.
  Future<void> interruptSelectedMemberTurn({
    String? sessionId,
    String? memberId,
  }) async {
    final sid = sessionId ?? state.activeSessionId;
    if (sid == null) return;
    final tab = _tabStore.openTabBySessionId(sid);
    if (tab == null) return;
    final mid = (memberId ?? tab.selectedMemberId).trim();
    if (mid.isEmpty) return;

    final cli = SessionMemberCliResolver.resolve(
      persistedSession: tab.persistedSession,
      team: _teamForSessionTab(tab),
      memberId: mid,
      cliForMember: _shellFactory.cliForMember,
      globalPresets: _lifecycle.globalPresets,
    );

    await _turnInterrupt.interrupt(
      sessionId: sid,
      memberId: mid,
      shell: tab.memberShells[mid],
      cli: cli,
    );
  }

  /// Answers AskUserQuestion via the CLI capability facade (PTY digit inject
  /// or pending store). [memberId] is the shell key (`sessionId` for simple,
  /// member id for team) — same as seat attention.
  ///
  /// Full optimistic dismiss + OpenCode `askRequestId`/`answers` wiring lands
  /// in a follow-up task; this keeps the card compiling against the facade.
  Future<AskUserAnswerResult> answerAskUserQuestion({
    required String sessionId,
    required String memberId,
    required int optionIndex,
    String? askRequestId,
    List<List<String>>? answers,
  }) async {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) {
      return const AskUserAnswerFailed('session_not_found');
    }
    final mid = memberId.trim();
    if (mid.isEmpty) {
      return const AskUserAnswerFailed('member_not_found');
    }
    final cli = SessionMemberCliResolver.resolve(
      persistedSession: tab.persistedSession,
      team: _teamForSessionTab(tab),
      memberId: mid,
      cliForMember: _shellFactory.cliForMember,
      globalPresets: _lifecycle.globalPresets,
    );
    return _askUserAnswer.answer(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
      shell: tab.memberShells[mid],
      askRequestId: askRequestId,
      optionIndex: optionIndex,
      answers: answers,
    );
  }

  /// Cancels a pending AskUserQuestion (PTY Esc or pending reject).
  Future<AskUserAnswerResult> cancelAskUserQuestion({
    required String sessionId,
    required String memberId,
    String? askRequestId,
  }) async {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) {
      return const AskUserAnswerFailed('session_not_found');
    }
    final mid = memberId.trim();
    if (mid.isEmpty) {
      return const AskUserAnswerFailed('member_not_found');
    }
    final cli = SessionMemberCliResolver.resolve(
      persistedSession: tab.persistedSession,
      team: _teamForSessionTab(tab),
      memberId: mid,
      cliForMember: _shellFactory.cliForMember,
      globalPresets: _lifecycle.globalPresets,
    );
    return _askUserAnswer.cancel(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
      shell: tab.memberShells[mid],
      askRequestId: askRequestId,
    );
  }

  TeamProfile? _teamForSessionTab(ChatTab tab) {
    final session = tab.persistedSession;
    if (session == null || session.sessionTeam.trim().isEmpty) return null;
    final teamId = session.sessionTeam.trim();
    if (_activeTeam?.id == teamId) return _activeTeam;
    return null;
  }

  /// Exercises History/Terminal submit → [onAfterTurnLatched] without PTY I/O.
  @visibleForTesting
  void debugNotifyOperatorTurnLatched(String sessionId, String memberId) =>
      _onOperatorTurnLatched(sessionId, memberId);

  void _pushPresenceTarget() {
    final cubit = _presenceCubit;
    if (cubit == null) return;
    final tab = _activeTab;
    if (tab == null) {
      cubit.updateTarget(null);
      return;
    }
    cubit.updateTarget(
      PresenceTarget(
        cliTeamName: tab.effectiveCliTeamName,
        memberToolConfigDir: tab.memberToolConfigDir,
        memberShells: tab.memberShells,
        session: _presenceSessionContext(tab),
      ),
    );
  }

  PresenceSessionContext? _presenceSessionContext(ChatTab tab) {
    final team = _activeTeam;
    if (team == null) return null;
    return PresenceSessionContext(
      team: team,
      appSession: tab.persistedSession,
      teamBus: tab.teamBus,
      globalPresets: _lifecycle.globalPresets,
    );
  }

  /// Switches the active workspace bucket and republishes its tabs into state.
  /// Called by the workspace page whenever the active workspace changes.
  void setActiveWorkspace(String workspaceId) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceId,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveWorkspaceTabs(restoredIndex);
  }

  /// Switches the chat tab bucket and session visibility scope in one [emit].
  /// Use on workspace tab activation so [setTeamSessionScope] does not fire a
  /// second rebuild on the next frame.
  void activateWorkspaceTab({
    required String workspaceTabKey,
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceTabKey,
      currentActiveIndex: state.activeTabIndex,
    );
    final scopeChanged = _dataStore.setScope(
      scopeSessionsToSelectedTeam: scopeSessionsToSelectedTeam,
      selectedTeamId: selectedTeamId,
    );
    final snapshot = scopeChanged
        ? _dataStore.deriveSnapshot(
            workspaces: state.workspaces,
            sessions: state.sessions,
          )
        : null;
    _publishActiveWorkspaceTabs(restoredIndex, snapshot: snapshot);
  }

  /// Re-emits the active bucket's tab infos without changing the workspace, after
  /// callers mutate the active bucket directly via [tabStore].
  @override
  void refreshActiveWorkspaceTabs() =>
      _publishActiveWorkspaceTabs(state.activeTabIndex);

  void _publishActiveWorkspaceTabs(
    int desiredIndex, {
    ChatDataSnapshot? snapshot,
  }) {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setNewChatActive(workspaceId, true);
      final empty = snapshot;
      emit(
        state.copyWith(
          tabs: const [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          clearSessionConnectingId: true,
          selectedMemberId: '',
          newChatActive: true,
          workspaces: empty?.workspaces,
          sessions: empty?.sessions,
          visibleWorkspaces: empty?.visibleWorkspaces,
          visibleSessions: empty?.visibleSessions,
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final index = desiredIndex.clamp(0, _tabStore.activeTabCount - 1);
    final newChatActive = _tabStore.isNewChatActive(workspaceId);
    if (newChatActive) {
      emit(
        state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: index,
          clearActiveSessionId: true,
          selectedMemberId: '',
          newChatActive: true,
          workspaces: snapshot?.workspaces,
          sessions: snapshot?.sessions,
          visibleWorkspaces: snapshot?.visibleWorkspaces,
          visibleSessions: snapshot?.visibleSessions,
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        newChatActive: false,
        workspaces: snapshot?.workspaces,
        sessions: snapshot?.sessions,
        visibleWorkspaces: snapshot?.visibleWorkspaces,
        visibleSessions: snapshot?.visibleSessions,
      ),
    );
    _pushPresenceTarget();
  }

  static void _defaultPostFrameScheduler(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  void setTeamSessionScope({
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    if (!_dataStore.setScope(
      scopeSessionsToSelectedTeam: scopeSessionsToSelectedTeam,
      selectedTeamId: selectedTeamId,
    )) {
      return;
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: state.sessions,
      ),
    );
  }

  void _emitSnapshot(ChatDataSnapshot snap, {ChatState? base}) {
    final s = base ?? state;
    emit(
      s.copyWith(
        workspaces: snap.workspaces,
        sessions: snap.sessions,
        visibleWorkspaces: snap.visibleWorkspaces,
        visibleSessions: snap.visibleSessions,
      ),
    );
  }

  ChatTab? get _activeTab => _tabStore.activeTab(state.activeTabIndex);

  TerminalSession? get currentSession {
    final tab = _activeTab;
    if (tab == null) return null;
    final memberShell = tab.memberShells[tab.selectedMemberId];
    return memberShell ?? tab.resumeSession;
  }

  /// Session workspace path for the active tab (used to resolve relative file links).
  String get activeTabWorkingDirectory {
    final tab = _activeTab;
    if (tab == null) return AppStorage.cwd;
    return _tabStore
        .workingDirectoryAndAddDirsForTab(
          tab,
          state.sessions,
          workspaces: state.workspaces,
        )
        .$1;
  }

  /// Last launch failure for the active tab, or [ChatState.sessionLaunchError].
  String? get activeLaunchError {
    if (!_tabStore.activeTabsIsEmpty) {
      final index = state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1);
      final error = _tabStore.activeTabs[index].info.launchError;
      if (error != null && error.isNotEmpty) return error;
    }
    final pending = state.sessionLaunchError;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Home index: workspace manifests only; sessions hydrate separately.
  Future<void> loadWorkspaceIndex(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceIndex(repo));
  }

  Future<void> hydrateAllSessions(SessionRepository repo) async {
    final sessions = await _dataStore.loadSessions(repo);
    _dataStore.markWorkspacesSessionsHydrated(
      state.workspaces.map((workspace) => workspace.workspaceId),
    );
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  /// Loads [workspaceId] sessions from disk when the UI needs them.
  Future<void> ensureSessionsForWorkspace(String workspaceId) async {
    final repo = _sessionRepository;
    final id = workspaceId.trim();
    if (repo == null || id.isEmpty) return;
    if (_dataStore.sessionsLoadedForWorkspace(id)) return;

    final inflight = _sessionHydrationByWorkspace[id];
    if (inflight != null) {
      await inflight;
      return;
    }

    final load = _hydrateWorkspaceSessions(repo, id);
    _sessionHydrationByWorkspace[id] = load;
    try {
      await load;
    } finally {
      _sessionHydrationByWorkspace.remove(id);
    }
  }

  Future<List<AppSession>> sessionsForWorkspaceReady(String workspaceId) async {
    await ensureSessionsForWorkspace(workspaceId);
    return sessionsForWorkspace(
      state.workspaces.where((w) => w.workspaceId == workspaceId).firstOrNull ??
          Workspace(workspaceId: workspaceId, folders: const [], createdAt: 0),
      state.sessions,
    );
  }

  Future<void> _hydrateWorkspaceSessions(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final sessions = await _dataStore.loadSessionsForWorkspace(
      repo,
      workspaceId,
    );
    if (isClosed) return;
    _emitSnapshot(
      _dataStore.mergeWorkspaceSessions(
        current: ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        workspaceId: workspaceId,
        workspaceSessions: sessions,
      ),
    );
  }

  /// Updates persisted-index mirrors in state and recomputes team-scoped sidebar lists.
  void ingestWorkspaceSessionSnapshot({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) {
    _emitSnapshot(
      _dataStore.deriveSnapshot(workspaces: workspaces, sessions: sessions),
    );
  }

  Future<AppSession> createSession(
    String workspaceId,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    TeamProfile? team,
    CliTool? cli,
    String? workingDirectory,
    String? fixedSessionId,
  }) async {
    final trimmedTeam = sessionTeamId.trim();
    final resolvedClis = trimmedTeam.isEmpty
        ? const <String, CliTool>{}
        : memberClis.isNotEmpty
        ? memberClis
        : team != null
        ? resolveSessionMemberCliLocks(
            team: team,
            rosterMembers: rosterMembers,
            globalPresets: _lifecycle.globalPresets,
          )
        : throw ArgumentError(
            'Team session create requires memberClis or team',
          );
    final session = await _dataStore.createSession(
      workspaceId,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: resolvedClis,
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
    );
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
    return session;
  }

  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) => _launchService.requestCreateAndOpenSession(request);

  /// Creates (or reuses) the workspace for [primaryPath], seeds a first session,
  /// reloads workspace data, and returns the workspace id so callers can navigate
  /// straight to the new workspace.
  Future<String> createWorkspaceWithFirstSession(
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    TeamProfile? team,
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final result = await _dataStore.createWorkspaceWithFirstSession(
      folders,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: memberClis,
      team: team,
      globalPresets: _lifecycle.globalPresets,
      display: display,
      allowDuplicate: allowDuplicate,
      identityRepository: identityRepository,
    );
    _emitSnapshot(result.snapshot);
    return result.workspaceId;
  }

  Future<void> addWorkspaceDirectory(
    SessionRepository repo,
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    final snap = await _dataStore.addWorkspaceDirectory(
      repo,
      workspace,
      folder,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
  }) async {
    _emitSnapshot(
      await _dataStore.updateWorkspaceMetadata(
        repo,
        workspaceId,
        display: display,
        defaultProfileId: defaultProfileId,
        rootSandboxEnvOptIn: rootSandboxEnvOptIn,
      ),
    );
  }

  Future<void> applyWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    _emitSnapshot(await _dataStore.applyWorkspaceIcon(repo, workspaceId, icon));
  }

  Future<void> importCustomWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    _emitSnapshot(
      await _dataStore.importCustomWorkspaceIcon(
        repo,
        workspaceId,
        localSourcePath,
      ),
    );
  }

  /// Opens the icon picker and applies the user's choice.
  ///
  /// Returns an error message when custom import fails; otherwise `null`.
  Future<String?> editWorkspaceIcon(
    BuildContext context,
    SessionRepository repo,
    Workspace workspace,
  ) async {
    final result = await showWorkspaceIconPickerDialog(
      context,
      workspace: workspace,
    );
    return switch (result) {
      WorkspaceIconPickerCancelled() => null,
      WorkspaceIconPickerUploadRequested() => _pickAndImportCustomIcon(
        repo,
        workspace.workspaceId,
      ),
      WorkspaceIconPickerCommitted(:final icon) => _applyCommittedIcon(
        repo,
        workspace.workspaceId,
        icon,
      ),
    };
  }

  Future<String?> _pickAndImportCustomIcon(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: WorkspaceIconStorage.allowedExtensions
          .where((ext) => ext != 'jpeg')
          .toList(growable: false),
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    try {
      await importCustomWorkspaceIcon(repo, workspaceId, path);
      return null;
    } on WorkspaceIconImportException catch (error) {
      return error.message;
    }
  }

  Future<String?> _applyCommittedIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    await applyWorkspaceIcon(repo, workspaceId, icon);
    return null;
  }

  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) =>
      _launchService.requestOpenSession(request);

  Future<void> scheduleTeamConfigValidation(TeamProfile team) =>
      _launchService.scheduleTeamConfigValidation(team);

  Future<void> openMemberTab(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
    bool scheduleTeamConfigValidation = true,
  }) => _launchService.openMemberTab(
    team,
    member,
    repo: repo,
    workspaceCwd: workspaceCwd,
    scheduleTeamConfigValidation: scheduleTeamConfigValidation,
  );

  Future<void> reconnectSshProfile(String profileId) =>
      _launchService.reconnectSshProfile(profileId);

  Future<void> _tearDownTab(ChatTab tab) async {
    final sessionId = tab.info.id;
    onHistorySeatsDispose?.call(sessionId);
    for (final session in tab.sessions) {
      session.dispose();
    }
    _agentAttentionCubit?.clearSession(sessionId);
    _followUpQueue.clearSession(sessionId);
    _agentStatusSeatLookup?.clearSession(sessionId);
    _teammateBusMcpGateway.unregisterAgentStatusSession(sessionId);
    await _teamBus.disposeSessionBus(sessionId);
    await tab.disposeBus();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.removeAt(index);
    _sessionRuntime.maybeStopIdleWatch();
    // Emit tabs before tearDown so working→idle sees the tab already gone
    // (idle notify must not fire for user-closed sessions).
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setNewChatActive(_tabStore.activeWorkspaceId, true);
      emit(
        state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          newChatActive: true,
          workingSessionIds: _sessionRuntime.recomputeWorkingSessions(),
        ),
      );
    } else {
      final newIdx = state.activeTabIndex >= _tabStore.activeTabCount
          ? _tabStore.activeTabCount - 1
          : state.activeTabIndex;
      final nextTab = _tabStore.activeTabs[newIdx];
      emit(
        state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
          newChatActive: false,
          workingSessionIds: _sessionRuntime.recomputeWorkingSessions(),
        ),
      );
    }
    unawaited(_tearDownTab(tab));
    _pushPresenceTarget();
  }

  /// Number of open session-backed tabs in [workspaceId]'s bucket (excludes
  /// `local-` scratch tabs, which have no persisted workspace session).
  int openTabCountForWorkspace(String workspaceId) =>
      _tabStore.sessionBackedCountForWorkspace(workspaceId);

  /// Closes (terminates) every open tab belonging to [workspaceId] by dropping
  /// its whole bucket and disposing each tab's sessions and team-bus.
  void closeTabsForWorkspace(String workspaceId) {
    final removed = _tabStore.removeWorkspace(workspaceId);
    if (removed.isEmpty) return;
    _sessionRuntime.maybeStopIdleWatch();
    // Republish whenever the active bucket was affected: either it was the
    // named bucket for this workspace, or it is the legacy empty-string bucket
    // and tabs were removed from it (legacy path before setActiveWorkspace).
    final activeIsAffected =
        workspaceId == _tabStore.activeWorkspaceId ||
        _tabStore.activeWorkspaceId.isEmpty;
    if (activeIsAffected) {
      _publishActiveWorkspaceTabs(0);
    }
    _updateWorkingSessions(_sessionRuntime.recomputeWorkingSessions());
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final removed = <ChatTab>[];
    for (var i = _tabStore.activeTabCount - 1; i >= 0; i--) {
      if (i == index) continue;
      removed.add(_tabStore.removeAt(i));
    }
    _sessionRuntime.maybeStopIdleWatch();
    final kept = _tabStore.activeTabs.single;
    _tabStore.setNewChatActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
        newChatActive: false,
        workingSessionIds: _sessionRuntime.recomputeWorkingSessions(),
      ),
    );
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
    _pushPresenceTarget();
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final removed = <ChatTab>[];
    for (var i = _tabStore.activeTabCount - 1; i > index; i--) {
      removed.add(_tabStore.removeAt(i));
    }
    _sessionRuntime.maybeStopIdleWatch();
    final active = _activeTab;
    _tabStore.setNewChatActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: state.activeTabIndex.clamp(
          0,
          _tabStore.activeTabCount - 1,
        ),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
        newChatActive: false,
        workingSessionIds: _sessionRuntime.recomputeWorkingSessions(),
      ),
    );
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
    _pushPresenceTarget();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.activeTabs[index];
    _tabStore.setNewChatActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        newChatActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  /// Sets Chat vs Terminal center body for an open session tab.
  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null || tab.workbenchView == view) return;
    tab.workbenchView = view;
    emit(state.copyWith(stateVersion: state.stateVersion + 1));
    if (view == SessionWorkbenchView.chat) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  /// Shows the new-chat landing for [workspaceId] without closing open tabs.
  void enterNewChat(String workspaceId) {
    final wasActive = _tabStore.activeWorkspaceId == workspaceId;
    if (!wasActive) {
      _tabStore.setNewChatActive(workspaceId, true);
      return;
    }
    _tabStore.setNewChatActive(workspaceId, true);
    final index = state.activeTabIndex.clamp(
      0,
      _tabStore.activeTabCount == 0 ? 0 : _tabStore.activeTabCount - 1,
    );
    emit(
      state.copyWith(
        activeTabIndex: index,
        clearActiveSessionId: true,
        selectedMemberId: '',
        newChatActive: true,
      ),
    );
    _pushPresenceTarget();
  }

  /// Leaves new-chat mode and selects the remembered session tab index.
  void exitNewChat() {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (!_tabStore.isNewChatActive(workspaceId)) return;
    _tabStore.setNewChatActive(workspaceId, false);
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setNewChatActive(workspaceId, true);
      emit(state.copyWith(newChatActive: true));
      return;
    }
    final index = state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1);
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        newChatActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  /// Clears new-chat mode without selecting a session (e.g. opening a file/diff tab).
  void dismissNewChat() {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (!_tabStore.isNewChatActive(workspaceId) && !state.newChatActive) {
      return;
    }
    _tabStore.setNewChatActive(workspaceId, false);
    if (state.newChatActive) {
      emit(state.copyWith(newChatActive: false));
    }
  }

  void syncTeam(TeamProfile team) {
    if (team.members.isEmpty) {
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    final newId = _tabStore.defaultMemberId(team);
    _activeTab?.selectedMemberId = newId;
    emit(state.copyWith(selectedMemberId: newId));
  }

  @override
  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    _activeTab?.selectedMemberId = memberId;
    emit(state.copyWith(selectedMemberId: memberId));
  }

  /// Whether the member's PTY is up (spawning through running).
  ///
  /// [memberId] is the shell key (`memberShells` / History `shellMemberId`),
  /// not only the active workspace tab.
  bool isMemberRunning({required String sessionId, required String memberId}) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    final shell = tab?.memberShells[memberId];
    return shell?.isRunning ?? false;
  }

  Future<void> launchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) => _launchService.launchAllMembers(
    team,
    repo: repo,
    workspaceCwd: workspaceCwd,
  );

  String selectedMemberName(TeamProfile team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession? ensureSession(TeamProfile team) =>
      _launchService.ensureSession(team);

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.connectWorkspaceSession(request, repo: repo);

  /// Rebuilds and replays the connect request for a failed/disconnected
  /// session — used by the launch-failure banner's Retry action.
  Future<void> retrySessionLaunch(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    AppSession? session;
    for (final s in state.sessions) {
      if (s.sessionId == id) {
        session = s;
        break;
      }
    }
    session ??= tab?.persistedSession;
    if (session == null) return;

    TeamProfile? team;
    final teamId = session.sessionTeam.trim();
    if (teamId.isNotEmpty) {
      team = await teamProfileById(teamId);
    }

    final request = buildRetryExistingSessionConnect(
      session: session,
      selectedMemberId: tab?.selectedMemberId ?? state.selectedMemberId,
      team: team,
    );
    if (request == null) {
      AppLogger.instance.w(
        'retrySessionLaunch: no team profile for team session $id '
        '(teamId=${teamId.isEmpty ? "?" : teamId})',
      );
      return;
    }
    await connectWorkspaceSession(request);
  }

  void disconnectSession() {
    final tab = activeTab;
    final sessionId = tab?.info.id;
    _launchService.disconnectSession();
    if (sessionId != null && sessionId.isNotEmpty) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  /// Disconnects [memberId] for [sessionId] (any open tab). Prefer this over
  /// [disconnectSession] when the target is not the active tab's selection
  /// (e.g. Resource Manager kill).
  void disconnectMemberShell(String sessionId, String memberId) {
    _launchService.disconnectMemberShell(sessionId, memberId);
    if (sessionId.trim().isNotEmpty) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.restartWorkspaceSession(request, repo: repo);

  @override
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {
    await repo.renameSession(sessionId, newName);
    final sessions = state.sessions.map((s) {
      if (s.sessionId == sessionId) return s.copyWith(display: newName);
      return s;
    }).toList();
    final tabs = state.tabs.map((t) {
      if (t.id == sessionId) return t.copyWith(title: newName);
      return t;
    }).toList();
    for (final tab in _tabStore.openTabs) {
      if (tab.info.id == sessionId) {
        tab.info = tab.info.copyWith(title: newName);
      }
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  /// Compose-landing / inject path: rename untitled session from first prompt.
  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _launchService.applyFirstPromptTitle(sessionId, firstPrompt);

  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.touchSession(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Persists session-level or per-member continue permission overrides.
  ///
  /// Returns false when the repo/session is missing or persistence fails.
  Future<bool> setSessionContinuePermission({
    required String sessionId,
    required bool dangerouslySkipPermissions,
    String? memberId,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchPermission(
      session: session,
      dangerouslySkipPermissions: dangerouslySkipPermissions,
      memberId: memberId,
    );
    try {
      await _continueOverridesController.persistPermission(
        repo: repo,
        patched: patched,
      );
      replaceSessionSnapshot(patched);
      return true;
    } on Object {
      return false;
    }
  }

  /// Persists a same-CLI preset for Simple identity or a team member override.
  ///
  /// Returns false when [preset.cli] does not match [lockedCli] (no disk write).
  Future<bool> setSessionContinuePreset({
    required String sessionId,
    required CliPreset preset,
    String? memberId,
    required CliTool lockedCli,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchPreset(
      session: session,
      preset: preset,
      memberId: memberId,
      lockedCli: lockedCli,
    );
    if (patched == null) return false;
    await _continueOverridesController.persistPreset(
      repo: repo,
      patched: patched,
      memberId: memberId,
    );
    replaceSessionSnapshot(patched);
    return true;
  }

  /// Persists manual provider/model/effort for Simple identity (clears preset).
  ///
  /// Returns false when the session is not Simple or missing.
  Future<bool> setSessionContinueCustom({
    required String sessionId,
    required String provider,
    required String model,
    required String effort,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchCustom(
      session: session,
      provider: provider,
      model: model,
      effort: effort,
    );
    if (patched == null) return false;
    await _continueOverridesController.persistCustom(
      repo: repo,
      patched: patched,
    );
    replaceSessionSnapshot(patched);
    return true;
  }

  /// Persists a manual session arrangement. [orderedSessionIds] is the new
  /// top-to-bottom order (used by [AppSessionSort.manual]).
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    // Optimistic: stamp the new sortOrder in memory and emit immediately so the
    // list stays where the user dropped it, then persist on disk in the
    // background. Awaiting the per-file writes + a full reload first made the
    // row snap back, then jump once persistence finished (~1-2s later).
    final orderById = <String, int>{
      for (var i = 0; i < orderedSessionIds.length; i++)
        orderedSessionIds[i]: i + 1,
    };
    final sessions = [
      for (final s in state.sessions)
        orderById.containsKey(s.sessionId)
            ? s.copyWith(sortOrder: orderById[s.sessionId])
            : s,
    ];
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions),
    );
    await repo.reorderSessions(orderedSessionIds);
  }

  Future<void> toggleSessionPin(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.toggleSessionPin(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final session = state.sessions
        .where((s) => s.sessionId == sessionId)
        .firstOrNull;
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    ChatTab? removedTab;
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) {
      removedTab = _tabStore.removeAt(idx);
      _sessionRuntime.maybeStopIdleWatch();
    }
    final tabs = _tabStore.activeTabs.map((t) => t.info).toList();
    final working = _sessionRuntime.recomputeWorkingSessions();

    if (wasActive && !_tabStore.activeTabsIsEmpty) {
      final newIdx = idx < _tabStore.activeTabCount
          ? idx
          : _tabStore.activeTabCount - 1;
      final nextTab = _tabStore.activeTabs[newIdx];
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: tabs,
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
          workingSessionIds: working,
        ),
      );
    } else if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setNewChatActive(_tabStore.activeWorkspaceId, true);
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          newChatActive: true,
          workingSessionIds: working,
        ),
      );
    } else {
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(tabs: tabs, workingSessionIds: working),
      );
    }

    if (removedTab != null) {
      await _tearDownTab(removedTab);
    }

    _emitSnapshot(await _dataStore.deleteSessionRecord(repo, sessionId));
    if (session != null) {
      await _automationRepository.disableForSession(
        session.workspaceId,
        sessionId,
      );
      _notifyAutomationsChanged();
    }
  }

  Future<Workspace> cloneWorkspace(
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await _dataStore.cloneWorkspace(
      repo,
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    _emitSnapshot(result.snapshot);
    return result.workspace;
  }

  Future<void> deleteWorkspace(
    SessionRepository repo,
    String workspaceId,
  ) async {
    Workspace? workspace;
    for (final p in state.workspaces) {
      if (p.workspaceId == workspaceId) {
        workspace = p;
        break;
      }
    }
    if (workspace == null) return;
    for (final sid in workspace.sessionIds.toList()) {
      await deleteSession(repo, sid);
    }
    await _automationRepository.removeWorkspace(workspaceId);
    _notifyAutomationsChanged();
    _emitSnapshot(await _dataStore.deleteWorkspaceRecord(repo, workspaceId));
  }

  void addSystemMessage(String content) {
    final target = currentSession;
    target?.write('\r\n[system] $content\r\n');
  }

  bool hasTeamBusResources(String sessionId) =>
      _teamBus.hasTeamBusResources(sessionId);

  @visibleForTesting
  Uri? teammateBusMcpEndpointForSession(String sessionId) =>
      _teamBus.teammateBusMcpEndpointForSession(sessionId);

  @override
  Future<void> close() async {
    if (isClosed) return;
    await _agentAttentionSub?.cancel();
    _agentAttentionSub = null;
    _sessionRuntime.disposeIdleWatch();
    final busDisposals = <Future<void>>[];
    for (final tab in _tabStore.openTabs) {
      busDisposals.add(_tearDownTab(tab));
    }
    await Future.wait(busDisposals);
    _tabStore.clear();
    await super.close();
  }
}
