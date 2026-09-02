import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/operator_history_send.dart';

void main() {
  test('PTY persists before deliver and notifies on success', () async {
    final calls = <String>[];
    FailedMessageRecord? persisted;
    final result = await runOperatorHistorySend(
      sessionId: 's1',
      memberId: 'm1',
      text: 'hello',
      ports: (
        resolveChannel: () async => HistoryContinueChannel.pty,
        persistPending: (t) async {
          calls.add('persist:$t');
          persisted = FailedMessageRecord(
            id: 'pending:1',
            text: t,
            createdAt: DateTime.utc(2026),
            status: FailedMessageStatus.sending,
          );
          return persisted;
        },
        markFailed: (_) async => calls.add('markFailed'),
        clearPending: (_) async => calls.add('clearPending'),
        deliver: (t) async {
          calls.add('deliver:$t');
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        },
        onPtyDelivered: () => calls.add('ptyDelivered'),
        onMailboxQueued: (_) => calls.add('mailboxQueued'),
        refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
      ),
    );
    expect(result.ok, isTrue);
    expect(calls, ['persist:hello', 'deliver:hello', 'ptyDelivered']);
  });

  test('PTY failure marks pending failed', () async {
    final calls = <String>[];
    await runOperatorHistorySend(
      sessionId: 's1',
      memberId: 'm1',
      text: 'x',
      ports: (
        resolveChannel: () async => HistoryContinueChannel.pty,
        persistPending: (t) async => FailedMessageRecord(
          id: 'pending:1',
          text: t,
          createdAt: DateTime.utc(2026),
          status: FailedMessageStatus.sending,
        ),
        markFailed: (r) async => calls.add('markFailed:${r.id}'),
        clearPending: (_) async => calls.add('clearPending'),
        deliver: (_) async => const HistoryContinueSubmitResult.failed(),
        onPtyDelivered: () => calls.add('ptyDelivered'),
        onMailboxQueued: (_) {},
        refreshMailboxTimeline: () async {},
      ),
    );
    expect(calls, ['markFailed:pending:1']);
  });

  test(
    'mailbox success emits queued event and refreshes; no persist',
    () async {
      final calls = <String>[];
      OperatorMailboxQueuedEvent? queued;
      await runOperatorHistorySend(
        sessionId: 's1',
        memberId: 'm1',
        text: 'mail me',
        ports: (
          resolveChannel: () async => HistoryContinueChannel.mailbox,
          persistPending: (_) async {
            calls.add('persist');
            return null;
          },
          markFailed: (_) async => calls.add('markFailed'),
          clearPending: (_) async => calls.add('clearPending'),
          deliver: (_) async => const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.mailbox,
            mailId: 'mail-9',
          ),
          onPtyDelivered: () => calls.add('ptyDelivered'),
          onMailboxQueued: (e) {
            queued = e;
            calls.add('mailboxQueued');
          },
          refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
        ),
      );
      expect(calls, ['mailboxQueued', 'refreshMailbox']);
      expect(queued?.mailId, 'mail-9');
      expect(queued?.text, 'mail me');
    },
  );

  test(
    'PTY peek switching to mailbox clears pending and uses mailbox UX',
    () async {
      final calls = <String>[];
      await runOperatorHistorySend(
        sessionId: 's1',
        memberId: 'm1',
        text: 'flipped mail',
        ports: (
          resolveChannel: () async => HistoryContinueChannel.pty,
          persistPending: (text) async {
            calls.add('persist:$text');
            return FailedMessageRecord(
              id: 'pending:flip',
              text: text,
              createdAt: DateTime.utc(2026),
              status: FailedMessageStatus.sending,
            );
          },
          markFailed: (_) async => calls.add('markFailed'),
          clearPending: (record) async => calls.add('clear:${record.id}'),
          deliver: (_) async {
            calls.add('deliver');
            return const HistoryContinueSubmitResult(
              ok: true,
              channel: HistoryContinueChannel.mailbox,
              mailId: 'mail-flip',
            );
          },
          onPtyDelivered: () => calls.add('ptyDelivered'),
          onMailboxQueued: (_) => calls.add('mailboxQueued'),
          refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
        ),
      );

      expect(calls, [
        'persist:flipped mail',
        'deliver',
        'clear:pending:flip',
        'mailboxQueued',
        'refreshMailbox',
      ]);
    },
  );

  test(
    'mailbox peek switching to PTY persists after delivery and stales',
    () async {
      final calls = <String>[];
      await runOperatorHistorySend(
        sessionId: 's1',
        memberId: 'm1',
        text: 'flipped pty',
        ports: (
          resolveChannel: () async => HistoryContinueChannel.mailbox,
          persistPending: (text) async {
            calls.add('persist:$text');
            return FailedMessageRecord(
              id: 'pending:flip',
              text: text,
              createdAt: DateTime.utc(2026),
              status: FailedMessageStatus.sending,
            );
          },
          markFailed: (_) async => calls.add('markFailed'),
          clearPending: (_) async => calls.add('clearPending'),
          deliver: (_) async {
            calls.add('deliver');
            return const HistoryContinueSubmitResult(
              ok: true,
              channel: HistoryContinueChannel.pty,
            );
          },
          onPtyDelivered: () => calls.add('ptyDelivered'),
          onMailboxQueued: (_) => calls.add('mailboxQueued'),
          refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
        ),
      );

      expect(calls, ['deliver', 'persist:flipped pty', 'ptyDelivered']);
    },
  );
}
