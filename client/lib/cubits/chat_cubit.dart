import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/failed_message_record.dart';
import '../models/session_activity.dart';
import '../models/workspace.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_launch_context.dart';
import '../models/app_session.dart';
import '../services/team/member_presence_service.dart';
import '../models/workspace_icon_picker_result.dart';
import '../models/workspace_icon_ref.dart';
import '../models/team_config.dart';
import '../models/runtime_target.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/automation_repository.dart';
import '../repositories/session_repository.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/session_activity_reduce.dart';
import '../services/session/failed_message_store.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/session/session_member_cli_locks.dart';
import '../services/remote/remote_cli_readiness.dart';
import '../services/team_bus/artifacts/artifact_registry.dart';
import '../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_permission_request.dart';
import '../services/agent_status/agent_status_event.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/agent_status/ask_user_answer_pending_store.dart';
import '../services/agent_status/general_permission_request_gate.dart';
import '../services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'agent_attention_cubit.dart';
import '../services/launch/launch_factory.dart';
import '../services/launch/session_connect_orchestrator.dart';
import '../services/launch/workspace_provision_coordinator.dart';
import '../services/install/install_job_registry.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/cli/registry/capabilities/team_behavior_capability.dart';
import '../services/cli/preset_resolver.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/ask_user_question_answer_service.dart';
import '../services/terminal/exit_plan_mode_approval_service.dart';
import '../services/terminal/member_turn_interrupt_service.dart';
import '../services/terminal/session_member_cli_resolver.dart';
import '../services/termux/termux_connection_gate.dart';
import '../services/terminal/terminal_theme_for_launch.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/compose/compose_draft_cache.dart';
import '../services/follow_up/follow_up_queue.dart';
import '../services/follow_up/follow_up_queue_drainer.dart';
import '../pages/chat/history_continue_delivery.dart';
import '../pages/chat/operator_history_send.dart';
import '../pages/chat/session_chat_continue_seat.dart';
import '../pages/chat/session_history_review_submit.dart';
import '../utils/session/workspace_sessions.dart';
import '../widgets/workspace_icon_picker_dialog.dart';
import '../utils/logging/logger_utils.dart';
import 'chat/session_launch_retry.dart';
import 'chat/session_connect_settle.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/session_launch_service.dart';
import 'chat/tab_member_materializer.dart';
import 'chat/operator_delivery_in_flight.dart';
import 'chat/tab_session_runtime_coordinator.dart';
import 'chat/tab_team_bus_coordinator.dart';
import 'layout_cubit.dart';
import 'member_presence_cubit.dart';
import 'workbench/workbench_tab.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/session_connect_request.dart';
import 'chat/model/session_create_request.dart';
import 'chat/model/session_open_request.dart';
import 'chat/model/session_open_status.dart';
import 'chat/model/session_workbench_view.dart';
import 'chat/session_continue_overrides_controller.dart';
import 'session/history_store.dart';
import 'session/session_pod.dart';
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
    bool Function()? reclaimIdleTerminalsEnabled,
    int Function()? reclaimIdleTerminalAfterSeconds,
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
    AskUserAnswerPendingStore? askUserAnswerPendingStore,
    AskUserQuestionAnswerService? askUserQuestionAnswerService,
    GeneralPermissionRequestGate? generalPermissionGate,
    ExitPlanModeApprovalService? exitPlanApprovalService,
    InMemoryFollowUpQueueStore? followUpQueueStore,
    FollowUpQueueDrainer? followUpQueueDrainer,
    Future<TeamProfile?> Function(String teamId)? teamById,
    required AutomationRepository automationRepository,
    LayoutCubit? layoutCubit,
    RemoteCliReadinessService? remoteCliReadiness,
    InstallJobRegistry? installJobRegistry,
    bool Function()? termuxConnectedResolver,
    String Function()? termuxDisconnectedWorkOpsMessageResolver,
    RuntimeTarget Function()? termuxGateHomeResolver,
    PromptDeliveryCoordinator? Function()? promptDeliveries,
  }) : _remoteBusResolver = remoteBusResolver,
       _promptDeliveries = promptDeliveries,
       _remoteCliReadiness = remoteCliReadiness,
       _sessionConnect = sessionConnect,
       _installJobRegistry = installJobRegistry,
       _teamById = teamById,
       _teammateBusMcpGateway =
           teammateBusMcpGateway ?? TeammateBusMcpGateway(),
       _agentStatusSeatLookup = agentStatusSeatLookup,
       _agentAttentionCubit = agentAttentionCubit,
       _askUserAnswerPendingStore = askUserAnswerPendingStore,
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
       _reclaimIdleTerminalsEnabled = reclaimIdleTerminalsEnabled,
       _reclaimIdleTerminalAfterSeconds = reclaimIdleTerminalAfterSeconds,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       _followUpQueue = followUpQueueStore ?? InMemoryFollowUpQueueStore(),
       _termuxConnectedResolver = termuxConnectedResolver,
       _termuxDisconnectedWorkOpsMessageResolver =
           termuxDisconnectedWorkOpsMessageResolver,
       _termuxGateHomeResolver = termuxGateHomeResolver,
       super(const ChatState()) {
    _exitPlanApproval =
        exitPlanApprovalService ?? ExitPlanModeApprovalService();
    _askUserAnswer =
        askUserQuestionAnswerService ??
        AskUserQuestionAnswerService(
          store: askUserAnswerPendingStore,
          generalPermissionGate: generalPermissionGate,
        );
    _followUpDrainer =
        followUpQueueDrainer ??
        FollowUpQueueDrainer(
          store: _followUpQueue,
          deliver: (seat, content) => _deliverFollowUpAtSeat(seat, content),
        );
    final attention = _agentAttentionCubit;
    if (attention != null) {
      var previous = attention.state;
      _agentAttentionSub = attention.stream.listen((next) {
        if (!isClosed) {
          _endMemberTurnsForNewlyDoneSeats(previous, next);
          _updateSessionActivities();
        }
        previous = next;
      });
    }
  }

  /// Fired when History should drop cache / reload (disconnect or switch back).
  void Function(String sessionId)? onSessionHistoryStale;

  final _operatorMailboxQueued =
      StreamController<OperatorMailboxQueuedEvent>.broadcast();
  Stream<OperatorMailboxQueuedEvent> get operatorMailboxQueued =>
      _operatorMailboxQueued.stream;

  /// Fired when a session tab is torn down so History can dispose its seats.
  void Function(String sessionId)? onHistorySeatsDispose;

  /// Domain → workbench-bar handshake: fired after a new session tab surfaces
  /// so the bar can be fed (wired to [WorkbenchChatBridge.onSessionTabOpened]
  /// by the app shell after construction).
  void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })?
  onSessionTabOpened;

  /// Domain → bar port: routes session closes, landing, and workspace closes
  /// through the workbench bar. Wired to the [WorkbenchChatBridge] by the app
  /// shell after construction (null until then — the domain falls back to a
  /// direct teardown).
  ChatWorkbenchPort? _workbenchPort;
  set workbenchPort(ChatWorkbenchPort? value) => _workbenchPort = value;

  final RemoteBusBindingResolver? _remoteBusResolver;
  final RemoteCliReadinessService? _remoteCliReadiness;
  final InstallJobRegistry? _installJobRegistry;
  final SessionConnectOrchestrator? _sessionConnect;

  /// User-driven remote CLI locate/install (Machines panel + landing gate).
  RemoteCliReadinessService? get remoteCliReadiness => _remoteCliReadiness;
  final Future<TeamProfile?> Function(String teamId)? _teamById;
  final bool Function()? _termuxConnectedResolver;
  final String Function()? _termuxDisconnectedWorkOpsMessageResolver;
  final RuntimeTarget Function()? _termuxGateHomeResolver;
  final PromptDeliveryCoordinator? Function()? _promptDeliveries;
  String? Function(AppSession session)? _teamGenerationTokenIssuer;
  final TeammateBusMcpGateway _teammateBusMcpGateway;
  final AgentStatusSeatLookup? _agentStatusSeatLookup;
  final AgentAttentionCubit? _agentAttentionCubit;
  final AskUserAnswerPendingStore? _askUserAnswerPendingStore;
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

  /// Per-session [SessionPod] values, keyed by session id. The launch/connect
  /// lifecycle (Task 6) drives `phase`; the workbench overlay derives from the
  /// active pod instead of global connecting sentinels.
  final Map<String, SessionPod> _pods = {};

  /// Pre-session materialization (the former `'pending'` connect): no real pod
  /// exists yet, but a connect is in flight so concurrent connects must wait.
  bool _materializingInFlight = false;

  /// Wired post-bootstrap (the AiHistoryLoader is built after ChatCubit). When
  /// set, pods own a [HistoryStore]; consumers fall back to the global cubit
  /// until then.
  AiHistoryLoader? historyLoader;
  static const _continueOverridesController =
      SessionContinueOverridesController();
  final Map<String, Future<void>> _sessionHydrationByWorkspace = {};
  late final SessionLaunchService _launchService = SessionLaunchService(
    this,
    termuxWorkOpsBlockFor: _termuxWorkOpsBlockFor,
    onSessionTabOpened: _forwardSessionTabOpened,
  );

  /// Forwards to [onSessionTabOpened], resolved at call time so wiring set by
  /// the app shell after construction is always observed (the launch service is
  /// built lazily on first session open).
  void _forwardSessionTabOpened(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) {
    onSessionTabOpened?.call(
      workspaceId,
      sessionId,
      preview: preview,
      activate: activate,
    );
  }

  late final OperatorDeliveryInFlight _operatorDeliveryInFlight =
      OperatorDeliveryInFlight(
        onChanged: () {
          if (!isClosed) _updateSessionActivities();
        },
      );
  final _forcedDisposition = <String, SessionTurnDisposition>{};
  late final TabSessionRuntimeCoordinator _sessionRuntime =
      TabSessionRuntimeCoordinator(
        tabStore: _tabStore,
        shellFactory: _shellFactory,
        activeTeam: () => _activeTeam,
        isClosed: () => isClosed,
        globalPresets: () => _lifecycle.globalPresets,
        activeSessionId: () => activeTab?.info.id,
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
        sessionBusyFromDeliveryInFlight: (sessionId) =>
            _operatorDeliveryInFlight.isInFlight(sessionId),
        onAfterIdleWatchTick: () => unawaited(_onIdleWatchTick()),
        onAfterTurnLatched: _onOperatorTurnLatched,
        onUserActivity: _launchService.touchOnUserActivity,
        onAfterTurnEnded: _onTurnEnded,
        memberCli: (tab, memberId) {
          final session = tab.persistedSession;
          if (session == null) return null;
          return SessionMemberCliResolver.resolve(
            persistedSession: session,
            team: _activeTeam,
            memberId: memberId,
            cliForMember: (team, id, {globalPresets = const []}) =>
                memberLaunchCli(
                  team: team,
                  member:
                      _rosterMemberFor(team, id) ??
                      TeamMemberConfig(id: id, name: id),
                  globalPresets: globalPresets,
                ),
            globalPresets: _lifecycle.globalPresets,
          );
        },
        reclaimEnabled: () => _reclaimIdleTerminalsEnabled?.call() ?? false,
        reclaimIdleAfterSeconds: () =>
            _reclaimIdleTerminalAfterSeconds?.call() ?? 180,
        onReclaimMember: _launchService.discardMemberTerminal,
        isSessionPinned: (sessionId) {
          for (final s in state.sessions) {
            if (s.sessionId == sessionId) return s.pinned;
          }
          return false;
        },
        promptDeliveries: _promptDeliveries?.call(),
      );
  late final MemberTurnInterruptService _turnInterrupt =
      MemberTurnInterruptService(
        cliToolRegistry: CliToolRegistry.builtIn(),
        abortMemberInject: _sessionRuntime.abortMemberInject,
      );
  late final AskUserQuestionAnswerService _askUserAnswer;
  late final ExitPlanModeApprovalService _exitPlanApproval;
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
  final bool Function()? _reclaimIdleTerminalsEnabled;
  final int Function()? _reclaimIdleTerminalAfterSeconds;
  final SessionLifecycleService _lifecycle;
  final SessionRepository? _sessionRepository;

  @override
  ChatTabStore get tabStore => _tabStore;

  @override
  void onTabRunningChanged() => _pushPresenceTarget();

  // ===== SessionPod registry =====

  /// Runtime pod for [sessionId], or null when none exists yet.
  @override
  SessionPod? podRuntime(String sessionId) => _pods[sessionId.trim()];

  /// Seeds an idle runtime pod for [sessionId] if absent and returns it.
  /// The pod is a [ChangeNotifier] — consumers listen directly; no global emit.
  @override
  SessionPod ensurePodRuntime(String sessionId) =>
      _pods.putIfAbsent(sessionId.trim(), () {
        final tab = _tabStore.openTabBySessionId(sessionId.trim());
        final sid = sessionId.trim();
        final loader = historyLoader;
        return SessionPod(
          sessionId: sid,
          workspaceId: tab?.workspaceId ?? '',
          history: loader == null
              ? null
              : HistoryStore(
                  loader: loader,
                  loadMailboxRecords: (s, m) async {
                    final bus = _tabStore.openTabBySessionId(s)?.teamBus;
                    if (bus == null) return const [];
                    return bus.memberMailRecords(m);
                  },
                ),
        );
      });

  /// Observable state of the pod for [sessionId], or null.
  SessionPodState? podFor(String sessionId) => _pods[sessionId.trim()]?.state;

  /// Observable state of the active session's pod (foreground tab), or null.
  SessionPodState? get activePod {
    final id = activeTab?.info.id;
    if (id == null || id.isEmpty) return null;
    return _pods[id]?.state;
  }

  // ===== History seed routing (pod store first, global cubit fallback) =====

  /// Fallback sinks wired to AiHistoryCubit post-bootstrap, used only when a
  /// pod has no HistoryStore yet.
  void Function(String sessionId, String memberId, String text)?
  onSeedHistoryPending;
  void Function(String sessionId, String text)? onCancelSeedHistoryPending;

  /// Seeds an optimistic user bubble on the pod's HistoryStore (or the global
  /// cubit as fallback) so Chat shows the user turn before connect/deliver.
  void seedHistoryPending({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final store = podRuntime(sessionId)?.history;
    if (store != null) {
      store.seedPendingUser(
        sessionId: sessionId,
        memberId: memberId,
        text: text,
      );
      return;
    }
    onSeedHistoryPending?.call(sessionId, memberId, text);
  }

  /// Cancels a landing seed when send fails.
  void cancelHistorySeedPending({
    required String sessionId,
    required String text,
  }) {
    final store = podRuntime(sessionId)?.history;
    if (store != null) {
      store.cancelSeedPendingUser(sessionId: sessionId, text: text);
      return;
    }
    onCancelSeedHistoryPending?.call(sessionId, text);
  }

  FailedMessageStore get _failedMessageStore =>
      FailedMessageStore(fs: AppStorage.fs, rootPath: AppStorage.appDataRoot);

  /// Persists the optimistic user bubble for landing create+send (same record
  /// model as History continue) so it survives tab close and app restart.
  Future<FailedMessageRecord?> persistHistoryPending({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    required String text,
    String? deliveryId,
    bool preserveText = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty ||
        workspaceId.trim().isEmpty ||
        sessionId.trim().isEmpty) {
      return null;
    }
    final history = ensurePodRuntime(sessionId).history;
    if (history == null) return null;
    final seat = history.memberSeat(sessionId: sessionId, memberId: memberId);
    return seat.persistPendingUser(
      store: _failedMessageStore,
      workspaceId: workspaceId,
      sessionId: sessionId,
      text: preserveText ? text : trimmed,
      deliveryId: deliveryId,
    );
  }

  /// Marks a persisted landing bubble failed instead of rolling it back.
  Future<void> markHistoryPendingFailed({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    required FailedMessageRecord record,
  }) async {
    final history = podRuntime(sessionId)?.history;
    if (history == null) return;
    final seat = history.memberSeat(sessionId: sessionId, memberId: memberId);
    await seat.markPendingFailed(
      store: _failedMessageStore,
      workspaceId: workspaceId,
      sessionId: sessionId,
      record: record,
    );
  }

  /// Clears a delivered pending bubble from memory and disk.
  Future<void> clearHistoryPending({
    required String workspaceId,
    required String sessionId,
    required String memberId,
    required String recordId,
  }) async {
    final trimmed = recordId.trim();
    if (trimmed.isEmpty) return;
    await _failedMessageStore.remove(workspaceId, sessionId, trimmed);
    await podRuntime(sessionId)?.history
        ?.memberSeat(sessionId: sessionId, memberId: memberId)
        .removePendingById(trimmed);
  }

  /// Releases a session's pod: closes its HistoryStore and drops the registry
  /// entry. Called on tab teardown; idempotent.
  Future<void> disposePod(String sessionId) async {
    final pod = _pods.remove(sessionId.trim());
    if (pod == null) return;
    await pod.history?.close();
  }

  // ===== SessionLaunchHost =====

  // ===== SessionLaunchHost =====

  @override
  void applyState(ChatState next) => emit(next);

  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
    workspaces: state.workspaces,
    sessions: state.sessions,
    visibleWorkspaces: state.visibleWorkspaces,
    visibleSessions: state.visibleSessions,
  );

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => _emitSnapshot(snapshot);

  @override
  void appendSessionSnapshot(AppSession session) {
    _emitSnapshot(_dataStore.appendSession(stateSnapshot(), session));
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    _emitSnapshot(_dataStore.replaceSession(stateSnapshot(), session));
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    _emitSnapshot(_dataStore.removeSession(stateSnapshot(), sessionId));
  }

  @override
  void closeSessionTab(String sessionId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return;
    // Domain-driven close: remove from the bar; the port calls teardownSession.
    final port = _workbenchPort;
    if (port != null) {
      port.onSessionTabClosed(tab.workspaceId, sessionId);
    } else {
      unawaited(teardownSession(sessionId));
    }
  }

  @override
  void pushPresenceTarget() => _pushPresenceTarget();

  @override
  ChatTab? get activeTab {
    final wsId = _tabStore.activeWorkspaceId;
    final port = _workbenchPort;
    if (wsId.isNotEmpty && port != null) {
      final tabId = port.centerActiveForScope(wsId);
      if (tabId != null && tabId.kind == WorkbenchTabKind.session) {
        final tab = _tabStore.openTabBySessionId(tabId.id);
        if (tab != null) return tab;
      }
      // A non-session tab (file/diff) is center-active: no session is active
      // in this workspace — never fall through to another workspace's tabs.
      if (tabId != null) return null;
      // Landing (center-active null): legacy local-tab runtimes that have not
      // been bar-fed stay reachable within this workspace.
      return _tabStore.tabsForWorkspace(wsId).firstOrNull;
    }
    // Port unwired (tests / legacy): first open tab wins.
    return _tabStore.openTabs.firstOrNull;
  }

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
  String? Function(AppSession session)? get teamGenerationTokenIssuer =>
      _teamGenerationTokenIssuer;

  void setTeamGenerationTokenIssuer(
    String? Function(AppSession session)? issuer,
  ) {
    _teamGenerationTokenIssuer = issuer;
  }

  @override
  AgentStatusSeatLookup? get agentStatusSeatLookup => _agentStatusSeatLookup;

  @override
  AgentAttentionCubit? get agentAttentionCubit => _agentAttentionCubit;

  @override
  AskUserAnswerPendingStore? get askUserAnswerPendingStore =>
      _askUserAnswerPendingStore;

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
  InstallJobRegistry? get installJobRegistry => _installJobRegistry;

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
  /// Session spinners follow [SessionActivity.isBusy] on [ChatState.sessionActivities].
  void _updateSessionActivities() {
    if (isClosed) return;
    final reasons = _sessionRuntime.computeReasons();
    final next = <String, SessionActivity>{};
    for (final tab in _tabStore.openTabs) {
      final id = tab.info.id;
      final prev = state.sessionActivities[id] ?? const SessionActivity();
      final forced = _forcedDisposition.remove(id);
      next[id] = reduceSessionActivity(
        previous: prev,
        reasons: reasons[id] ?? const {},
        forced: forced,
      );
    }
    if (!mapEquals(next, state.sessionActivities)) {
      emit(state.copyWith(sessionActivities: next));
    }
    _syncFollowUpQueuesWithWorking();
  }

  Future<void> _onIdleWatchTick() async {
    await _presenceCubit?.tickFromIdleWatch();
    if (isClosed) return;
    _updateSessionActivities();
  }

  Future<T> withOperatorDeliveryInFlight<T>(
    String sessionId,
    Future<T> Function() action,
  ) => _operatorDeliveryInFlight.run(sessionId, action);

  void endOperatorDeliveryInFlight(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    _forcedDisposition[id] = SessionTurnDisposition.cancelled;
    _operatorDeliveryInFlight.clear(id);
  }

  @visibleForTesting
  bool isOperatorDeliveryInFlight(String sessionId) =>
      _operatorDeliveryInFlight.isInFlight(sessionId);

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

    if (message.trim().isEmpty) {
      return const HistoryContinueSubmitResult.failed();
    }

    return withOperatorDeliveryInFlight(
      sessionId,
      () => submitSessionHistoryReviewMessage(
        sessionId: sessionId,
        memberId: shellMemberId,
        message: message,
        connectRequest: ExistingSessionConnect(
          session: session,
          team: team,
          member: connectMember,
          preserveWorkbenchView: preserveWorkbenchView,
        ),
        resolveChannel: () =>
            resolveOperatorMessageChannel(sessionId, shellMemberId),
        connectWorkspaceSession: connectWorkspaceSession,
        ensureMemberInputReady: (sid, mid, {bool directToPty = false}) =>
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
      ),
    );
  }

  @protected
  HistoryContinueChannel resolveOperatorMessageChannel(
    String sessionId,
    String shellMemberId,
  ) {
    final bus = _sessionRuntime.busForSession(sessionId);
    return resolveHistoryContinueChannel(
      teamBusInstalled: bus != null,
      memberWaitingForMessage: bus?.isWaitingForMessage(shellMemberId) ?? false,
      memberInTurn: bus?.isMemberInTurn(shellMemberId) ?? false,
    );
  }

  Future<HistoryContinueSubmitResult> _deliverFollowUpAtSeat(
    String seat,
    String content,
  ) async {
    final parsed = parseFollowUpSeatKey(seat);
    if (parsed == null) return const HistoryContinueSubmitResult.failed();

    final sessionId = parsed.$1;
    final memberId = parsed.$2;
    final session = _tabStore.openTabBySessionId(sessionId)?.persistedSession;
    if (session == null) {
      return const HistoryContinueSubmitResult.failed();
    }

    final isPersonal = session.sessionTeam.trim().isEmpty;
    TeamProfile? team;
    if (!isPersonal) {
      team = await teamProfileById(session.sessionTeam);
    }
    final connectMember = !isPersonal && team != null
        ? resolveSessionChatContinueMember(
            session: session,
            team: team,
            selectedMemberId: memberId,
          )
        : null;
    final shellMemberId = isPersonal
        ? session.sessionId
        : (connectMember?.id ?? memberId);
    final workspaceId = session.workspaceId;

    return runOperatorHistorySend(
      sessionId: sessionId,
      memberId: shellMemberId,
      text: content,
      ports: (
        resolveChannel: () async =>
            resolveOperatorMessageChannel(sessionId, shellMemberId),
        persistPending: (text) => persistHistoryPending(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: shellMemberId,
          text: text,
        ),
        markFailed: (record) => markHistoryPendingFailed(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: shellMemberId,
          record: record,
        ),
        clearPending: (record) => clearHistoryPending(
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: shellMemberId,
          recordId: record.id,
        ),
        deliver: (text) => submitSessionOperatorMessage(
          sessionId: sessionId,
          memberId: shellMemberId,
          message: text,
        ),
        onPtyDelivered: () {
          onSessionHistoryStale?.call(sessionId);
          softReloadPodHistorySeat(sessionId, shellMemberId);
        },
        onMailboxQueued: (event) {
          if (!_operatorMailboxQueued.isClosed) {
            _operatorMailboxQueued.add(event);
          }
        },
        refreshMailboxTimeline: () async {
          await podRuntime(sessionId)?.history
              ?.seatOf(sessionId: sessionId, memberId: shellMemberId)
              ?.refreshMailboxTimeline();
        },
      ),
    );
  }

  @protected
  void softReloadPodHistorySeat(String sessionId, String memberId) {
    unawaited(
      podRuntime(sessionId)?.history
              ?.memberSeat(sessionId: sessionId, memberId: memberId)
              .softReload(force: true) ??
          Future<void>.value(),
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
    _updateSessionActivities();
  }

  /// PTY-quiet turn end — clears the attention working seat for CLIs whose
  /// done event may be unreliable (requiresPtyFallback). Only fires after the
  /// shell turn latch ends (PTY quiet after turn activity), so it never
  /// mis-clears a `waiting` permission seat (clearWorkingIfWorking is
  /// waiting-safe) and defers while a doorbell is still pending.
  void _onTurnEnded(String sessionId, String memberId) {
    final attention = _agentAttentionCubit;
    if (attention == null || memberId.trim().isEmpty) return;
    final tab = _tabStore.openTabBySessionId(sessionId);
    final session = tab?.persistedSession;
    if (tab == null || session == null) return;

    final cli = SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: _activeTeam,
      memberId: memberId,
      cliForMember: (team, id, {globalPresets = const []}) => memberLaunchCli(
        team: team,
        member:
            _rosterMemberFor(team, id) ?? TeamMemberConfig(id: id, name: id),
        globalPresets: globalPresets,
      ),
      globalPresets: _lifecycle.globalPresets,
    );
    final cap = cliRegistry.capability<TeamBehaviorCapability>(cli);
    if (cap == null || !cap.requiresPtyFallback) return;
    final bus = tab.teamBus;
    if (bus != null && bus.hasPendingDoorbell(memberId)) return;
    attention.clearWorkingIfWorking(sessionId: sessionId, memberId: memberId);
    _updateSessionActivities();
  }

  /// Roster member by id from the active team, or null when the member is not
  /// in the team (personal sessions resolve their CLI via [AppSession.cli]).
  TeamMemberConfig? _rosterMemberFor(TeamProfile team, String memberId) {
    for (final member in team.members) {
      if (member.id == memberId) return member;
    }
    return null;
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

  /// Seat attention just became [AgentSeatAttention.done] — end that member's
  /// turn latch. PTY quiet no longer ends Claude/Codex/OpenCode/flashskyai;
  /// Cursor still ends on quiet, and this path is idempotent if quiet won.
  void _endMemberTurnsForNewlyDoneSeats(
    AgentAttentionState previous,
    AgentAttentionState next,
  ) {
    for (final entry in next.seats.entries) {
      if (entry.value.attention != AgentSeatAttention.done) continue;
      if (previous.seats[entry.key]?.attention == AgentSeatAttention.done) {
        continue;
      }
      final sep = entry.key.indexOf('\u0000');
      if (sep <= 0) continue;
      final sessionId = entry.key.substring(0, sep);
      final memberId = entry.key.substring(sep + 1);
      if (memberId.isEmpty) continue;
      _sessionRuntime.endMemberTurn(sessionId, memberId);
    }
  }

  @visibleForTesting
  void updateWorkingSessionsForTest(Set<String> ids) {
    if (isClosed) return;
    emit(
      state.copyWith(
        sessionActivities: {
          for (final id in ids)
            id: const SessionActivity(
              reasons: {SessionBusyReason.inTurn},
              hadTurn: true,
            ),
        },
      ),
    );
  }

  @visibleForTesting
  void debugTickIdleWatch() => _sessionRuntime.debugTickIdleWatch();

  @visibleForTesting
  void debugTickReclaimWatch() => _sessionRuntime.debugTickReclaimWatch();

  @visibleForTesting
  void debugRecomputeWorkingSessions() => _updateSessionActivities();

  /// Clears [SessionActivity.isReadyToChat] after idle-notify consumes it.
  void acknowledgeSessionReady(String sessionId) {
    if (isClosed) return;
    final current = state.sessionActivities[sessionId];
    if (current == null || current == const SessionActivity()) return;
    emit(
      state.copyWith(
        sessionActivities: {
          ...state.sessionActivities,
          sessionId: const SessionActivity(),
        },
      ),
    );
  }

  /// Seat-level working for compose stop button (mirrors members panel rules).
  bool isMemberWorking(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return false;

    final presence = _presenceCubit?.state.presence ?? const {};
    final sessionWorking = _sessionRuntime.sessionWorking;
    final usesPresenceSnapshot = sessionWorking.usesPresenceSnapshotForTab(
      tab: tab,
      activeSessionId: activeTab?.info.id,
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
    final sid = sessionId ?? activeTab?.info.id;
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

    // Clear the seat before PTY writes so sidebar / compose Stop drop immediately
    // instead of waiting for interrupt-plan gaps. An interrupted turn never
    // reaches a CLI `Stop`/done hook (the PTY may die non-zero, or the CLI parks
    // at a prompt), so without this the attention busy arm stays lit until TTL.
    clearAgentStatusSeat(sessionId: sid, memberId: mid);
    _sessionRuntime.endMemberTurn(sid, mid);
    _forcedDisposition[sid] = SessionTurnDisposition.cancelled;
    endOperatorDeliveryInFlight(sid);
    _updateSessionActivities();
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
  /// On [AskUserAnswerOk], optimistically dismisses the waiting card via
  /// [AgentAttentionCubit.markAskAnswered]. Failures leave attention unchanged.
  Future<AskUserAnswerResult> answerAskUserQuestion({
    required String sessionId,
    required String memberId,
    required int optionIndex,
    List<int>? optionIndices,
    String? askRequestId,
    List<List<String>>? answers,
    String? freeText,
    List<String?>? freeTexts,
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
    final resolvedAskRequestId = _resolveAskRequestId(
      sessionId: sessionId,
      memberId: mid,
      askRequestId: askRequestId,
    );
    final result = await _askUserAnswer.answer(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
      shell: tab.memberShells[mid],
      askRequestId: resolvedAskRequestId,
      optionIndex: optionIndex,
      optionIndices: optionIndices,
      answers: answers,
      freeText: freeText,
      freeTexts: freeTexts,
      questions: _agentAttentionCubit?.state
          .entryFor(sessionId: sessionId, memberId: mid)
          ?.lastEvent
          ?.askUserQuestions,
    );
    if (result is AskUserAnswerOk) {
      _agentAttentionCubit?.markAskAnswered(
        sessionId: sessionId,
        memberId: mid,
      );
    }
    return result;
  }

  /// Cancels a pending AskUserQuestion (PTY Esc or pending reject).
  ///
  /// Successful cancel also optimistically dismisses waiting attention.
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
    final resolvedAskRequestId = _resolveAskRequestId(
      sessionId: sessionId,
      memberId: mid,
      askRequestId: askRequestId,
    );
    final result = await _askUserAnswer.cancel(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
      shell: tab.memberShells[mid],
      askRequestId: resolvedAskRequestId,
    );
    if (result is AskUserAnswerOk) {
      _agentAttentionCubit?.markAskAnswered(
        sessionId: sessionId,
        memberId: mid,
      );
    }
    return result;
  }

  /// Answers a permission request from the chat card. OpenCode (plugin SDK
  /// channel) maps [AgentPermissionReplyKind] to its `once` / `always` /
  /// `reject` string via the pending store; the Claude family (hook-hold
  /// channel) completes the held `PermissionRequest` hook — `alwaysPayload`
  /// echoes the selected suggestion's `permission_suggestions` entry.
  ///
  /// On [AskUserAnswerOk], optimistically dismisses the waiting card via
  /// [AgentAttentionCubit.markAskAnswered]. Failures leave attention unchanged.
  Future<AskUserAnswerResult> answerPermissionRequest({
    required String sessionId,
    required String memberId,
    String? permissionRequestId,
    required AgentPermissionReplyKind kind,
    Object? alwaysPayload,
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
    final resolvedRequestId = _resolveAskRequestId(
      sessionId: sessionId,
      memberId: mid,
      askRequestId: permissionRequestId,
    );
    final result = await _askUserAnswer.answerPermission(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
      requestId: resolvedRequestId,
      kind: kind,
      alwaysPayload: alwaysPayload,
    );
    if (result is AskUserAnswerOk) {
      _agentAttentionCubit?.markAskAnswered(
        sessionId: sessionId,
        memberId: mid,
      );
    }
    return result;
  }

  /// Releases the seat's held Claude-family permission hook (card "answer in
  /// terminal"): the gateway answers `{}` and the native TUI prompt appears.
  Future<AskUserAnswerResult> releasePermissionToTerminal({
    required String sessionId,
    required String memberId,
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
    return _askUserAnswer.releasePermission(
      cli: cli,
      sessionId: sessionId,
      memberId: mid,
    );
  }

  /// Approves the pending Claude `ExitPlanMode` plan from the chat card
  /// (completes the held PreToolUse hook, and the follow-up PermissionRequest
  /// hook when present). On success, optimistically dismisses the waiting
  /// attention.
  Future<ExitPlanApprovalResult> approveExitPlanMode({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    String? planText,
    String? planFilePath,
  }) async {
    final result = await _exitPlanApproval.approve(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
      planText: planText,
      planFilePath: planFilePath,
    );
    if (result is ExitPlanApprovalOk) {
      _agentAttentionCubit?.dismissWaitingPlanApproval(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return result;
  }

  /// Rejects the pending Claude `ExitPlanMode` plan (keeps the agent in plan
  /// mode). On success, optimistically dismisses the waiting attention.
  Future<ExitPlanApprovalResult> rejectExitPlanMode({
    required String sessionId,
    required String memberId,
    required String toolUseId,
    String? planText,
    String? planFilePath,
  }) async {
    final result = await _exitPlanApproval.reject(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
      planText: planText,
      planFilePath: planFilePath,
    );
    if (result is ExitPlanApprovalOk) {
      _agentAttentionCubit?.dismissWaitingPlanApproval(
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return result;
  }

  /// Prefer an explicit id; otherwise read OpenCode/Claude ask id from the
  /// seat's last attention event when available.
  String? _resolveAskRequestId({
    required String sessionId,
    required String memberId,
    required String? askRequestId,
  }) {
    final explicit = askRequestId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final fromAttention = _agentAttentionCubit?.state
        .entryFor(sessionId: sessionId, memberId: memberId)
        ?.lastEvent
        ?.askRequestId
        ?.trim();
    if (fromAttention != null && fromAttention.isNotEmpty) {
      return fromAttention;
    }
    return askRequestId;
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
    if (tab == null || _isPersonalSessionTab(tab)) {
      // Simple / unteamed shells are keyed by session id, not roster member
      // ids. Polling the team roster against them marks every member offline.
      // Null target keeps last-known presence (hysteresis) until a team tab
      // is active again.
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

  /// Persisted simple sessions only. Local/test tabs without a session keep
  /// the previous push behavior (workspace-switch tests have no AppSession).
  bool _isPersonalSessionTab(ChatTab tab) {
    final session = tab.persistedSession;
    if (session == null) return false;
    return session.sessionTeam.trim().isEmpty;
  }

  PresenceSessionContext? _presenceSessionContext(ChatTab tab) {
    final team = _teamForSessionTab(tab);
    if (team == null) return null;
    return PresenceSessionContext(
      team: team,
      appSession: tab.persistedSession,
      teamBus: tab.teamBus,
      globalPresets: _lifecycle.globalPresets,
    );
  }

  /// Switches the foreground workspace in the session runtime registry. Called
  /// by the workspace page whenever the active workspace changes. Bar presence
  /// / order / active are owned by the workbench bar.
  void setActiveWorkspace(String workspaceId) {
    _tabStore.setActiveWorkspaceId(workspaceId);
    // Re-push the presence target: the previous workspace's session may still
    // be the target (connect events are workspace-agnostic), which would leave
    // the members panel computing against the wrong shells after a switch.
    _pushPresenceTarget();
  }

  /// Switches the foreground workspace and session visibility scope in one
  /// [emit]. Use on workspace tab activation so [setTeamSessionScope] does not
  /// fire a second rebuild on the next frame.
  void activateWorkspaceTab({
    required String workspaceTabKey,
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    _tabStore.setActiveWorkspaceId(workspaceTabKey);
    // Re-push the presence target for the now-active workspace's session.
    // Without this the target stays pinned to a session that connected while
    // another workspace was foreground, leaving that workspace's members panel
    // permanently offline after switching back.
    _pushPresenceTarget();
    if (_dataStore.setScope(
      scopeSessionsToSelectedTeam: scopeSessionsToSelectedTeam,
      selectedTeamId: selectedTeamId,
    )) {
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
        ),
      );
    }
  }

  /// SessionLaunchHost port: bar presence/order is the strip's job — there is
  /// nothing left to republish. Kept so launch-pipeline callers compile.
  @override
  void refreshActiveWorkspaceTabs() {}

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

  ChatTab? get _activeTab => activeTab;

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
    final error = _activeTab?.info.launchError;
    if (error != null && error.isNotEmpty) return error;
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
        current: stateSnapshot(),
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

  /// Patches one [Workspace] in the snapshot in memory (no disk rescan).
  ///
  /// Prefer after a targeted workspace-manifest mutation (e.g. member
  /// placement saves) — [loadWorkspaceData] rescans every workspace and
  /// session on disk. Sessions are unaffected by manifest-only edits, so a
  /// full reload buys nothing here.
  void patchWorkspace(Workspace updated) {
    _emitSnapshot(_dataStore.snapshotWithWorkspace(stateSnapshot(), updated));
  }

  /// Replaces [workspace] and its sessions from a targeted mutation (e.g.
  /// remapWorkspaceTarget) in memory; no disk rescan.
  void patchWorkspaceAndSessions(
    Workspace workspace,
    List<AppSession> sessions,
  ) {
    _emitSnapshot(
      _dataStore.snapshotWithWorkspaceAndSessions(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        workspace: workspace,
        sessions: sessions,
      ),
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
    _emitSnapshot(_dataStore.appendSession(stateSnapshot(), session));
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
      stateSnapshot(),
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
      stateSnapshot(),
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
    final snap = await _dataStore.updateWorkspaceMetadata(
      stateSnapshot(),
      repo,
      workspaceId,
      display: display,
      defaultProfileId: defaultProfileId,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> applyWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final snap = await _dataStore.applyWorkspaceIcon(
      stateSnapshot(),
      repo,
      workspaceId,
      icon,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> importCustomWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    final snap = await _dataStore.importCustomWorkspaceIcon(
      stateSnapshot(),
      repo,
      workspaceId,
      localSourcePath,
    );
    if (snap != null) _emitSnapshot(snap);
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
    // Release the pod (history store + registry entry) first; the global cubit
    // sink handles legacy seats and any pods that predate history wiring.
    await disposePod(sessionId);
    onHistorySeatsDispose?.call(sessionId);
    for (final session in tab.sessions) {
      session.dispose();
    }
    _agentAttentionCubit?.clearSession(sessionId);
    _followUpQueue.clearSession(sessionId);
    _askUserAnswerPendingStore?.clearSession(sessionId);
    _agentStatusSeatLookup?.clearSession(sessionId);
    _teammateBusMcpGateway.unregisterAgentStatusSession(sessionId);
    await _teamBus.disposeSessionBus(sessionId);
    await tab.disposeBus();
  }

  /// Tears down a session runtime after the bar removed its tab. Idempotent:
  /// a session already removed (e.g. by a prior closeAll) is a no-op.
  Future<void> teardownSession(String sessionId) async {
    final tab = _tabStore.removeSession(sessionId);
    if (tab == null) return;
    _sessionRuntime.maybeStopIdleWatch();
    await _tearDownTab(tab);
    _pushPresenceTarget();
    _updateSessionActivities();
  }

  /// Registers a staged session runtime (bar presence is handled by the
  /// bridge) and starts the session idle/reclaim watches.
  void registerSessionRuntime(ChatTab tab) {
    _tabStore.registerSession(tab);
    _sessionRuntime.ensureIdleWatch();
  }

  /// Number of open session-backed tabs in [workspaceId] (excludes `local-`
  /// scratch tabs, which have no persisted workspace session).
  int openTabCountForWorkspace(String workspaceId) => _tabStore
      .tabsForWorkspace(workspaceId)
      .where((t) => !t.info.id.startsWith('local-'))
      .length;

  /// Closes (terminates) every open session belonging to [workspaceId] by
  /// routing the workspace close through the bar and tearing down each
  /// runtime. Idempotent.
  Future<void> closeTabsForWorkspace(String workspaceId) async {
    final port = _workbenchPort;
    if (port != null) {
      // Single teardown path: bar removal fires onTabRemoved →
      // teardownSession per center tab. Do not also loop teardownSession —
      // the port's onTabRemoved already handles each runtime.
      port.closeAll(workspaceId);
    } else {
      // No bar (tests / legacy): tear down each runtime directly.
      for (final id in _tabStore.sessionsForWorkspace(workspaceId)) {
        await teardownSession(id);
      }
    }
    _updateSessionActivities();
  }

  /// Sets Chat vs Terminal center body for an open session tab. The pod owns
  /// the view; `ChatTab.workbenchView` stays in sync during the transition.
  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    final pod = podRuntime(sessionId);
    if (pod != null && pod.state.view == view) {
      // Already the active view — still reconcile the transition copy on the
      // tab so tab reads (e.g. the view toggle) agree with the pod.
      _syncTabWorkbenchView(sessionId, view);
      return;
    }
    setPodView(sessionId, view);
    if (view == SessionWorkbenchView.chat) {
      onSessionHistoryStale?.call(sessionId);
    }
    if (view == SessionWorkbenchView.terminal) {
      final tab = _tabStore.openTabBySessionId(sessionId);
      final memberId = tab?.selectedMemberId ?? '';
      if (memberId.trim().isNotEmpty) {
        unawaited(ensureMemberTerminalForView(sessionId, memberId));
      }
    }
  }

  /// SessionLaunchHost port: the pod owns the per-session chat/terminal view.
  /// Keeps [ChatTab.workbenchView] in sync so tab reads (view toggle) agree
  /// with the pod — including connects that force Terminal via this port.
  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {
    ensurePodRuntime(sessionId).setView(view);
    _syncTabWorkbenchView(sessionId, view);
    // Bump podViewVersion so widgets reading ChatTab.workbenchView (or using
    // context.select on pod state through ChatCubit) stay in sync without the
    // removed stateVersion catch-all.
    if (!isClosed) {
      emit(state.copyWith(podViewVersion: state.podViewVersion + 1));
    }
  }

  void _syncTabWorkbenchView(String sessionId, SessionWorkbenchView view) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab != null && tab.workbenchView != view) {
      tab.workbenchView = view;
    }
  }

  /// SessionLaunchHost port: pod-phase concurrency gate.
  @override
  bool isSessionConnecting(String sessionId) =>
      podRuntime(sessionId)?.state.phase.isLaunching ?? false;

  @override
  bool get hasConnectingSession =>
      _materializingInFlight ||
      _pods.values.any((p) => p.state.phase.isLaunching);

  @override
  bool get isMaterializingInFlight => _materializingInFlight;

  @override
  void setMaterializingInFlight(bool value) {
    _materializingInFlight = value;
  }

  /// Shows the new-chat landing for [workspaceId] without closing open tabs.
  ///
  /// The bar owns the landing surface ([WorkbenchCubit.enterLanding]); this
  /// routes through the port so the workbench is the single source of
  /// presence/active. When the port is not yet wired (tests), the landing is
  /// left to the bar caller.
  void enterNewChat(
    String workspaceId, {
    String? initialText,
    String? referencedSessionId,
  }) {
    _workbenchPort?.enterLanding(
      workspaceId,
      initialText: initialText,
      referencedSessionId: referencedSessionId,
    );
  }

  void syncTeam(TeamProfile team) {
    final tab = _activeTab;
    if (team.members.isEmpty) {
      if (tab != null) assignSelectedMember(tab, '');
      return;
    }
    if (team.members.any((m) => m.id == tab?.selectedMemberId)) return;
    if (tab != null) assignSelectedMember(tab, _tabStore.defaultMemberId(team));
  }

  void _syncActiveWorkspaceScope(String tabScopeId) {
    if (_tabStore.activeWorkspaceId == tabScopeId) return;
    _tabStore.setActiveWorkspaceId(tabScopeId);
    _pushPresenceTarget();
  }

  @override
  void assignSelectedMember(ChatTab tab, String memberId) {
    if (tab.selectedMemberId == memberId) return;
    tab.selectedMemberId = memberId;
    _bumpMemberSelection();
  }

  @override
  void selectMember(String memberId, {String? tabScopeId}) {
    if (tabScopeId != null && tabScopeId.isNotEmpty) {
      _syncActiveWorkspaceScope(tabScopeId);
    }
    final tab = _activeTab;
    if (tab == null) return;
    assignSelectedMember(tab, memberId);
    if (tab.workbenchView == SessionWorkbenchView.terminal) {
      unawaited(ensureMemberTerminalForView(tab.info.id, memberId));
    }
  }

  /// Emits the [ChatState.memberSelectionVersion] bump so widgets deriving the
  /// member highlight from [ChatTab.selectedMemberId] rebuild.
  void _bumpMemberSelection() {
    if (!isClosed) {
      emit(
        state.copyWith(
          memberSelectionVersion: state.memberSelectionVersion + 1,
        ),
      );
    }
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

  /// Whether any terminal of the session's open tab is up (spawning/running).
  bool isSessionRunning(String sessionId) =>
      _tabStore.openTabBySessionId(sessionId)?.isRunning ?? false;

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
    final id = activeTab?.selectedMemberId ?? '';
    for (final m in team.members) {
      if (m.id == id) return m.name;
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
      selectedMemberId: tab?.selectedMemberId ?? '',
      team: team,
    );
    if (request == null) {
      AppLogger.instance.w(
        'retrySessionLaunch: no team profile for team session $id '
        '(teamId=${teamId.isEmpty ? "?" : teamId})',
      );
      return;
    }
    // Surface connecting immediately so Chat/sidebar show a spinner. The
    // pipeline also begins connect, but that happens inside unawaited prep.
    beginSessionConnect(id);
    await connectWorkspaceSession(request);
    if (isClosed) return;
    // connectWorkspaceSession returns when tab surfacing schedules async shell
    // prep — wait until the pod leaves launching before completing the retry.
    await awaitSessionConnectSettle(
      isConnecting: () => isSessionConnecting(id),
      isClosed: () => isClosed,
    );
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

  void discardMemberTerminal(String sessionId, String memberId) =>
      _launchService.discardMemberTerminal(sessionId, memberId);

  Future<void> ensureMemberTerminalForView(String sessionId, String memberId) =>
      _launchService.ensureMemberTerminalForView(sessionId, memberId);

  bool isMemberTerminalReclaimed(String sessionId, String memberId) =>
      _tabStore
          .openTabBySessionId(sessionId)
          ?.reclaimedMemberIds
          .contains(memberId) ??
      false;

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
      base: state.copyWith(sessions: sessions),
    );
  }

  /// Duplicates a Simple session (launch identity + CLI history fork).
  ///
  /// [newDisplayTitle] is resolved by the caller so l10n stays out of the
  /// cubit. Throws [StateError] while the source session still has a live
  /// terminal or pending connects — copying a live transcript risks torn
  /// JSONL appends and corrupt SQLite WAL snapshots.
  Future<AppSession> duplicateSession(
    SessionRepository repo,
    String sourceSessionId, {
    required String newDisplayTitle,
  }) async {
    final tab = _tabStore.openTabBySessionId(sourceSessionId);
    if (tab != null &&
        (tab.isRunning || tab.membersPendingConnect.isNotEmpty)) {
      throw StateError('Cannot duplicate a running session');
    }
    final created = await repo.duplicateSession(
      sourceSessionId,
      display: newDisplayTitle,
    );
    final sessions = [...state.sessions, created];
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions),
    );
    return created;
  }

  /// Compose-landing / inject path: rename untitled session from first prompt.
  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _launchService.applyFirstPromptTitle(sessionId, firstPrompt);

  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    final updated = await repo.touchSession(sessionId);
    if (updated != null) replaceSessionSnapshot(updated);
  }

  /// Persists session-level or per-member continue security-policy overrides.
  ///
  /// Returns false when the repo/session is missing or persistence fails.
  Future<bool> setSessionContinueSecurityPolicy({
    required String sessionId,
    required LaunchSecurityPolicy launchSecurityPolicy,
    String? memberId,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchSecurityPolicy(
      session: session,
      launchSecurityPolicy: launchSecurityPolicy,
      memberId: memberId,
    );
    try {
      await _continueOverridesController.persistSecurityPolicy(
        repo: repo,
        patched: patched,
      );
      replaceSessionSnapshot(patched);
      _syncTabPersistedSession(patched);
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
    _syncTabPersistedSession(patched);
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
    _syncTabPersistedSession(patched);
    return true;
  }

  /// Keeps [ChatTab.persistedSession] (used by restart / member reconnect)
  /// in sync with continue-chrome edits without dropping launch-time fields
  /// (native resume ids, launchState) that only exist on the tab cache.
  void _syncTabPersistedSession(AppSession patched) {
    final tab = _tabStore.openTabBySessionId(patched.sessionId);
    final cached = tab?.persistedSession;
    if (tab == null || cached == null) return;
    tab.persistedSession = SessionContinueOverridesController.mergeOntoTabCache(
      cached: cached,
      patched: patched,
    );
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
    final updated = await repo.toggleSessionPin(sessionId);
    if (updated != null) replaceSessionSnapshot(updated);
  }

  Future<void> archiveSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    final updated = await repo.setSessionArchived(sessionId, true);
    if (updated != null) replaceSessionSnapshot(updated);
  }

  Future<void> unarchiveSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    final updated = await repo.setSessionArchived(sessionId, false);
    if (updated != null) replaceSessionSnapshot(updated);
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final session = state.sessions
        .where((s) => s.sessionId == sessionId)
        .firstOrNull;
    composeDraftCache.clearSessionDraft(sessionId);
    if (session != null) {
      await composeDraftCache.clearSessionPersistent(
        session.workspaceId,
        sessionId,
      );
    }
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    final tab = _tabStore.openTabBySessionId(sessionId);
    final port = _workbenchPort;
    if (tab != null) {
      _sessionRuntime.maybeStopIdleWatch();
      if (port != null) {
        // Bar removal fires onTabRemoved → teardownSession (removes the runtime
        // and disposes it); the bar recomputes center-active.
        port.onSessionTabClosed(tab.workspaceId, sessionId);
      } else {
        await _tearDownTab(tab);
        _tabStore.removeSession(sessionId);
      }
    }
    if (session != null && port != null) {
      port.onSessionDeleted(session.workspaceId, sessionId);
    }
    _updateSessionActivities();
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state,
    );
    _emitSnapshot(
      await _dataStore.deleteSessionRecord(stateSnapshot(), repo, sessionId),
    );
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
      stateSnapshot(),
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
    composeDraftCache.clearLandingDraft(workspaceId);
    for (final sid in workspace.sessionIds.toList()) {
      await deleteSession(repo, sid);
    }
    await _automationRepository.removeWorkspace(workspaceId);
    _notifyAutomationsChanged();
    _emitSnapshot(
      await _dataStore.deleteWorkspaceRecord(
        stateSnapshot(),
        repo,
        workspaceId,
      ),
    );
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
    await _operatorMailboxQueued.close();
    await super.close();
  }
}
