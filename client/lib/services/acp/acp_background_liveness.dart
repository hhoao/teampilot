/// Answer to "does this ACP session still have out-of-turn work in flight?".
///
/// The ACP wire goes silent once a prompt resolves, so a lease armed from a
/// background launch (task / shell) has no protocol completion signal. CLIs
/// that leave on-disk evidence of that work can be polled instead.
enum AcpBackgroundLiveness {
  /// At least one background shell or child agent is still alive.
  running,

  /// Every piece of out-of-turn work this session left behind has finished.
  idle,

  /// Nothing readable: no evidence either way. Keep the lease until the watch
  /// window closes rather than guessing.
  unknown,
}

/// Polls the agent's own on-disk evidence for out-of-turn work.
abstract interface class AcpBackgroundLivenessProbe {
  /// Never throws: [AcpBackgroundLiveness.unknown] covers read failures.
  ///
  /// [since] is when the watch armed. Evidence older than that (minus a grace
  /// window) cannot prove *this* watch's work finished — a previous task's
  /// closed transcript must not clear a fresh lease — so implementations
  /// answer [AcpBackgroundLiveness.unknown] instead of [AcpBackgroundLiveness.idle].
  Future<AcpBackgroundLiveness> probe({DateTime? since});
}

/// Builds a [AcpBackgroundLivenessProbe] for one agent session, or null when
/// this CLI keeps no readable evidence.
typedef AcpBackgroundLivenessProbeFactory =
    AcpBackgroundLivenessProbe? Function({
      required String sessionToolDir,
      required String sessionId,
    });
