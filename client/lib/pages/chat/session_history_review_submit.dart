import 'dart:async';

import '../../cubits/chat/model/session_connect_request.dart';
import '../../utils/logging/logger.dart';

/// Preference gate: when false (default), History continue stays on History.
bool shouldSwitchToTerminalAfterHistorySubmit(
  bool historySubmitSwitchesToTerminal,
) => historySubmitSwitchesToTerminal;

/// Re-entrancy lock for History continue while connect/inject is in flight.
///
/// History stays mounted during submit, so compose can fire twice before the
/// first await returns; callers must gate UI on [isBusy] as well.
final class HistoryContinueSubmitLock {
  var _busy = false;

  bool get isBusy => _busy;

  /// Runs [action] once; overlapping calls return `false` without invoking it.
  Future<bool> run(Future<bool> Function() action) async {
    if (_busy) return false;
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

/// Connects an already-open review tab, waits for the selected member, then
/// injects [message] at the PTY prompt.
///
/// [connectRequest] must be [ExistingSessionConnect] for the open session tab.
/// Must not call [ChatCubit.requestOpenSession] with `connectImmediately: true`
/// — that path is for landing create / automation only.
///
/// Returns `true` only after successful inject (caller may then clear compose).
/// On connect/ready/inject failure returns `false` so compose text is kept;
/// launch errors surface via existing tab `launchError`.
Future<bool> submitSessionHistoryReviewMessage({
  required String sessionId,
  required String memberId,
  required String message,
  required SessionConnectRequest connectRequest,
  required Future<void> Function(SessionConnectRequest request)
  connectWorkspaceSession,
  required Future<void> Function(
    String sessionId,
    String memberId, {
    bool directToPty,
  })
  ensureMemberInputReady,
  required Future<void> Function(
    String sessionId,
    String memberId,
    String text, {
    bool directToPty,
  })
  deliverUserCommandToMember,
  required Future<void> Function(String sessionId, String firstPrompt)
  applyFirstPromptTitle,
  Duration readyTimeout = const Duration(seconds: 120),
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return false;

  try {
    await connectWorkspaceSession(connectRequest);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage: connect failed',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }

  try {
    await ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: true,
    ).timeout(readyTimeout);
  } on TimeoutException {
    appLogger.w(
      'submitSessionHistoryReviewMessage: member not ready '
      'session=$sessionId member=$memberId',
    );
    return false;
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage: ready wait failed',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }

  try {
    await deliverUserCommandToMember(
      sessionId,
      memberId,
      trimmed,
      directToPty: true,
    );
    // Review inject bypasses FirstUserLineCapture (keyboard path only).
    await applyFirstPromptTitle(sessionId, trimmed);
    return true;
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}
