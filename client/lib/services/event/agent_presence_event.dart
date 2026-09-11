import 'dispatcher.dart';

/// Availability phase of one agent seat, plus [cleared] (a retraction verb).
///
/// [booting] / [working] / [idle] mirror `MemberAvailability` one-to-one.
/// [cleared] is NOT an availability: it means the seat is gone (disconnect /
/// unbind). The wire codec maps it to `op:clear`.
enum AgentPresenceKind { booting, working, idle, cleared }

/// Seat identity (session + team member) for presence events.
///
/// Deliberately NOT `agent_runtime`'s `RuntimeSeatKey`: the event package must
/// not depend on a feature package. Phase 2.5 (hook-event convergence) maps
/// between the two.
final class PresenceSeatKey {
  const PresenceSeatKey({required this.sessionId, required this.memberId});

  final String sessionId;
  final String memberId;

  @override
  bool operator ==(Object other) =>
      other is PresenceSeatKey &&
      other.sessionId == sessionId &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(sessionId, memberId);

  @override
  String toString() => 'PresenceSeatKey($sessionId/$memberId)';
}

/// Emitted when a seat's composed availability changes value.
final class AgentPresenceEvent implements DispatcherEvent<AgentPresenceKind> {
  const AgentPresenceEvent({
    required this.seat,
    required this.eventKind,
    required this.timestamp,
  });

  final PresenceSeatKey seat;

  @override
  final AgentPresenceKind eventKind;

  @override
  final DateTime timestamp;

  String get sessionId => seat.sessionId;
  String get memberId => seat.memberId;
}
