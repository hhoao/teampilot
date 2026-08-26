import 'dart:async';

import '../prompt_delivery/prompt_delivery.dart';
import '../prompt_delivery/prompt_delivery_coordinator.dart';
import 'agent_event_gateway.dart';
import 'runtime_event.dart';
import 'runtime_event_projection.dart';

/// App-scoped composition of the agent runtime event plane.
///
/// One gateway owns durable hook ingress (journal-before-publish); one
/// prompt-delivery coordinator owns the durable delivery lifecycle. This
/// class is the join between them: every journaled [RuntimeEventKind
/// .promptSubmitted] event is applied by the coordinator under the same
/// per-seat serialization as its state transitions, so a hook can never
/// confirm a delivery ahead of the coordinator's own ordering.
///
/// Recovery ([restoreSession]) replays a session's journal through the
/// projections and the coordinator before flipping leftover unconfirmed
/// submits to [PromptDeliveryState.submittedUnknown]. It must complete
/// before the session's terminal input is enabled.
final class AgentRuntime {
  AgentRuntime({
    required this.gateway,
    required this.promptDeliveries,
    Iterable<RuntimeEventProjection> projections = const [],
  }) : _projections = List<RuntimeEventProjection>.unmodifiable(projections) {
    _subscription = gateway.stream.events.listen(_onEvent);
  }

  final AgentEventGateway gateway;

  /// The coordinator's store and commands are supplied by app composition:
  /// a durable [PromptDeliveryStore] plus the fenced terminal adapter.
  final PromptDeliveryCoordinator promptDeliveries;
  final List<RuntimeEventProjection> _projections;
  final Map<RuntimeSeatKey, Future<void>> _seatTails = {};
  StreamSubscription<RuntimeEventEnvelope>? _subscription;

  void _onEvent(RuntimeEventEnvelope event) {
    final previous = _seatTails[event.seat] ?? Future<void>.value();
    _seatTails[event.seat] = previous
        .then((_) => promptDeliveries.onRuntimeEvent(event))
        .then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  /// Completes when every runtime event already published for [seat] has
  /// been applied by the coordinator.
  Future<void> settle(RuntimeSeatKey seat) => _seatTails[seat] ?? Future.value();

  /// Opens and replays the durable journal + delivery records for one
  /// session. Called during launch preparation so an unconfirmed submitted
  /// delivery becomes [PromptDeliveryState.submittedUnknown] before any new
  /// input can be enabled; replayed hooks may still confirm what genuinely
  /// landed before the restart.
  Future<void> restoreSession(String sessionId) async {
    final seats = <RuntimeSeatKey>{
      ...await gateway.journal.seatsForSession(sessionId),
      ...await promptDeliveries.store.seatsForSession(sessionId),
    };
    for (final seat in seats) {
      await for (final event in gateway.journal.replay(seat)) {
        for (final projection in _projections) {
          projection.apply(event);
        }
        final previous = _seatTails[seat] ?? Future<void>.value();
        _seatTails[seat] = previous
            .then((_) => promptDeliveries.onRuntimeEvent(event))
            .then<void>((_) {}, onError: (Object _, StackTrace __) {});
      }
      await settle(seat);
      await promptDeliveries.restoreSeat(seat);
    }
  }

  /// The seat-level recovery candidates for [sessionId]: the latest record
  /// of each seat when it is explicitly unresolved (submittedUnknown). A
  /// newer record always supersedes an older unknown — the compose section
  /// offers review/retry only for these, and retry mints a NEW delivery id.
  Future<List<PromptDelivery>> recoverableDeliveries(String sessionId) async {
    final recoveries = <PromptDelivery>[];
    for (final seat in await promptDeliveries.store.seatsForSession(
      sessionId,
    )) {
      final history = await promptDeliveries.store.forSeat(seat);
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.state == PromptDeliveryState.submittedUnknown) {
        recoveries.add(latest);
      }
    }
    return recoveries;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _seatTails.clear();
  }
}
