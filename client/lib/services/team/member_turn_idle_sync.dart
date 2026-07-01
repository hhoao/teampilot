import '../terminal/terminal_session.dart';

/// PTY quiet-after-activity turn sync shared by simple and mixed idle watch.
abstract final class MemberTurnIdleSync {
  MemberTurnIdleSync._();

  /// On [inTurn] rising edge, latches the shell tracker. When the visible PTY
  /// fingerprint has been unchanged for [TerminalActivityTracker.idleAfter],
  /// invokes [endTurn].
  ///
  /// Returns whether the member should count as working for session-level spinners.
  static bool tick({
    required String turnKey,
    required bool inTurn,
    required TerminalSession shell,
    required Map<String, bool> wasInTurn,
    required void Function() endTurn,
  }) {
    if (!shell.isRunning) {
      wasInTurn.remove(turnKey);
      return false;
    }
    final was = wasInTurn[turnKey] ?? false;
    if (inTurn && !was) {
      shell.activityTracker.latchTurnQuietBaseline();
    }
    wasInTurn[turnKey] = inTurn;
    if (!inTurn) return false;
    if (shell.activityTracker.isQuietAfterTurnPtyActivity) {
      endTurn();
      wasInTurn[turnKey] = false;
      return false;
    }
    return true;
  }
}
