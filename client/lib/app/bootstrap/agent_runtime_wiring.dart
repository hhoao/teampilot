import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/seat_lease_cubit.dart';
import '../../services/agent_runtime/agent_event_gateway.dart';
import '../../services/agent_runtime/agent_runtime.dart';
import '../../services/agent_runtime/runtime_event_journal.dart';
import '../../services/agent_runtime/runtime_event_projection.dart';
import '../../services/agent_runtime/seat_event_stream.dart';
import '../../services/agent_runtime/seat_lease_projection.dart';
import '../../services/agent_status/agent_status_seat_lookup.dart';
import '../../services/agent_status/ask_user_answer_pending_store.dart';
import '../../services/agent_status/ask_user_question_hook_gate.dart';
import '../../services/agent_status/exit_plan_mode_hook_gate.dart';
import '../../services/agent_status/general_permission_request_gate.dart';
import '../../services/chat/conversation/approvals/ask_user_question_answer_service.dart';
import '../../services/chat/conversation/approvals/exit_plan_mode_approval_service.dart';
import '../../services/chat/conversation/prompt_delivery/prompt_delivery_coordinator.dart';
import '../../services/chat/conversation/prompt_delivery/prompt_delivery_store.dart';
import '../../services/chat/runtime/pty/tab_member_pty_delivery.dart';
import '../../services/chat/session/session_lifecycle_service.dart';
import '../../services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/storage/home_storage.dart';

/// The app-lifetime agent event/status plane: the teammate-bus MCP gateway,
/// the shared ask-user store and approval gates/services, the attention and
/// seat-lease state, and the journaled [AgentEventGateway] those feed.
typedef AgentEventPlane = ({
  TeammateBusMcpGateway teammateBusMcpGateway,
  AskUserAnswerPendingStore askUserAnswerPendingStore,
  AskUserQuestionAnswerService askUserQuestionAnswerService,
  GeneralPermissionRequestGate generalPermissionRequestGate,
  ExitPlanModeApprovalService exitPlanModeApprovalService,
  AgentAttentionCubit agentAttentionCubit,
  SeatLeaseCubit seatLeaseCubit,
  AgentStatusSeatLookup agentStatusSeatLookup,
  AgentEventGateway agentEventGateway,
  List<RuntimeEventProjection> runtimeProjections,
});

/// Builds the agent event plane and starts the teammate-bus MCP gateway.
///
/// Kept separate from [wireAgentRuntime] because the shell attaches the catalog
/// and SSH MCP handlers to the returned gateway (and constructs the chat cubit
/// with the returned state) before the chat cubit — which the prompt-delivery
/// coordinator needs for its fenced terminal adapter — exists.
Future<AgentEventPlane> wireAgentEventPlane({
  required HomeStorage storage,
}) async {
  final teammateBusMcpGateway = TeammateBusMcpGateway();
  await teammateBusMcpGateway.ensureStarted();

  // Shared AskUserAnswerPendingStore singleton (lives in buildAppShell):
  // gateway GET /ask-user-answer + ChatCubit answer facade must reuse
  // this instance — do not construct a second store.
  final askUserAnswerPendingStore = AskUserAnswerPendingStore();
  teammateBusMcpGateway.attachAskUserAnswerStore(askUserAnswerPendingStore);
  final askUserQuestionHookGate = AskUserQuestionHookGate();
  final generalPermissionRequestGate = GeneralPermissionRequestGate();
  final askUserQuestionAnswerService = AskUserQuestionAnswerService(
    store: askUserAnswerPendingStore,
    hookGate: askUserQuestionHookGate,
    generalPermissionGate: generalPermissionRequestGate,
  );
  final exitPlanModeHookGate = ExitPlanModeHookGate();
  final exitPlanPermissionRequestGate = ExitPlanPermissionRequestGate();
  final exitPlanModeApprovalService = ExitPlanModeApprovalService(
    hookGate: exitPlanModeHookGate,
    permissionGate: exitPlanPermissionRequestGate,
  );

  final agentAttentionCubit = AgentAttentionCubit();
  final seatLeaseCubit = SeatLeaseCubit();
  final agentStatusSeatLookup = AgentStatusSeatLookup();
  final agentRuntimeStream = SeatEventStream();
  final askUserQuestionProjection = AskUserQuestionRuntimeEventProjection(
    hookGate: askUserQuestionHookGate,
  );
  final exitPlanModeProjection = ExitPlanModeRuntimeEventProjection(
    hookGate: exitPlanModeHookGate,
    permissionGate: exitPlanPermissionRequestGate,
  );
  final generalPermissionProjection = GeneralPermissionRuntimeEventProjection(
    gate: generalPermissionRequestGate,
  );
  final runtimeProjections = [
    RuntimeEventProjection.attention(
      attention: agentAttentionCubit,
      resolveSkipPermissions: agentStatusSeatLookup.resolveSkipPermissions,
    ),
    seatLeaseProjection(leases: seatLeaseCubit),
    askUserQuestionProjection,
    exitPlanModeProjection,
    generalPermissionProjection,
  ];
  final agentEventGateway = AgentEventGateway(
    journal: FileRuntimeEventJournal(
      journalRoot: storage.fs.pathContext.join(
        storage.paths.basePath,
        'runtime-events',
      ),
      fs: storage.fs,
    ),
    stream: agentRuntimeStream,
    resolveCli: agentStatusSeatLookup.resolveCli,
    projections: runtimeProjections,
    responders: [
      askUserQuestionProjection,
      exitPlanModeProjection,
      generalPermissionProjection,
    ],
  );
  teammateBusMcpGateway.attachAgentEventGateway(agentEventGateway);

  return (
    teammateBusMcpGateway: teammateBusMcpGateway,
    askUserAnswerPendingStore: askUserAnswerPendingStore,
    askUserQuestionAnswerService: askUserQuestionAnswerService,
    generalPermissionRequestGate: generalPermissionRequestGate,
    exitPlanModeApprovalService: exitPlanModeApprovalService,
    agentAttentionCubit: agentAttentionCubit,
    seatLeaseCubit: seatLeaseCubit,
    agentStatusSeatLookup: agentStatusSeatLookup,
    agentEventGateway: agentEventGateway,
    runtimeProjections: runtimeProjections,
  );
}

/// The app-scoped prompt-delivery composition and the agent runtime joined to
/// it.
typedef AgentRuntimeWiring = ({
  PromptDeliveryCoordinator promptDeliveries,
  AgentRuntime agentRuntime,
});

/// Builds the durable prompt-delivery coordinator and the one app-scoped agent
/// runtime, then attaches the runtime to the session lifecycle service.
///
/// Runs after the chat cubit exists because [TabPromptDeliveryCommands] needs
/// the chat tab store. [chatCubit] and [sessionLifecycleService] are getters
/// because the shell owns them as `late final` dependencies.
AgentRuntimeWiring wireAgentRuntime({
  required HomeStorage storage,
  required AgentEventGateway gateway,
  required List<RuntimeEventProjection> projections,
  required ChatCubit Function() chatCubit,
  required SessionLifecycleService Function() sessionLifecycleService,
}) {
  final chat = chatCubit();
  final lifecycle = sessionLifecycleService();
  final promptDeliveryStore = FilePromptDeliveryStore(
    root: storage.fs.pathContext.join(
      storage.paths.basePath,
      'prompt-deliveries',
    ),
    fs: storage.fs,
  );
  final promptDeliveries = PromptDeliveryCoordinator(
    store: promptDeliveryStore,
    commands: TabPromptDeliveryCommands(chat.tabStore),
  );
  // One app-scoped runtime join: journaled hooks drive delivery correlation
  // under per-seat serialization; restoreSession replays both durable stores
  // before a session's input is enabled (see SessionLifecycleService).
  final agentRuntime = AgentRuntime(
    gateway: gateway,
    projections: projections,
    promptDeliveries: promptDeliveries,
  );
  lifecycle.attachAgentRuntime(agentRuntime);

  return (promptDeliveries: promptDeliveries, agentRuntime: agentRuntime);
}
