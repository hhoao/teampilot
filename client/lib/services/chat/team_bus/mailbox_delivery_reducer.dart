import 'mailbox_delivery.dart';

/// Inputs to [MailboxDeliveryReducer] (orthogonal to [BusEvent] / presence).
sealed class MailboxDeliveryEvent {
  const MailboxDeliveryEvent();
}

/// [MailArrived] produced a mail [DoorbellEffect] — owe PTY notify.
final class MailDeliveryScheduled extends MailboxDeliveryEvent {
  const MailDeliveryScheduled();
}

/// PTY inject / reengage wake is starting for unread mail.
final class MailDeliveryStarted extends MailboxDeliveryEvent {
  const MailDeliveryStarted();
}

/// Grid ACK: doorbell text submitted to prompt (not inbox consumed).
final class MailDeliverySubmitted extends MailboxDeliveryEvent {
  const MailDeliverySubmitted();
}

/// PTY automation failed; may retry until [maxAttempts].
final class MailDeliveryFailed extends MailboxDeliveryEvent {
  const MailDeliveryFailed(this.error);
  final MailboxDeliveryError error;
}

/// Shell disconnected mid-inject.
final class MailDeliveryAborted extends MailboxDeliveryEvent {
  const MailDeliveryAborted();
}

/// Inbox drained via MCP (`read_messages` / `receiveWork`).
final class MailConsumed extends MailboxDeliveryEvent {
  const MailConsumed();
}

/// Snapshot applied to [AgentNode] delivery fields.
final class MailboxDeliverySnapshot {
  const MailboxDeliverySnapshot({
    this.phase = MailboxDeliveryPhase.none,
    this.attempts = 0,
    this.lastError,
  });

  final MailboxDeliveryPhase phase;
  final int attempts;
  final MailboxDeliveryError? lastError;

  MailboxDeliverySnapshot copyWith({
    MailboxDeliveryPhase? phase,
    int? attempts,
    MailboxDeliveryError? lastError,
    bool clearLastError = false,
  }) {
    return MailboxDeliverySnapshot(
      phase: phase ?? this.phase,
      attempts: attempts ?? this.attempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Pure mail-notify state machine (see mailbox-delivery design spec).
abstract final class MailboxDeliveryReducer {
  MailboxDeliveryReducer._();

  static MailboxDeliverySnapshot reduce(
    MailboxDeliverySnapshot state,
    MailboxDeliveryEvent event, {
    required bool hasUnread,
    required int maxAttempts,
  }) {
    switch (event) {
      case MailConsumed():
        if (!hasUnread) {
          return const MailboxDeliverySnapshot();
        }
        return state.copyWith(
          phase: MailboxDeliveryPhase.pending,
          clearLastError: true,
        );

      case MailDeliveryScheduled():
        if (!hasUnread) return const MailboxDeliverySnapshot();
        if (state.phase == MailboxDeliveryPhase.failed) return state;
        return state.copyWith(
          phase: MailboxDeliveryPhase.pending,
          clearLastError: true,
        );

      case MailDeliveryStarted():
        // failed 非终态:重臂一轮新预算(attempts 归零),避免投递义务被耗尽后封死。
        final attempts = (state.phase == MailboxDeliveryPhase.failed)
            ? 0
            : state.attempts;
        final nextAttempts = attempts + 1;
        if (nextAttempts > maxAttempts) {
          return MailboxDeliverySnapshot(
            phase: MailboxDeliveryPhase.failed,
            attempts: nextAttempts,
            lastError: state.lastError ?? MailboxDeliveryError.crStuck,
          );
        }
        return state.copyWith(
          phase: MailboxDeliveryPhase.inFlight,
          attempts: nextAttempts,
        );

      case MailDeliverySubmitted():
        if (!hasUnread) return const MailboxDeliverySnapshot();
        return state.copyWith(phase: MailboxDeliveryPhase.pending);

      case MailDeliveryFailed(:final error):
        // 只回报结果,不叠加次数(次数由 Started 计),避免一次尝试双计快速耗竭预算。
        if (state.attempts >= maxAttempts) {
          return MailboxDeliverySnapshot(
            phase: MailboxDeliveryPhase.failed,
            attempts: state.attempts,
            lastError: error,
          );
        }
        return MailboxDeliverySnapshot(
          phase: MailboxDeliveryPhase.pending,
          attempts: state.attempts,
          lastError: error,
        );

      case MailDeliveryAborted():
        if (!hasUnread) return const MailboxDeliverySnapshot();
        return state.copyWith(phase: MailboxDeliveryPhase.pending);
    }
  }
}
