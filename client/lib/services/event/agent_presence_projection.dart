import 'dart:async';

import 'agent_presence_event.dart';
import 'dispatcher.dart';

/// Reduces [AgentPresenceEvent]s into the latest availability per seat.
///
/// Registered on the central dispatcher by app_shell. Consumers (the presence
/// cubit today, mobile sync in phase 3) read [availabilityFor] / [snapshot] and
/// listen to [changes] for re-render notifications.
final class AgentPresenceProjection
    implements EventHandler<AgentPresenceEvent> {
  final Map<PresenceSeatKey, AgentPresenceKind> _bySeat = {};
  final StreamController<PresenceSeatKey> _changes =
      StreamController<PresenceSeatKey>.broadcast();

  /// An unmodifiable view of the current availability per seat.
  Map<PresenceSeatKey, AgentPresenceKind> get snapshot =>
      Map.unmodifiable(_bySeat);

  /// Fires the seat whose availability value changed. Broadcast: late
  /// subscribers only see subsequent changes.
  Stream<PresenceSeatKey> get changes => _changes.stream;

  /// The latest availability for [seat], or null if the seat is unknown.
  AgentPresenceKind? availabilityFor(PresenceSeatKey seat) => _bySeat[seat];

  Set<String> get occupiedSessionIds => {
    for (final seat in _bySeat.keys) seat.sessionId,
  };

  @override
  void handle(AgentPresenceEvent event) {
    if (event.eventKind == AgentPresenceKind.cleared) {
      if (!_bySeat.containsKey(event.seat)) return;
      _bySeat.remove(event.seat);
      if (!_changes.isClosed) _changes.add(event.seat);
      return;
    }
    final previous = _bySeat[event.seat];
    if (previous == event.eventKind) return;
    _bySeat[event.seat] = event.eventKind;
    if (!_changes.isClosed) _changes.add(event.seat);
  }

  /// Drops [seat]'s entry without broadcasting (the seat is gone, not changed).
  /// Idempotent: removing an unknown seat is a no-op.
  void removeSeat(PresenceSeatKey seat) {
    _bySeat.remove(seat);
  }

  /// Drops every seat and broadcasts each removed key. Used by transport
  /// `snapshotBegin`. Idempotent on an empty projection.
  void clearAll() {
    if (_bySeat.isEmpty) return;
    final seats = _bySeat.keys.toList();
    _bySeat.clear();
    if (_changes.isClosed) return;
    for (final seat in seats) {
      _changes.add(seat);
    }
  }

  Future<void> close() => _changes.close();
}
