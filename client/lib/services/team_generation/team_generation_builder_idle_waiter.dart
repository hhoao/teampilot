import 'dart:async';

import 'team_generation_session_port.dart';

/// Result of waiting for the builder session to go idle.
enum TeamGenerationBuilderIdleResult { idle, timeout, missing }

/// Waits for the builder session's existing turn-complete/ready signal plus a
/// bounded quiet window before cleanup is allowed.
///
/// Reads the current activity first, then subscribes through
/// [TeamGenerationSessionPort.activityStream]. The quiet timer restarts on
/// any busy transition and cancels on session disappearance. Busy/idle is
/// never inferred from terminal output text.
final class TeamGenerationBuilderIdleWaiter {
  TeamGenerationBuilderIdleWaiter({
    required TeamGenerationSessionPort sessionPort,
  }) : _sessionPort = sessionPort;

  final TeamGenerationSessionPort _sessionPort;

  Future<TeamGenerationBuilderIdleResult> wait({
    required String sessionId,
    required Duration quietWindow,
    required Duration timeout,
  }) async {
    final ready = Completer<TeamGenerationBuilderIdleResult>();
    Timer? quietTimer;
    Timer? timeoutTimer;
    StreamSubscription<PortActivity>? subscription;

    Future<void> settle(TeamGenerationBuilderIdleResult result) async {
      if (ready.isCompleted) return;
      quietTimer?.cancel();
      timeoutTimer?.cancel();
      await subscription?.cancel();
      ready.complete(result);
    }

    void restartQuietTimer(bool readyToChat) {
      if (!readyToChat) {
        quietTimer?.cancel();
        quietTimer = null;
        return;
      }
      quietTimer?.cancel();
      quietTimer = Timer(quietWindow, () {
        unawaited(settle(TeamGenerationBuilderIdleResult.idle));
      });
    }

    timeoutTimer = Timer(timeout, () {
      unawaited(settle(TeamGenerationBuilderIdleResult.timeout));
    });

    subscription = _sessionPort.activityStream(sessionId).listen((activity) {
      if (activity.sessionId != sessionId) return;
      restartQuietTimer(activity.readyToChat);
    }, onError: (_) {
      unawaited(settle(TeamGenerationBuilderIdleResult.missing));
    });

    return ready.future;
  }
}
