import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';

final class OperatorMailboxQueuedEvent {
  const OperatorMailboxQueuedEvent({
    required this.sessionId,
    required this.memberId,
    required this.mailId,
    required this.text,
  });
  final String sessionId;
  final String memberId;
  final String mailId;
  final String text;
}

typedef OperatorHistorySendPorts = ({
  Future<HistoryContinueChannel> Function() resolveChannel,
  Future<FailedMessageRecord?> Function(String text) persistPending,
  Future<void> Function(FailedMessageRecord record) markFailed,
  Future<void> Function(FailedMessageRecord record) clearPending,
  Future<HistoryContinueSubmitResult> Function(String text) deliver,
  void Function() onPtyDelivered,
  void Function(OperatorMailboxQueuedEvent event) onMailboxQueued,
  Future<void> Function() refreshMailboxTimeline,
});

Future<HistoryContinueSubmitResult> runOperatorHistorySend({
  required String sessionId,
  required String memberId,
  required String text,
  required OperatorHistorySendPorts ports,
}) async {
  final peekedChannel = await ports.resolveChannel();
  FailedMessageRecord? pending;
  if (peekedChannel == HistoryContinueChannel.pty) {
    pending = await ports.persistPending(text);
  }

  final result = await ports.deliver(text);
  if (!result.ok) {
    if (pending != null) {
      await ports.markFailed(pending);
    }
    return result;
  }

  switch (result.channel) {
    case HistoryContinueChannel.mailbox:
      if (!result.isMailbox) return result;
      if (pending != null) {
        await ports.clearPending(pending);
      }
      ports.onMailboxQueued(
        OperatorMailboxQueuedEvent(
          sessionId: sessionId,
          memberId: memberId,
          mailId: result.mailId!,
          text: text,
        ),
      );
      await ports.refreshMailboxTimeline();
      break;
    case HistoryContinueChannel.pty:
      pending ??= await ports.persistPending(text);
      ports.onPtyDelivered();
      break;
  }
  return result;
}
