/// Backoff policy for storage/session-plane reconnect after a profile goes down.
class SshProfileReconnectPolicy {
  const SshProfileReconnectPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
    this.disconnectCoalesce = const Duration(milliseconds: 150),
  });

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  /// Window to merge multiple TCP drops (storage + member planes) into one
  /// disconnect signal per profile.
  final Duration disconnectCoalesce;

  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return initialDelay;
    final multiplier = 1 << (attempt - 1).clamp(0, 10);
    final scaled = Duration(
      milliseconds: initialDelay.inMilliseconds * multiplier,
    );
    return scaled > maxDelay ? maxDelay : scaled;
  }
}
