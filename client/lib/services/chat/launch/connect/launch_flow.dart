/// Launch-owned connect-job phases. Observers subscribe; they do not drive
/// the pipeline.
enum LaunchFlowPhase { queued, settled }

/// One member-seat transition in the connect scheduler.
final class LaunchFlowEvent {
  const LaunchFlowEvent({
    required this.sessionId,
    required this.memberId,
    required this.phase,
  });

  final String sessionId;
  final String memberId;
  final LaunchFlowPhase phase;

  @override
  bool operator ==(Object other) =>
      other is LaunchFlowEvent &&
      other.sessionId == sessionId &&
      other.memberId == memberId &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(sessionId, memberId, phase);
}

/// Notified when a connect identity is queued or leaves the scheduler.
abstract interface class LaunchFlowListener {
  void onLaunchFlow(LaunchFlowEvent event);
}

final class NoopLaunchFlowListener implements LaunchFlowListener {
  const NoopLaunchFlowListener();

  @override
  void onLaunchFlow(LaunchFlowEvent event) {}
}
