import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mailbox_delivery.dart';
import 'package:teampilot/services/team_bus/mailbox_delivery_reducer.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

void main() {
  group('MailboxDeliveryReducer', () {
    test('MailDeliveryScheduled with unread → pending', () {
      const state = MailboxDeliverySnapshot();
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliveryScheduled(),
        hasUnread: true,
        maxAttempts: TeamBus.maxPtyNotifyAttempts,
      );
      expect(next.phase, MailboxDeliveryPhase.pending);
    });

    test('MailDeliveryStarted increments attempts and → inFlight', () {
      const state = MailboxDeliverySnapshot(phase: MailboxDeliveryPhase.pending);
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliveryStarted(),
        hasUnread: true,
        maxAttempts: 6,
      );
      expect(next.phase, MailboxDeliveryPhase.inFlight);
      expect(next.attempts, 1);
    });

    test('MailDeliveryFailed at budget → failed (attempts not double-counted)', () {
      const state = MailboxDeliverySnapshot(
        phase: MailboxDeliveryPhase.inFlight,
        attempts: 6,
      );
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliveryFailed(MailboxDeliveryError.crStuck),
        hasUnread: true,
        maxAttempts: 6,
      );
      expect(next.phase, MailboxDeliveryPhase.failed);
      expect(next.attempts, 6); // 次数由 Started 计,Failed 不叠加
      expect(next.lastError, MailboxDeliveryError.crStuck);
    });

    test('MailDeliveryFailed does not double-count attempts', () {
      const state = MailboxDeliverySnapshot(
        phase: MailboxDeliveryPhase.inFlight,
        attempts: 3,
      );
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliveryFailed(MailboxDeliveryError.pasteNotFound),
        hasUnread: true,
        maxAttempts: 6,
      );
      expect(next.attempts, 3); // 不再 +1
      expect(next.phase, MailboxDeliveryPhase.pending);
    });

    test('MailDeliveryStarted on failed phase re-arms a fresh budget', () {
      const state = MailboxDeliverySnapshot(
        phase: MailboxDeliveryPhase.failed,
        attempts: 6,
      );
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliveryStarted(),
        hasUnread: true,
        maxAttempts: 6,
      );
      expect(next.phase, MailboxDeliveryPhase.inFlight);
      expect(next.attempts, 1); // 重置后第一轮
    });

    test('MailDeliverySubmitted with unread → pending', () {
      const state = MailboxDeliverySnapshot(phase: MailboxDeliveryPhase.inFlight);
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailDeliverySubmitted(),
        hasUnread: true,
        maxAttempts: 6,
      );
      expect(next.phase, MailboxDeliveryPhase.pending);
    });

    test('MailConsumed when inbox empty → none', () {
      const state = MailboxDeliverySnapshot(
        phase: MailboxDeliveryPhase.pending,
        attempts: 2,
        lastError: MailboxDeliveryError.crStuck,
      );
      final next = MailboxDeliveryReducer.reduce(
        state,
        const MailConsumed(),
        hasUnread: false,
        maxAttempts: 6,
      );
      expect(next.phase, MailboxDeliveryPhase.none);
      expect(next.attempts, 0);
      expect(next.lastError, isNull);
    });
  });
}
