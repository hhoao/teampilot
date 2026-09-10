import 'dispatcher.dart';

/// Session lifecycle vocabulary (per-family event types, YARN style).
enum SessionLifecycleKind {
  sessionSpawned,
  sessionStarted,
  seatStarted,
  seatInterrupted,
  seatExited,
  sessionClosed,
}

/// Session lifecycle events flowing through the central [Dispatcher].
///
/// - [SessionLifecycleEvent.sessionSpawned]: a session object exists
///   (in-memory snapshot appended, sessionId determined).
/// - [SessionLifecycleEvent.sessionStarted]: the session surfaced
///   successfully to the user (launch returned an `opened` status).
/// - [SessionLifecycleEvent.sessionClosed]: session deletion began.
///
/// The seat-level kinds ([SessionLifecycleKind.seatStarted],
/// [SessionLifecycleKind.seatInterrupted],
/// [SessionLifecycleKind.seatExited]) are vocabulary only in this phase —
/// no publish points yet; they will be wired when the agent runtime is
/// migrated onto the dispatcher.
sealed class SessionLifecycleEvent
    implements DispatcherEvent<SessionLifecycleKind> {
  const SessionLifecycleEvent._({
    required this.kind,
    required this.sessionId,
    required this.workspaceId,
    required this.timestamp,
    this.memberId,
  });

  factory SessionLifecycleEvent.sessionSpawned({
    required String sessionId,
    required String workspaceId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.sessionSpawned,
    sessionId: sessionId,
    workspaceId: workspaceId,
    timestamp: timestamp,
  );

  factory SessionLifecycleEvent.sessionStarted({
    required String sessionId,
    required String workspaceId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.sessionStarted,
    sessionId: sessionId,
    workspaceId: workspaceId,
    timestamp: timestamp,
  );

  factory SessionLifecycleEvent.seatStarted({
    required String sessionId,
    required String workspaceId,
    required String memberId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.seatStarted,
    sessionId: sessionId,
    workspaceId: workspaceId,
    memberId: memberId,
    timestamp: timestamp,
  );

  factory SessionLifecycleEvent.seatInterrupted({
    required String sessionId,
    required String workspaceId,
    required String memberId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.seatInterrupted,
    sessionId: sessionId,
    workspaceId: workspaceId,
    memberId: memberId,
    timestamp: timestamp,
  );

  factory SessionLifecycleEvent.seatExited({
    required String sessionId,
    required String workspaceId,
    required String memberId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.seatExited,
    sessionId: sessionId,
    workspaceId: workspaceId,
    memberId: memberId,
    timestamp: timestamp,
  );

  factory SessionLifecycleEvent.sessionClosed({
    required String sessionId,
    required String workspaceId,
    required DateTime timestamp,
  }) => _SessionLifecycleEvent(
    kind: SessionLifecycleKind.sessionClosed,
    sessionId: sessionId,
    workspaceId: workspaceId,
    timestamp: timestamp,
  );

  @override
  final SessionLifecycleKind kind;
  final String sessionId;
  final String workspaceId;

  /// Seat-scoped member (seat events only; null for session-level events).
  final String? memberId;

  @override
  final DateTime timestamp;
}

/// The single concrete leaf (the family is sealed only to pin its vocabulary).
final class _SessionLifecycleEvent extends SessionLifecycleEvent {
  const _SessionLifecycleEvent({
    required super.kind,
    required super.sessionId,
    required super.workspaceId,
    required super.timestamp,
    super.memberId,
  }) : super._();
}
