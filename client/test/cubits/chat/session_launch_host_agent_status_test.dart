import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/cubits/chat/session_launch_host.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/agent_runtime/agent_runtime.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_projection.dart';
import 'package:teampilot/services/agent_runtime/seat_event_stream.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';

void main() {
  // SessionLaunchPipeline._restartTeamSession needs a full host fake; the
  // restart path calls clearAgentStatusSession → clearAgentStatusSessionSeats.
  group('clearAgentStatusSessionSeats', () {
    test('clears attention and seat lookup for session, keeps other sessions', () {
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      final seats = AgentStatusSeatLookup();
      final pending = AskUserAnswerPendingStore();

      attention.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      attention.applyEvent(
        sessionId: 's2',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      seats.registerSeat(
        sessionId: 's1',
        memberId: 'm1',
        cli: CliTool.claude,
        skipPermissions: false,
      );
      seats.registerSeat(
        sessionId: 's2',
        memberId: 'm1',
        cli: CliTool.codex,
        skipPermissions: false,
      );
      pending.put(
        sessionId: 's1',
        memberId: 'm1',
        entry: const AskUserAnswerPendingEntry(requestId: 'req-1'),
      );
      pending.put(
        sessionId: 's2',
        memberId: 'm1',
        entry: const AskUserAnswerPendingEntry(requestId: 'req-2'),
      );

      clearAgentStatusSessionSeats(
        attention: attention,
        seatLookup: seats,
        askUserAnswerPendingStore: pending,
        sessionId: 's1',
      );

      expect(attention.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(
        attention.state.attentionFor(sessionId: 's2', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(seats.resolveCli('s1', 'm1'), isNull);
      expect(seats.resolveCli('s2', 'm1'), CliTool.codex);
      expect(
        pending.take(
          sessionId: 's1',
          memberId: 'm1',
          requestId: 'req-1',
        ),
        isNull,
      );
      expect(
        pending.take(
          sessionId: 's2',
          memberId: 'm1',
          requestId: 'req-2',
        ),
        isNotNull,
      );
    });
  });

  group('SessionLaunchHost.clearAgentStatusSeat', () {
    test('clears pending ask answers for the seat only', () {
      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      final seats = AgentStatusSeatLookup();
      final pending = AskUserAnswerPendingStore();
      final host = _HostWithAgentStatus(
        attention: attention,
        seats: seats,
        pending: pending,
      );

      pending.put(
        sessionId: 's1',
        memberId: 'm1',
        entry: const AskUserAnswerPendingEntry(requestId: 'req-1'),
      );
      pending.put(
        sessionId: 's1',
        memberId: 'm2',
        entry: const AskUserAnswerPendingEntry(requestId: 'req-2'),
      );

      host.clearAgentStatusSeat(sessionId: 's1', memberId: 'm1');

      expect(
        pending.take(
          sessionId: 's1',
          memberId: 'm1',
          requestId: 'req-1',
        ),
        isNull,
      );
      expect(
        pending.take(
          sessionId: 's1',
          memberId: 'm2',
          requestId: 'req-2',
        ),
        isNotNull,
      );
    });
  });

  group('app-scoped runtime composition', () {
    test('hook confirms delivery and updates attention projection', () async {
      final harness = _RuntimeCompositionHarness();
      addTearDown(harness.dispose);
      const seat = RuntimeSeatKey(sessionId: 's1', memberId: 'm1');

      await harness.submit(seat, 'hello');
      await harness.postHook(seat, {
        'hook_event_name': 'UserPromptSubmit',
        'prompt': 'hello',
      });

      expect(
        (await harness.deliveryStore.activeFor(seat)).single.state,
        PromptDeliveryState.confirmed,
      );
      expect(harness.attention.stateFor(seat).isWorking, isTrue);
    });

    test('restoreSession replays journal and resolves unknown submits',
        () async {
      final harness = _RuntimeCompositionHarness();
      addTearDown(harness.dispose);
      const seat = RuntimeSeatKey(sessionId: 's1', memberId: 'm1');
      await harness.submit(seat, 'recover me');

      // Simulate an app restart: a fresh runtime over the same journal/store
      // must replay the journaled hook state and flip the unconfirmed submit.
      final restored = _RuntimeCompositionHarness.restartOf(harness);
      addTearDown(restored.dispose);
      await restored.restoreSession(seat.sessionId);

      expect(
        (await restored.deliveryStore.activeFor(seat)).single.state,
        PromptDeliveryState.submittedUnknown,
      );
    });
  });
}

/// Read-only view over the composition's real delivery store. Production
/// `activeFor` hides terminal records; the assertions above need the full
/// per-seat history (confirmed / submittedUnknown are terminal states).
class _DeliveryStoreView {
  const _DeliveryStoreView(this._store);

  final PromptDeliveryStore _store;

  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) =>
      _store.forSeat(seat);
}

/// Attention snapshot view keeping the brief's `stateFor(seat).isWorking`
/// shape without inventing production API on [AgentAttentionCubit].
class _AttentionView {
  const _AttentionView(this._cubit);

  final AgentAttentionCubit _cubit;

  _AttentionState stateFor(RuntimeSeatKey seat) => _AttentionState(
        _cubit.state.attentionFor(
          sessionId: seat.sessionId,
          memberId: seat.memberId,
        ),
      );
}

class _AttentionState {
  const _AttentionState(this._attention);

  final AgentSeatAttention? _attention;

  bool get isWorking => _attention == AgentSeatAttention.working;
}

/// End-to-end composition harness: one gateway + one coordinator joined by
/// [AgentRuntime], with deterministic clock and ids. No CLI binary involved —
/// hooks are posted straight into the gateway ingress.
class _RuntimeCompositionHarness {
  _RuntimeCompositionHarness({
    MemoryRuntimeEventJournal? sharedJournal,
    MemoryPromptDeliveryStore? sharedStore,
  }) : journal = sharedJournal ?? MemoryRuntimeEventJournal(),
       store = sharedStore ?? MemoryPromptDeliveryStore() {
    final attentionProjection = RuntimeEventProjection.attention(
      attention: attentionCubit,
      resolveSkipPermissions: (_, __) => false,
    );
    gateway = AgentEventGateway(
      journal: journal,
      stream: stream,
      resolveCli: (_, __) => CliTool.claude,
      projections: [attentionProjection],
      clock: () => now,
    );
    runtime = AgentRuntime(
      gateway: gateway,
      projections: [attentionProjection],
      promptDeliveries: PromptDeliveryCoordinator(
        store: store,
        commands: commands,
        idGenerator: () => 'delivery-${ids++}',
        clock: () => now,
      ),
    );
  }

  /// Restart simulation: same durable journal + store records, fresh streams,
  /// projections, gateway, and coordinator (what app bootstrap rebuilds).
  factory _RuntimeCompositionHarness.restartOf(
    _RuntimeCompositionHarness previous,
  ) => _RuntimeCompositionHarness(
    sharedJournal: previous.journal,
    sharedStore: previous.store,
  );

  final DateTime now = DateTime.utc(2026, 8, 25, 12);
  var ids = 0;

  final MemoryRuntimeEventJournal journal;
  final stream = SeatEventStream();
  final attentionCubit = AgentAttentionCubit(pruneInterval: null);
  final MemoryPromptDeliveryStore store;
  final commands = _RecordingPromptDeliveryCommands();
  late final AgentEventGateway gateway;
  late final AgentRuntime runtime;

  _AttentionView get attention => _AttentionView(attentionCubit);

  _DeliveryStoreView get deliveryStore => _DeliveryStoreView(store);

  Future<void> submit(RuntimeSeatKey seat, String text) async {
    final delivery = await runtime.promptDeliveries.submit(
      PromptDeliveryRequest(seat: seat, cli: CliTool.claude, text: text),
    );
    await runtime.promptDeliveries.issueSubmit(delivery.id);
  }

  Future<void> postHook(RuntimeSeatKey seat, Map<String, Object?> body) async {
    await gateway.handleJson(seat, body);
    await runtime.settle(seat);
  }

  Future<void> restoreSession(String sessionId) =>
      runtime.restoreSession(sessionId);

  Future<void> dispose() async {
    await runtime.dispose();
    await gateway.close();
    await stream.close();
    await attentionCubit.close();
  }
}

final class _RecordingPromptDeliveryCommands implements PromptDeliveryCommands {
  final ptyWrites = <String>[];

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
    bool Function()? isAcked,
  }) async {
    if (!canExecute()) return PromptSubmissionResult.dropped;
    ptyWrites.add(delivery.text);
    return PromptSubmissionResult.submitted;
  }
}

class _HostWithAgentStatus implements SessionLaunchHost {
  _HostWithAgentStatus({
    required this.attention,
    required this.seats,
    required this.pending,
  });

  final AgentAttentionCubit attention;
  final AgentStatusSeatLookup seats;
  final AskUserAnswerPendingStore pending;

  @override
  AgentAttentionCubit? get agentAttentionCubit => attention;

  @override
  AgentStatusSeatLookup? get agentStatusSeatLookup => seats;

  @override
  AskUserAnswerPendingStore? get askUserAnswerPendingStore => pending;

  @override
  bool isSessionConnecting(String sessionId) => false;

  @override
  bool get hasConnectingSession => false;

  @override
  ChatDataSnapshot stateSnapshot() => const ChatDataSnapshot(
        workspaces: [],
        sessions: [],
        visibleWorkspaces: [],
        visibleSessions: [],
      );

  @override
  void setMaterializingInFlight(bool value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
