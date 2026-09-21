import '../agent_status/agent_status_seat_lookup.dart';
import '../chat/conversation/prompt_delivery/prompt_delivery_coordinator.dart';
import '../chat/conversation/prompt_delivery/prompt_delivery_store.dart';
import '../chat/runtime/pty/tab_member_pty_delivery.dart';
import '../chat/session/chat_tab_store.dart';
import '../chat/session/session_lifecycle_service.dart';
import '../chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'agent_event_gateway.dart';
import 'agent_runtime.dart';
import 'runtime_event_journal.dart';
import 'runtime_event_projection.dart';
import 'seat_event_stream.dart';

/// Default composition that joins journaled `/agent-status` hooks to the
/// prompt-delivery coordinator.
///
/// AppShell supplies a durable store and attaches [AgentRuntime] before the
/// first session-runtime access. ChatCubit still calls [ensure] on that first
/// access so hosts that skip AppShell (integration harnesses, focused cubit
/// tests) get the same hook → confirmation join instead of a private
/// per-tab coordinator that never sees `UserPromptSubmit`.
final class ChatAgentRuntimeJoin {
  /// Returns the coordinator [TabSessionRuntimeCoordinator] must use, binding
  /// [AgentRuntime] when the lifecycle has none yet.
  static PromptDeliveryCoordinator ensure({
    required TeammateBusMcpGateway mcpGateway,
    required AgentStatusSeatLookup seats,
    required SessionLifecycleService lifecycle,
    required ChatTabStore tabStore,
    PromptDeliveryCoordinator? promptDeliveries,
    AgentEventGateway? gateway,
    Iterable<RuntimeEventProjection> projections = const [],
  }) {
    final existing = lifecycle.agentRuntime;
    if (existing != null) {
      return promptDeliveries ?? existing.promptDeliveries;
    }

    final coordinator =
        promptDeliveries ??
        PromptDeliveryCoordinator(
          store: MemoryPromptDeliveryStore(),
          commands: TabPromptDeliveryCommands(tabStore),
        );
    final events =
        gateway ??
        mcpGateway.agentEventGateway ??
        AgentEventGateway(
          journal: MemoryRuntimeEventJournal(),
          stream: SeatEventStream(),
          resolveCli: seats.resolveCli,
          projections: projections,
        );
    if (mcpGateway.agentEventGateway == null) {
      mcpGateway.attachAgentEventGateway(events);
    }
    lifecycle.attachAgentRuntime(
      AgentRuntime(
        gateway: events,
        promptDeliveries: coordinator,
        projections: projections,
      ),
    );
    return coordinator;
  }
}
