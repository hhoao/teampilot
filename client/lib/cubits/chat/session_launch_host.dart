import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/app_session.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/launch/session_connect_orchestrator.dart';
import '../../services/launch/workspace_provision_coordinator.dart';
import '../../services/progress_activity/cli_provision_activity_adapter.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/agent_status/agent_status_seat_lookup.dart';
import '../../services/agent_status/ask_user_answer_pending_store.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/team_bus/remote/remote_bus_binding_resolver.dart';
import 'chat_session_shell_factory.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'model/session_workbench_view.dart';
import 'session_data_store.dart';
import 'tab_member_materializer.dart';
import 'tab_session_runtime_coordinator.dart';
import 'tab_team_bus_coordinator.dart';
import 'chat_tab_store.dart';

/// Connect-state transitions owned by [ChatCubit] (via [ChatConnectStateMixin]).
abstract interface class SessionConnectStatePort {
  void beginSessionConnect(String sessionId);
  void failSessionConnect(String sessionId, String rawMessage);
  void finishSessionConnect(String sessionId);
  void clearLaunchError(String sessionId);
  void setLaunchError(String sessionId, String rawMessage);
  void emitLaunchWarnings(List<String> warnings);
  void updateTabRunning(String tabId);

  /// Sets the pod's chat-vs-terminal view for [sessionId] (thin-ChatCubit: the
  /// pod owns the per-session view; the launch surface routes through this).
  void setPodView(String sessionId, SessionWorkbenchView view);

  /// True when [sessionId]'s pod is still provisioning/connecting.
  bool isSessionConnecting(String sessionId);

  /// True when any session is connecting or pre-session materialization is in
  /// flight (the former `'pending'` connect).
  bool get hasConnectingSession;

  /// True while pre-session materialization (the former `'pending'` connect) is
  /// in flight — no session pod exists yet, so it cannot be per-session gated.
  bool get isMaterializingInFlight;

  /// Marks pre-session materialization (former `'pending'`) in flight.
  void setMaterializingInFlight(bool value);

  /// Updates (or clears) live remote provision UI for [memberId] on [sessionId].
  void setMemberRemoteProvisionProgress(
    String sessionId,
    String memberId,
    MemberRemoteProvisionProgress? progress,
  );
}

/// Session snapshot writes routed through the cubit emit path.
abstract interface class SessionSnapshotPort {
  void appendSessionSnapshot(AppSession session);
  void replaceSessionSnapshot(AppSession session);
  void removeSessionSnapshot(String sessionId);
  void emitSnapshot(ChatDataSnapshot snapshot);
}

/// Seam [SessionLaunchService] uses to read/emit ChatState and reach the other
/// collaborators. Implemented by ChatCubit, which stays the sole emit owner
/// (the service routes every state write through [applyState] / the connect
/// state-machine methods).
abstract interface class SessionLaunchHost
    implements SessionConnectStatePort, SessionSnapshotPort {
  ChatState get state;
  bool get isClosed;

  /// Single emit entry point (wraps the cubit's protected emit).
  void applyState(ChatState next);
  void refreshActiveWorkspaceTabs();
  void closeSessionTab(String sessionId);
  void emitTeamConfigValidation(TeamConfigValidation validation);

  // Cubit-owned facade methods the launch flow drives.
  void selectMember(String memberId);
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  );
  Future<void> loadWorkspaceData(SessionRepository repo);
  void pushPresenceTarget();

  ChatTab? get activeTab;
  set activeTeam(TeamProfile? team);

  // Collaborators.
  ChatTabStore get tabStore;
  ChatSessionShellFactory get shellFactory;
  TabSessionRuntimeCoordinator get sessionRuntime;
  TabTeamBusCoordinator get teamBus;
  TabMemberMaterializer get memberMaterializer;
  SessionLifecycleService get lifecycle;
  SessionDataStore get dataStore;

  // Resolvers.
  SessionRepository? get sessionRepository;
  PostFrameScheduler get postFrameScheduler;
  bool Function()? get autoLaunchAllMembersOnConnect;

  /// P3b (#1): resolves a remote member's reverse-tunnel bus binding. Null when
  /// remote-member-over-tunnel is not wired (then all members use local
  /// transport — pre-P3b behavior).
  RemoteBusBindingResolver? get remoteBusResolver;

  SessionConnectOrchestrator get sessionConnect;

  TeammateBusMcpGateway get teammateBusMcpGateway;

  /// Seat CLI + skip-permissions map for `/agent-status` (null in tests).
  AgentStatusSeatLookup? get agentStatusSeatLookup;

  /// Permission-attention state; cleared on seat/tab dispose (null in tests).
  AgentAttentionCubit? get agentAttentionCubit;

  /// Shared OpenCode ask-answer pending map; cleared with attention on dispose.
  AskUserAnswerPendingStore? get askUserAnswerPendingStore;

  /// Exposes workspace Phase A for team / mixed off-home paths.
  WorkspaceProvisionCoordinator get workspaceProvision;

  /// Optional progress activity reporting for remote CLI provision.
  CliProvisionActivityAdapter? get cliProvisionActivity;

  /// CLI registry for lifecycle gating and tool capabilities at connect time.
  CliToolRegistry get cliRegistry;

  Future<TeamProfile?> teamProfileById(String teamId);

  /// Workspace opt-in: inject IS_SANDBOX when launching Claude as root over SSH.
  Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId);

  /// Terminal theme for member PTY spawn (COLORFGBG / Claude `theme: auto`).
  /// Null skips apply — tests and early bootstrap may omit it.
  TerminalTheme? resolveTerminalThemeForLaunch();
}

/// Drop attention + seat lookup (+ pending ask answers) for every seat in
/// [sessionId].
///
/// Used on team-session restart (shells disconnect without [onProcessExited]).
/// Does not unregister the gateway status session — reconnect re-registers seats.
void clearAgentStatusSessionSeats({
  AgentAttentionCubit? attention,
  AgentStatusSeatLookup? seatLookup,
  AskUserAnswerPendingStore? askUserAnswerPendingStore,
  required String sessionId,
}) {
  attention?.clearSession(sessionId);
  seatLookup?.clearSession(sessionId);
  askUserAnswerPendingStore?.clearSession(sessionId);
}

/// Drop attention + seat lookup for one seat (PTY exit, disconnect, reconnect).
extension SessionLaunchHostAgentStatus on SessionLaunchHost {
  void clearAgentStatusSeat({
    required String sessionId,
    required String memberId,
  }) {
    agentAttentionCubit?.clearSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
    agentStatusSeatLookup?.unregisterSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
    askUserAnswerPendingStore?.clearSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
  }

  void clearAgentStatusSession(String sessionId) {
    clearAgentStatusSessionSeats(
      attention: agentAttentionCubit,
      seatLookup: agentStatusSeatLookup,
      askUserAnswerPendingStore: askUserAnswerPendingStore,
      sessionId: sessionId,
    );
  }
}

/// Narrow surface the session domain uses to drive the workbench bar.
///
/// Implemented by [WorkbenchChatBridge] in production; null in tests until the
/// app shell wires the bridge.
abstract class ChatWorkbenchPort {
  /// Domain-driven close: remove [sessionId]'s tab from the bar. The bar then
  /// calls back [WorkbenchDomainPort.onTabRemoved], which tears down the
  /// session runtime.
  void onSessionTabClosed(String workspaceId, String sessionId);

  /// Show the new-chat landing for [workspaceId] (bar active → null).
  void enterLanding(String workspaceId);

  /// Close every center tab for [workspaceId] (each removal tears down).
  void closeAll(String workspaceId);
}
