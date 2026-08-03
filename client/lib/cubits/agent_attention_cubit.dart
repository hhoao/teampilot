import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_status_event.dart';
import '../services/agent_status/agent_status_normalizer.dart';
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
    this.dismissedAskRequestId,
    this.askReplyError,
  });

  final AgentSeatAttention attention;
  final DateTime updatedAt;

  /// Last applied event (sticky permission context).
  final AgentStatusEvent? lastEvent;

  /// Ask id optimistically dismissed via [AgentAttentionCubit.markAskAnswered].
  /// Same-id waiting events are ignored until restore or a new ask arrives.
  final String? dismissedAskRequestId;

  /// Optional error from `question.reply_failed` after optimistic dismiss.
  final String? askReplyError;

  @override
  List<Object?> get props => [
    attention,
    updatedAt,
    lastEvent,
    dismissedAskRequestId,
    askReplyError,
  ];
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

  /// Fresh seat entry, or null when absent / stale.
  AgentSeatAttentionEntry? entryFor({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final entry = seats[key];
    if (entry == null || _isStale(entry, _now)) return null;
    return entry;
  }

  /// Attention for a seat, or null when absent / stale.
  AgentSeatAttention? attentionFor({
    required String sessionId,
    required String memberId,
  }) => entryFor(sessionId: sessionId, memberId: memberId)?.attention;

  /// True when any fresh seat in [sessionId] is [AgentSeatAttention.waiting].
  bool sessionHasWaiting(String sessionId) =>
      waitingMemberIds(sessionId).isNotEmpty;

  /// True when any fresh seat in [sessionId] is [AgentSeatAttention.waiting] or
  /// [AgentSeatAttention.working] — Orca-style "agent still in a turn" for
  /// sidebar / History working indicators (PTY idle-watch may have ended the
  /// latch while permission was held).
  ///
  /// When [includeMember] is set, seats for which it returns false are ignored
  /// (e.g. mixed members parked in `wait_for_message`).
  bool sessionIsAgentActive(
    String sessionId, {
    bool Function(String memberId)? includeMember,
  }) {
    final prefix = '${sessionId.trim()}\u0000';
    final now = _now;
    for (final e in seats.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (_isStale(e.value, now)) continue;
      final memberId = e.key.substring(prefix.length);
      if (includeMember != null && !includeMember(memberId)) continue;
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

  /// Optimistically dismiss a waiting ask: move to [AgentSeatAttention.working]
  /// while retaining [AgentSeatAttentionEntry.lastEvent] so
  /// `question.reply_failed` can restore the card.
  ///
  /// Reads the dismissed id from [AgentSeatAttentionEntry.lastEvent]'s
  /// [AgentStatusEvent.askRequestId] — callers do not pass an id.
  void markAskAnswered({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final existing = state.seats[key];
    if (existing == null) return;
    if (existing.attention != AgentSeatAttention.waiting) return;
    final askRequestId = existing.lastEvent?.askRequestId;
    if (askRequestId == null || askRequestId.isEmpty) return;

    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: AgentSeatAttention.working,
      updatedAt: _clock(),
      lastEvent: existing.lastEvent,
      dismissedAskRequestId: askRequestId,
      askReplyError: null,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
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
    // Claude Code's --dangerously-skip-permissions does not skip
    // AskUserQuestion, and opencode's question tool always needs an answer —
    // both still block on an interactive prompt the operator must answer.
    // Keep the seat waiting for them so the chat card stays available.
    final isAskUserQuestionWaiting =
        event.state == AgentSeatAttention.waiting &&
        (isAskUserQuestionTool(event.toolName) ||
            event.hookEventName == 'question.asked');
    if (skipPermissions &&
        event.state == AgentSeatAttention.waiting &&
        !isAskUserQuestionWaiting) {
      pruneStale();
      return;
    }

    final now = _clock();
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final pruned = state.pruned(now);
    final existingEntry = pruned.seats[key];
    final previous = existingEntry?.lastEvent;

    // Ignore echoed waiting for an optimistically dismissed ask.
    final dismissedId = existingEntry?.dismissedAskRequestId;
    if (event.state == AgentSeatAttention.waiting &&
        event.askRequestId != null &&
        dismissedId != null &&
        event.askRequestId == dismissedId) {
      if (pruned != state) emit(pruned);
      return;
    }

    // Restore waiting ask card after reply_failed (keep prior questions).
    final isRestore =
        event.restoreAskWaiting ||
        event.hookEventName == 'question.reply_failed';
    if (isRestore && existingEntry != null) {
      final eventAskId = event.askRequestId;
      final lastAskId = existingEntry.lastEvent?.askRequestId;
      final matches =
          eventAskId != null &&
          (eventAskId == dismissedId || eventAskId == lastAskId);
      if (matches) {
        final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
        seats[key] = AgentSeatAttentionEntry(
          attention: AgentSeatAttention.waiting,
          updatedAt: now,
          lastEvent: existingEntry.lastEvent,
          dismissedAskRequestId: null,
          askReplyError: event.message,
        );
        emit(AgentAttentionState(seats: seats, clock: _clock));
        return;
      }
    }

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
