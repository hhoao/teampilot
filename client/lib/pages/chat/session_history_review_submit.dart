import 'dart:async';

import '../../cubits/chat/model/session_connect_request.dart';
import '../../utils/logger.dart';

/// Connects an already-open review tab, waits for the selected member, then
/// injects [message] at the PTY prompt.
///
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
