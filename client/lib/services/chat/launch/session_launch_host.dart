import '../../../models/app_session.dart';
import '../../../models/member_remote_provision_progress.dart';
import '../launch/staging/session_connect_orchestrator.dart';
import '../../agent_status/agent_status_seat_lookup_port.dart';
import '../../agent_status/ask_user_answer_pending_port.dart';
import '../../agent_status/agent_attention_port.dart';
import '../../agent_status/seat_lease_port.dart';
import '../team_bus/mcp/teammate_bus_mcp_gateway_port.dart';
import '../team_bus/remote/remote_member_bus_setup.dart';
import '../session/session_workbench_view.dart';
import '../session/session_data_store.dart';
import 'session/tab_member_materializer.dart';
import '../runtime/tab_session_runtime_coordinator.dart';
import '../team_bus/team_bus_user_input_port.dart';
import 'chat_state_port.dart';
import 'launch_environment_port.dart';
import '../session/session_repository_port.dart';
import '../session/tab_port.dart';

/// Connect-state transitions owned by [ChatCubit] (via [ChatConnectStateMixin]).
abstract interface class SessionConnectStatePort {
  void beginSessionConnect(String sessionId);

  /// [error]/[stackTrace] carry the original failure when one exists.
  void failSessionConnect(
    String sessionId,
    String rawMessage, {
    Object? error,
    StackTrace? stackTrace,
  });
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
    implements
        ChatStatePort,
        LaunchEnvironmentPort,
        SessionConnectStatePort,
        SessionRepositoryPort,
        SessionSnapshotPort,
        TabPort {
  // Collaborators that are not themselves narrow enough to be a port. Each is
  // a candidate for extraction; until then they stay on the host.

  TabSessionRuntimeCoordinator get sessionRuntime;
  TeamBusUserInputPort get teamBus;
  TabMemberMaterializer get memberMaterializer;
  SessionDataStore get dataStore;

  /// P3b (#1): reverse-tunnel bus bind for remote members. Null when
  /// remote-member-over-tunnel is not wired (then all members use local
  /// transport — pre-P3b behavior).
  RemoteMemberBusSetupPort? get remoteBusSetup;

  SessionConnectOrchestrator get sessionConnect;

  TeammateBusMcpGatewayPort get teammateBusMcpGateway;

  /// Issues/rotates the team-generation workflow token for a builder session
  /// (null in tests / when generation is not wired).
  String? Function(AppSession session)? get teamGenerationTokenIssuer => null;

  /// Seat CLI + skip-permissions map for `/agent-status` (null in tests).
  AgentStatusSeatLookupPort? get agentStatusSeatLookup;

  /// Permission-attention state; cleared on seat/tab dispose (null in tests).
  AgentAttentionPort? get agentAttentionCubit;

  /// Seat keep-alive leases (background shell tasks); cleared with
  /// attention on seat/tab dispose (null in tests).
  SeatLeasePort? get seatLeaseCubit;

  /// Shared OpenCode ask-answer pending map; cleared with attention on dispose.
  AskUserAnswerPendingPort? get askUserAnswerPendingStore;
}

/// Drop attention + seat lookup (+ pending ask answers) for every seat in
/// [sessionId].
///
/// Used on team-session restart (shells disconnect without [onProcessExited]).
/// Does not unregister the gateway status session — reconnect re-registers seats.
void clearAgentStatusSessionSeats({
  AgentAttentionPort? attention,
  AgentStatusSeatLookupPort? seatLookup,
  AskUserAnswerPendingPort? askUserAnswerPendingStore,
  SeatLeasePort? seatLeaseCubit,
  required String sessionId,
}) {
  attention?.clearSession(sessionId);
  seatLookup?.clearSession(sessionId);
  askUserAnswerPendingStore?.clearSession(sessionId);
  seatLeaseCubit?.clearSession(sessionId);
}

/// Drop attention + seat lookup for one seat (PTY exit, disconnect, reconnect).
extension SessionLaunchHostAgentStatus on SessionLaunchHost {
  void clearAgentStatusSeat({
    required String sessionId,
    required String memberId,
  }) {
    agentAttentionCubit?.clearSeat(sessionId: sessionId, memberId: memberId);
    agentStatusSeatLookup?.unregisterSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
    askUserAnswerPendingStore?.clearSeat(
      sessionId: sessionId,
      memberId: memberId,
    );
    seatLeaseCubit?.clearSeat(sessionId: sessionId, memberId: memberId);
  }

  void clearAgentStatusSession(String sessionId) {
    clearAgentStatusSessionSeats(
      attention: agentAttentionCubit,
      seatLookup: agentStatusSeatLookup,
      askUserAnswerPendingStore: askUserAnswerPendingStore,
      seatLeaseCubit: seatLeaseCubit,
      sessionId: sessionId,
    );
  }
}

/// Bar-derived center-active tab, without workbench cubit types.
///
/// Distinguishes landing (no center tab) from a non-session tab so the domain
/// never treats another workspace's session as active.
class CenterActiveScope {
  const CenterActiveScope.landing() : sessionId = null, isNonSessionTab = false;

  const CenterActiveScope.session(this.sessionId) : isNonSessionTab = false;

  const CenterActiveScope.nonSessionTab()
    : sessionId = null,
      isNonSessionTab = true;

  /// Session id when a session tab is center-active; otherwise null.
  final String? sessionId;

  /// True when a file/diff/etc tab is center-active (not landing).
  final bool isNonSessionTab;
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
  void enterLanding(
    String workspaceId, {
    String? initialText,
    String? referencedSessionId,
  });

  /// Clears a Landing reference after its persisted Session is deleted.
  void onSessionDeleted(String workspaceId, String sessionId);

  /// Close every center tab for [workspaceId] (each removal tears down).
  void closeAll(String workspaceId);

  /// Bar center-active tab for [workspaceId]. Lets the domain derive "the
  /// active session" from the bar — the single source of truth.
  CenterActiveScope centerActiveForScope(String workspaceId);
}
