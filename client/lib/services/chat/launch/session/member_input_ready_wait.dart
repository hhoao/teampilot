/// Wait policy for [TabMemberMaterializer.ensureMemberInputReady].
///
/// Landing used to wrap that waiter in a 120s [TimeoutException]. Cursor can
/// sit on a black PTY longer than that while plugins load; the process is
/// still alive. Fail only when the shell is dead or [defaultMemberInputReadyCap]
/// elapses.
const Duration defaultMemberInputReadyCap = Duration(minutes: 10);

enum MemberInputReadyFailure { dead, timedOut }

final class MemberInputReadyException implements Exception {
  const MemberInputReadyException(this.failure);

  final MemberInputReadyFailure failure;

  @override
  String toString() => 'MemberInputReadyException($failure)';
}

final class MemberShellReadySnapshot {
  const MemberShellReadySnapshot({
    required this.startFailed,
    required this.isConnecting,
    required this.isRunning,
    required this.isConnected,
  });

  final bool startFailed;
  final bool isConnecting;
  final bool isRunning;
  final bool isConnected;
}

bool memberInputWaitSawRunning(MemberShellReadySnapshot shell) =>
    shell.isRunning || shell.isConnected;

bool memberInputWaitShouldAbortDead({
  required MemberShellReadySnapshot shell,
  required bool sawRunning,
}) {
  if (shell.startFailed) return true;
  return sawRunning &&
      !shell.isConnecting &&
      !shell.isRunning &&
      !shell.isConnected;
}

bool memberInputWaitTimedOut({
  required DateTime startedAt,
  required Duration cap,
  required DateTime now,
}) => now.difference(startedAt) >= cap;
