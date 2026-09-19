import 'dart:async';

/// Settle intervals for full-screen PTY inject ACK polling.
abstract final class PtyInjectAckTiming {
  PtyInjectAckTiming._();

  /// Ink / bracketed-paste TUIs need time to apply repeated Ctrl-U clears.
  static const afterClear = Duration(milliseconds: 350);

  /// Grid mirror lags PTY output; probe too early → false paste-not-found.
  static const afterPaste = Duration(milliseconds: 700);

  static const afterCr = Duration(milliseconds: 800);

  /// Pause before clear→paste reinject so a slow first paste can land.
  static const afterReinject = Duration(milliseconds: 500);

  static const crMaxAttempts = 4;
  static const reinjectMaxAttempts = 2;
  static const nudgeMaxAttempts = 4;
}

/// Zero-based attempt with inclusive [maxAttempts] cap.
typedef PtyAckAttempt = ({int attempt, int maxAttempts});

enum PtyAckPollOutcome {
  /// [isAcked] returned true within the attempt budget.
  acked,

  /// All attempts exhausted without ack.
  exhausted,

  /// [aborted] returned true before a final outcome.
  aborted,
}

/// Waits [settle], checks [isAcked], then optionally runs [onRetry] before the
/// next attempt. The first check happens after the initial [settle] — call
/// [onRetry] from the caller before this when the first probe should follow an
/// action (e.g. CR already sent).
Future<PtyAckPollOutcome> ptyAckPollRetry({
  required Duration settle,
  required int maxAttempts,
  required bool Function() aborted,
  required FutureOr<bool> Function(PtyAckAttempt attempt) isAcked,
  required Future<void> Function(PtyAckAttempt attempt) onRetry,
  void Function(PtyAckAttempt attempt)? onStillPending,
  void Function(PtyAckAttempt attempt)? onAcked,
}) async {
  assert(maxAttempts >= 0);
  for (var attempt = 0; attempt <= maxAttempts; attempt++) {
    if (aborted()) return PtyAckPollOutcome.aborted;
    await Future<void>.delayed(settle);
    if (aborted()) return PtyAckPollOutcome.aborted;

    final ctx = (attempt: attempt, maxAttempts: maxAttempts);
    if (await isAcked(ctx)) {
      onAcked?.call(ctx);
      return PtyAckPollOutcome.acked;
    }
    onStillPending?.call(ctx);
    if (attempt < maxAttempts) {
      await onRetry(ctx);
    }
  }
  return PtyAckPollOutcome.exhausted;
}
