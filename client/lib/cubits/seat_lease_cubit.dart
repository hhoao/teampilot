import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_status/agent_attention_state.dart' show agentSeatKey;
import '../services/agent_status/seat_lease.dart';
import '../utils/logging/logger.dart';

/// How often [SeatLeaseCubit] physically prunes TTL-expired leases.
const Duration seatLeasePruneInterval = Duration(minutes: 1);

class SeatLeaseState extends Equatable {
  const SeatLeaseState({this.leases = const {}});

  /// seatKey (`agentSeatKey`) → leaseId → lease.
  final Map<String, Map<String, SeatLease>> leases;

  bool seatHasLeases({
    required String sessionId,
    required String memberId,
  }) =>
      (leases[agentSeatKey(sessionId: sessionId, memberId: memberId)] ??
          const {}).isNotEmpty;

  bool sessionHasLeases(String sessionId) {
    final prefix = agentSeatKey(sessionId: sessionId, memberId: '');
    for (final e in leases.entries) {
      if (e.key.startsWith(prefix) && e.value.isNotEmpty) return true;
    }
    return false;
  }

  /// Drops leases past their kind TTL. Pure — the cubit logs the expiries.
  SeatLeaseState pruned(DateTime now) {
    var changed = false;
    final next = <String, Map<String, SeatLease>>{};
    for (final e in leases.entries) {
      final kept = <String, SeatLease>{};
      for (final lease in e.value.entries) {
        if (now.difference(lease.value.acquiredAt) <
            seatLeaseTtl(lease.value.kind)) {
          kept[lease.key] = lease.value;
        } else {
          changed = true;
        }
      }
      if (kept.isNotEmpty) {
        next[e.key] = kept;
      } else if (e.value.isNotEmpty) {
        changed = true;
      }
    }
    if (!changed) return this;
    return SeatLeaseState(leases: next);
  }

  @override
  List<Object?> get props => [leases];
}

/// Holds per-seat keep-alive leases ("the CLI process must survive").
/// Driven by `seatLeaseProjection` from the runtime-event gateway; consumed
/// by the idle terminal reclaim. Independent of attention semantics.
class SeatLeaseCubit extends Cubit<SeatLeaseState> {
  SeatLeaseCubit({DateTime Function()? clock, Duration? pruneInterval})
      : _clock = clock ?? DateTime.now,
        super(const SeatLeaseState()) {
    final interval = pruneInterval ?? seatLeasePruneInterval;
    if (interval != null) {
      _pruneTimer = Timer.periodic(interval, (_) => pruneStale());
    }
  }

  final DateTime Function() _clock;
  Timer? _pruneTimer;

  /// Idempotent per lease id; last delivery wins on `acquiredAt`.
  void acquire({
    required String sessionId,
    required String memberId,
    required SeatLease lease,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final seat = Map<String, SeatLease>.of(seats[key] ?? const {});
    seat[lease.id] = lease;
    seats[key] = seat;
    emit(SeatLeaseState(leases: seats));
  }

  /// No-op when the lease is absent (e.g. the start hook POST was lost).
  void release({
    required String sessionId,
    required String memberId,
    required String leaseId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final seat = state.leases[key];
    if (seat == null || !seat.containsKey(leaseId)) return;
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final remaining = Map<String, SeatLease>.of(seat)..remove(leaseId);
    if (remaining.isEmpty) {
      seats.remove(key);
    } else {
      seats[key] = remaining;
    }
    emit(SeatLeaseState(leases: seats));
  }

  /// Drop one seat (PTY exit, disconnect, reclaim-discard).
  void clearSeat({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    if (!state.leases.containsKey(key)) return;
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases)
      ..remove(key);
    emit(SeatLeaseState(leases: seats));
  }

  /// Drop every seat in a session (tab close, team-session restart).
  void clearSession(String sessionId) {
    final prefix = agentSeatKey(sessionId: sessionId, memberId: '');
    final seats = Map<String, Map<String, SeatLease>>.of(state.leases);
    final before = seats.length;
    seats.removeWhere((k, _) => k.startsWith(prefix));
    if (seats.length == before) return;
    emit(SeatLeaseState(leases: seats));
  }

  /// Physically prune TTL-expired leases, logging each expiry — a TTL
  /// expiry means the paired completion event never arrived (notification
  /// lost, CLI killed, task stopped without notifying).
  void pruneStale() {
    if (isClosed) return;
    final now = _clock();
    final next = state.pruned(now);
    if (next == state) return;
    for (final e in state.leases.entries) {
      for (final lease in e.value.values) {
        if (now.difference(lease.acquiredAt) >= seatLeaseTtl(lease.kind)) {
          appLogger.w(
            '[seat-lease] ttl-expired seat=${e.key} '
            'kind=${lease.kind.name} id=${lease.id}',
          );
        }
      }
    }
    emit(next);
  }

  @override
  Future<void> close() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    return super.close();
  }
}
