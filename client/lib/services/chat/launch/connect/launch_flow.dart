/// Launch-owned connect-job phases. Observers subscribe; they do not drive
/// the pipeline.
enum LaunchFlowPhase { queued, settled }

/// One member-seat transition in the connect scheduler.
final class LaunchFlowEvent {
  const LaunchFlowEvent({
    required this.sessionId,
    required this.memberId,
    required this.phase,
    this.showsConnectUi = true,
  });

  final String sessionId;
  final String memberId;
  final LaunchFlowPhase phase;

  /// Whether this job actually attaches a transport, so the UI may treat the
  /// session as "connecting".
  ///
  /// Deferred preparation jobs (`connectShell: false`) still stage a shell /
  /// runtime, but nothing is launched: they must not flip the pod phase or the
  /// sidebar spinner (a history-only open would flash "running").
  final bool showsConnectUi;

  @override
  bool operator ==(Object other) =>
      other is LaunchFlowEvent &&
      other.sessionId == sessionId &&
      other.memberId == memberId &&
      other.phase == phase &&
      other.showsConnectUi == showsConnectUi;

  @override
  int get hashCode => Object.hash(sessionId, memberId, phase, showsConnectUi);
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
