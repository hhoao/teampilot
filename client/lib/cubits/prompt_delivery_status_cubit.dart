import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_runtime/agent_runtime.dart';

/// One explicitly unresolved prompt delivery surfaced for review/retry.
class PromptDeliveryRecovery extends Equatable {
  const PromptDeliveryRecovery({
    required this.deliveryId,
    required this.text,
  });

  final String deliveryId;
  final String text;

  @override
  List<Object?> get props => [deliveryId, text];
}

/// Seat-keyed recovery candidates per session.
class PromptDeliveryStatusState extends Equatable {
  const PromptDeliveryStatusState({this.recoveries = const {}});

  final Map<String, PromptDeliveryRecovery> recoveries;

  PromptDeliveryRecovery? recoveryFor(String sessionId, String memberId) =>
      recoveries[recoverySeatKey(sessionId, memberId)];

  static String recoverySeatKey(String sessionId, String memberId) =>
      '$sessionId\u0000$memberId';

  @override
  List<Object?> get props => [recoveries];
}

/// Surfaces durable `submittedUnknown` deliveries to the compose section.
///
/// The state is loaded from the app-scoped runtime's delivery store (never
/// from inside a widget build); retry always goes through the injected
/// resubmit callback which creates a NEW delivery id via the fenced direct
/// path — the unresolved record is never resumed.
class PromptDeliveryStatusCubit extends Cubit<PromptDeliveryStatusState> {
  PromptDeliveryStatusCubit({
    required AgentRuntime runtime,
    Future<bool> Function(String sessionId, String memberId, String text)?
    resubmit,
  }) : _runtime = runtime,
       _resubmit = resubmit,
       super(const PromptDeliveryStatusState());

  final AgentRuntime _runtime;
  final Future<bool> Function(String sessionId, String memberId, String text)?
  _resubmit;
  final Set<String> _refreshingSessions = {};

  /// Reloads the recovery candidates of [sessionId] from the durable store.
  Future<void> refreshSession(String sessionId) async {
    final trimmed = sessionId.trim();
    if (trimmed.isEmpty) return;
    if (!_refreshingSessions.add(trimmed)) return;
    try {
      final deliveries = await _runtime.recoverableDeliveries(trimmed);
      if (isClosed) return;
      final next = Map<String, PromptDeliveryRecovery>.of(state.recoveries)
        ..removeWhere((seatKey, _) => seatKey.startsWith('$trimmed\u0000'));
      for (final delivery in deliveries) {
        next[PromptDeliveryStatusState.recoverySeatKey(
          delivery.seat.sessionId,
          delivery.seat.memberId,
        )] = PromptDeliveryRecovery(
          deliveryId: delivery.id,
          text: delivery.text,
        );
      }
      emit(PromptDeliveryStatusState(recoveries: next));
    } finally {
      _refreshingSessions.remove(trimmed);
    }
  }

  /// Explicit user retry: submits the retained text as a NEW delivery through
  /// the normal fenced path, then refreshes. Returns whether the new delivery
  /// was accepted.
  Future<bool> retry({
    required String sessionId,
    required String memberId,
  }) async {
    final recovery = state.recoveryFor(sessionId.trim(), memberId.trim());
    if (recovery == null || _resubmit == null) return false;
    final ok = await _resubmit(sessionId, memberId, recovery.text);
    await refreshSession(sessionId);
    return ok;
  }
}
