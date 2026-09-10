import '../../cubits/chat/member_input_ready_wait.dart';
import '../../cubits/chat/model/session_connect_request.dart';
import '../../utils/logging/logger.dart';
import 'history_continue_delivery.dart';

/// Preference gate: when false (default), Chat submit stays on Chat.
bool shouldSwitchToTerminalAfterChatSubmit(bool chatSubmitSwitchesToTerminal) =>
    chatSubmitSwitchesToTerminal;

/// Re-entrancy lock for History continue while connect/inject is in flight.
///
/// History stays mounted during submit, so compose can fire twice before the
/// first await returns; callers must gate UI on [isBusy] as well.
final class HistoryContinueSubmitLock {
  var _busy = false;

  bool get isBusy => _busy;

  /// Runs [action] once; overlapping calls return a failed result.
  Future<HistoryContinueSubmitResult> run(
    Future<HistoryContinueSubmitResult> Function() action,
  ) async {
    if (_busy) return const HistoryContinueSubmitResult.failed();
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

/// Connects an already-open review tab, then delivers [message] on [channel].
///
/// [connectRequest] must be [ExistingSessionConnect] for the open session tab.
/// Must not call [ChatCubit.requestOpenSession] with `connectImmediately: true`
/// — that path is for landing create / automation only.
///
/// PTY: waits for member ready, injects at the prompt, applies first-prompt
/// title. Mailbox: skips ready-wait and returns the TeamBus mail id.
///
/// On connect/ready/inject failure returns [HistoryContinueSubmitResult.failed]
/// so compose text is kept; launch errors surface via existing tab
/// `launchError`.
Future<HistoryContinueSubmitResult> submitSessionHistoryReviewMessage({
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
    bool Function()? aborted,
  })
  ensureMemberInputReady,
  required Future<String?> Function(
    String sessionId,
    String memberId,
    String text, {
    bool directToPty,
  })
  deliverUserCommandToMember,
  required Future<void> Function(String sessionId, String firstPrompt)
  applyFirstPromptTitle,
  HistoryContinueChannel channel = HistoryContinueChannel.pty,

  /// When set, called after connect so a newly installed TeamBus is visible.
  HistoryContinueChannel Function()? resolveChannel,

  /// Flips true when the operator pressed compose Stop after this send began.
  /// The message is then never delivered — a stopped launch must not feed the
  /// CLI its queued prompt once the terminal finally becomes ready.
  bool Function()? cancelled,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return HistoryContinueSubmitResult.failed(channel: channel);
  }

  try {
    await connectWorkspaceSession(connectRequest);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage: connect failed',
      error: error,
      stackTrace: stackTrace,
    );
    return HistoryContinueSubmitResult.failed(channel: channel);
  }

  if (cancelled?.call() ?? false) {
    appLogger.d(
      'submitSessionHistoryReviewMessage: cancelled by operator stop '
      'after connect session=$sessionId member=$memberId',
    );
    return HistoryContinueSubmitResult.failed(channel: channel);
  }

  // Prefer post-connect resolution so a freshly installed TeamBus is visible.
  final effectiveChannel = resolveChannel?.call() ?? channel;

  if (effectiveChannel == HistoryContinueChannel.mailbox) {
    if (cancelled?.call() ?? false) {
      appLogger.d(
        'submitSessionHistoryReviewMessage: cancelled by operator stop '
        'before mailbox deliver session=$sessionId member=$memberId',
      );
      return const HistoryContinueSubmitResult.failed(
        channel: HistoryContinueChannel.mailbox,
      );
    }
    try {
      final mailId = await deliverUserCommandToMember(
        sessionId,
        memberId,
        trimmed,
        directToPty: false,
      );
      final id = mailId?.trim() ?? '';
      if (id.isEmpty) {
        appLogger.w(
          'submitSessionHistoryReviewMessage: mailbox deliver missing id '
          'session=$sessionId member=$memberId',
        );
        return const HistoryContinueSubmitResult.failed(
          channel: HistoryContinueChannel.mailbox,
        );
      }
      return HistoryContinueSubmitResult(
        ok: true,
        channel: HistoryContinueChannel.mailbox,
        mailId: id,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        'submitSessionHistoryReviewMessage: mailbox deliver failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const HistoryContinueSubmitResult.failed(
        channel: HistoryContinueChannel.mailbox,
      );
    }
  }

  try {
    await ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: true,
      aborted: () => cancelled?.call() ?? false,
    );
  } on MemberInputReadyException catch (error) {
    appLogger.w(
      'submitSessionHistoryReviewMessage: '
      '${error.failure == MemberInputReadyFailure.timedOut ? 'composer wait cap' : 'composer wait dead'} '
      'session=$sessionId member=$memberId',
    );
    return const HistoryContinueSubmitResult.failed();
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage: ready wait failed',
      error: error,
      stackTrace: stackTrace,
    );
    return const HistoryContinueSubmitResult.failed();
  }

  if (cancelled?.call() ?? false) {
    appLogger.d(
      'submitSessionHistoryReviewMessage: cancelled by operator stop '
      'before terminal deliver session=$sessionId member=$memberId',
    );
    return const HistoryContinueSubmitResult.failed();
  }

  try {
    final deliveryId = await deliverUserCommandToMember(
      sessionId,
      memberId,
      trimmed,
      directToPty: true,
    );
    if (deliveryId == null || deliveryId.trim().isEmpty) {
      appLogger.w(
        'submitSessionHistoryReviewMessage: terminal submit unconfirmed '
        'session=$sessionId member=$memberId',
      );
      return const HistoryContinueSubmitResult.failed();
    }
    // Review inject bypasses FirstUserLineCapture (keyboard path only).
    await applyFirstPromptTitle(sessionId, trimmed);
    return const HistoryContinueSubmitResult(
      ok: true,
      channel: HistoryContinueChannel.pty,
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitSessionHistoryReviewMessage',
      error: error,
      stackTrace: stackTrace,
    );
    return const HistoryContinueSubmitResult.failed();
  }
}
