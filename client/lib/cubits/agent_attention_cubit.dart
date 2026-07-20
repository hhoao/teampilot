import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_status_event.dart';
import '../services/agent_status/claude_permission_sticky.dart';

/// Orca-aligned TTL: drop seat attention with no refresh after this duration.
const Duration agentAttentionStaleAfter = Duration(minutes: 30);

/// How often [AgentAttentionCubit] physically prunes stale seats so BlocBuilder
/// consumers clear waiting without waiting for a new hook.
const Duration agentAttentionPruneInterval = Duration(minutes: 1);

/// Per-seat attention snapshot with last-update timestamp for stale pruning.
class AgentSeatAttentionEntry extends Equatable {
  const AgentSeatAttentionEntry({
    required this.attention,
    required this.updatedAt,
    this.lastEvent,
  });

  final AgentSeatAttention attention;
  final DateTime updatedAt;

  /// Last applied event (sticky permission context).
  final AgentStatusEvent? lastEvent;

  @override
  List<Object?> get props => [attention, updatedAt, lastEvent];
}

/// Seat-keyed agent attention for History banner / sidebar consumers.
class AgentAttentionState extends Equatable {
  const AgentAttentionState({
    this.seats = const {},
    DateTime Function()? clock,
  }) : _clock = clock;

  final Map<String, AgentSeatAttentionEntry> seats;
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  /// Attention for a seat, or null when absent / stale.
  AgentSeatAttention? attentionFor({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final entry = seats[key];
    if (entry == null || _isStale(entry, _now)) return null;
    return entry.attention;
  }

  /// True when any fresh seat in [sessionId] is [AgentSeatAttention.waiting].
  bool sessionHasWaiting(String sessionId) =>
      waitingMemberIds(sessionId).isNotEmpty;

  /// True when any fresh seat is [AgentSeatAttention.waiting] or
  /// [AgentSeatAttention.working] — Orca-style "agent still in a turn" for
  /// sidebar / History working indicators (PTY idle-watch may have ended the
  /// latch while permission was held).
  bool sessionIsAgentActive(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final now = _now;
    for (final e in seats.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (_isStale(e.value, now)) continue;
      final a = e.value.attention;
      if (a == AgentSeatAttention.waiting || a == AgentSeatAttention.working) {
        return true;
      }
    }
    return false;
  }

  /// Member ids currently waiting (fresh) for [sessionId].
  List<String> waitingMemberIds(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final now = _now;
    final ids = <String>[];
    for (final e in seats.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (_isStale(e.value, now)) continue;
      if (e.value.attention != AgentSeatAttention.waiting) continue;
      ids.add(e.key.substring(prefix.length));
    }
    return ids;
  }

  AgentAttentionState copyWith({
    Map<String, AgentSeatAttentionEntry>? seats,
  }) => AgentAttentionState(seats: seats ?? this.seats, clock: _clock);

  /// Drop entries older than [agentAttentionStaleAfter].
  AgentAttentionState pruned([DateTime? now]) {
    final at = now ?? _now;
    final next = <String, AgentSeatAttentionEntry>{};
    for (final e in seats.entries) {
      if (!_isStale(e.value, at)) next[e.key] = e.value;
    }
    if (next.length == seats.length) return this;
    return copyWith(seats: next);
  }

  static bool _isStale(AgentSeatAttentionEntry entry, DateTime now) =>
      now.difference(entry.updatedAt) > agentAttentionStaleAfter;

  @override
  List<Object?> get props => [seats];
}

/// Holds seat-keyed attention; skip-permissions gate + 30m stale TTL.
class AgentAttentionCubit extends Cubit<AgentAttentionState> {
  AgentAttentionCubit({
    DateTime Function()? clock,
    Duration? pruneInterval = agentAttentionPruneInterval,
  }) : _clock = clock ?? DateTime.now,
       super(AgentAttentionState(clock: clock ?? DateTime.now)) {
    if (pruneInterval != null) {
      _pruneTimer = Timer.periodic(pruneInterval, (_) => pruneStale());
    }
  }

  final DateTime Function() _clock;
  Timer? _pruneTimer;

  /// Physically drop stale seats and emit when the map changes so BlocBuilder
  /// consumers clear waiting after TTL without a new hook.
  void pruneStale() {
    if (isClosed) return;
    final pruned = state.pruned(_clock());
    if (pruned != state) emit(pruned);
  }

  /// Apply a normalized status event for one seat.
  ///
  /// When [skipPermissions] is true and [event] is waiting, the event is
  /// ignored (prior non-waiting state kept, or no-op if absent).
  ///
  /// Sticky Claude permission (Orca): concurrent subagent tool activity does
  /// not clear waiting unless the approved tool resumes or an explicit prompt
  /// arrives.
  void applyEvent({
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
    required bool skipPermissions,
  }) {
    if (skipPermissions && event.state == AgentSeatAttention.waiting) {
      pruneStale();
      return;
    }

    final now = _clock();
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final pruned = state.pruned(now);
    final previous = pruned.seats[key]?.lastEvent;
    final effective = attachClaudePermissionToolUseId(previous, event);

    if (shouldKeepClaudePermissionVisible(previous, effective)) {
      // Keep the waiting row; do not let other-subagent activity overwrite it.
      if (pruned != state) emit(pruned);
      return;
    }

    final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: effective.state,
      updatedAt: now,
      lastEvent: effective,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Remove one seat (e.g. PTY dispose / disconnect).
  void clearSeat({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    if (!state.seats.containsKey(key)) return;
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats)
      ..remove(key);
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Remove all seats for a session (e.g. tab close).
  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    final before = seats.length;
    seats.removeWhere((k, _) => k.startsWith(prefix));
    if (seats.length == before) return;
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  @override
  Future<void> close() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    return super.close();
  }
}
