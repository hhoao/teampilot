import 'fullscreen_cr_ack_config.dart';
import '../../utils/logger.dart';
import '../team_bus/team_bus.dart';
import 'fullscreen_pty_automation.dart';
import 'pty_automation_retry_queue.dart';
import 'pty_automation_session_lock.dart';
import 'terminal_fullscreen_pty_port.dart';
import 'terminal_session.dart';

/// Session-scoped full-screen PTY inject with lock + idle-watch retry queue.
final class MemberPtyInjectService {
  MemberPtyInjectService({
    FullscreenPtyAutomation? automation,
    PtyAutomationSessionLock? lock,
    PtyAutomationRetryQueue? retryQueue,
    this.onDeliveryRetryExhausted,
  }) : _automation = automation ?? FullscreenPtyAutomation(),
       _lock = lock ?? PtyAutomationSessionLock(),
       _retryQueue =
           retryQueue ??
           PtyAutomationRetryQueue(
             retryIntervalMs: TeamBus.doorbellRetryMs,
             maxAttempts: TeamBus.maxPtyNotifyAttempts,
           );

  static const maxPtyNotifyAttempts = TeamBus.maxPtyNotifyAttempts;

  final FullscreenPtyAutomation _automation;
  final PtyAutomationSessionLock _lock;
  final PtyAutomationRetryQueue _retryQueue;
  final void Function(
    String sessionId,
    String memberId,
    FullscreenPtyDeliveryOutcome outcome,
  )?
  onDeliveryRetryExhausted;

  bool isBusy(String sessionId, String memberId) =>
      _lock.isBusy(sessionId, memberId);

  bool hasPendingRetry(String sessionId, String memberId) =>
      _retryQueue.isPending(PtyAutomationSessionLock.key(sessionId, memberId));

  void clearPending(String sessionId, String memberId) {
    _retryQueue.clear(PtyAutomationSessionLock.key(sessionId, memberId));
  }

  /// First delivery: clear → paste → grid ACK → CR.
  Future<FullscreenPtyDeliveryOutcome> deliver({
    required TerminalSession shell,
    required String sessionId,
    required String memberId,
    required String text,
    required Duration pasteSettle,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
  }) {
    return _runLocked(
      shell: shell,
      sessionId: sessionId,
      memberId: memberId,
      text: text,
      aborted: aborted,
      crAckConfig: crAckConfig,
      run: (port) => _automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: pasteSettle,
      ),
    );
  }

  /// Screen-gated retry: visible → CR; missing → full deliver.
  Future<FullscreenPtyDeliveryOutcome> retry({
    required TerminalSession shell,
    required String sessionId,
    required String memberId,
    required String text,
    required Duration pasteSettle,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
  }) {
    return _runLocked(
      shell: shell,
      sessionId: sessionId,
      memberId: memberId,
      text: text,
      aborted: aborted,
      crAckConfig: crAckConfig,
      run: (port) => _automation.retry(
        port: port,
        text: text,
        pasteSettle: pasteSettle,
      ),
    );
  }

  void tickRetries({
    required void Function(PtyAutomationRetryTick tick) onTick,
    bool Function(PtyAutomationRetryTick tick)? shouldSkip,
  }) {
    final due = _retryQueue.due(
      blocked: (key) {
        final sep = key.indexOf(':');
        if (sep <= 0) return true;
        return _lock.isBusy(key.substring(0, sep), key.substring(sep + 1));
      },
    );
    for (final tick in due) {
      if (shouldSkip?.call(tick) ?? false) {
        _retryQueue.clear(tick.key);
        continue;
      }
      appLogger.d(
        '[team-bus] automation-retry-tick member=${tick.memberId} '
        'session=${tick.sessionId} attempt=${tick.attempt}',
      );
      onTick(tick);
    }
  }

  Future<FullscreenPtyDeliveryOutcome> _runLocked({
    required TerminalSession shell,
    required String sessionId,
    required String memberId,
    required String text,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
    required Future<FullscreenPtyDeliveryOutcome> Function(
      TerminalFullscreenPtyPort port,
    )
    run,
  }) async {
    final key = PtyAutomationSessionLock.key(sessionId, memberId);
    if (!_lock.tryAcquire(sessionId, memberId)) {
      appLogger.d(
        '[team-bus] pty-automation deferred ack-in-progress '
        'member=$memberId session=$sessionId',
      );
      _scheduleRetry(key, sessionId, memberId, text, FullscreenPtyDeliveryOutcome.crStuck);
      return FullscreenPtyDeliveryOutcome.crStuck;
    }
    try {
      final port = TerminalFullscreenPtyPort(
        shell,
        aborted: aborted,
        crAckConfig: crAckConfig,
      );
      final outcome = await run(port);
      _handleOutcome(key, sessionId, memberId, text, outcome);
      return outcome;
    } finally {
      _lock.release(sessionId, memberId);
    }
  }

  void _handleOutcome(
    String key,
    String sessionId,
    String memberId,
    String text,
    FullscreenPtyDeliveryOutcome outcome,
  ) {
    switch (outcome) {
      case FullscreenPtyDeliveryOutcome.submitted:
        _retryQueue.clear(key);
      case FullscreenPtyDeliveryOutcome.aborted:
        break;
      case FullscreenPtyDeliveryOutcome.pasteNotFound:
      case FullscreenPtyDeliveryOutcome.crStuck:
        appLogger.w(
          '[team-bus] pty-automation-failed member=$memberId session=$sessionId '
          'outcome=$outcome',
        );
        _scheduleRetry(key, sessionId, memberId, text, outcome);
    }
  }

  void _scheduleRetry(
    String key,
    String sessionId,
    String memberId,
    String text,
    FullscreenPtyDeliveryOutcome outcome,
  ) {
    final scheduled = _retryQueue.schedule(
      key: key,
      sessionId: sessionId,
      memberId: memberId,
      text: text,
    );
    if (scheduled) {
      appLogger.d(
        '[team-bus] automation-retry-scheduled member=$memberId '
        'session=$sessionId',
      );
    } else {
      appLogger.w(
        '[team-bus] automation-retry-gave-up member=$memberId '
        'session=$sessionId',
      );
      onDeliveryRetryExhausted?.call(sessionId, memberId, outcome);
    }
  }
}
