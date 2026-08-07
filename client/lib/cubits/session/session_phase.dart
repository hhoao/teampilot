/// Lifecycle of one conversation, scoped to its own [SessionPod]. Never read
/// across pods — a session's overlay is a pure function of its own phase.
enum SessionPhase {
  idle,
  provisioning,
  connecting,
  running,
  paused,
  error;

  bool get isLaunching =>
      this == SessionPhase.provisioning || this == SessionPhase.connecting;

  bool get isRunning => this == SessionPhase.running;
}
