import 'dart:async';

import '../../utils/logging/logger.dart';
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
    _enqueueApply(event.seat, () => promptDeliveries.onRuntimeEvent(event));
  }

  void _enqueueApply(
    RuntimeSeatKey seat,
    Future<void> Function() apply,
  ) {
    final previous = _seatTails[seat] ?? Future<void>.value();
    _seatTails[seat] = previous
        .then((_) => apply())
        .then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {
          // A failed delivery apply (store IO error or projection throw) would
          // otherwise silently leave the delivery submitIssued with the fence
          // open. Log loud so the missed re-application is visible to
          // diagnostics.
          appLogger.w(
            '[agent-runtime] coordinator event apply failed '
            'seat=${seat.sessionId}/${seat.memberId}: $error',
            error: error,
            stackTrace: stackTrace,
          );
        });
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
        _enqueueApply(seat, () => promptDeliveries.onRuntimeEvent(event));
      }
      await settle(seat);
      await promptDeliveries.restoreSeat(seat);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _seatTails.clear();
  }
}
