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
  final channel = await ports.resolveChannel();

  switch (channel) {
    case HistoryContinueChannel.pty:
      final pending = await ports.persistPending(text);
      final result = await ports.deliver(text);
      if (result.ok) {
        ports.onPtyDelivered();
      } else if (pending != null) {
        await ports.markFailed(pending);
      }
      return result;
    case HistoryContinueChannel.mailbox:
      final result = await ports.deliver(text);
      if (result.isMailbox) {
        ports.onMailboxQueued(
          OperatorMailboxQueuedEvent(
            sessionId: sessionId,
            memberId: memberId,
            mailId: result.mailId!,
            text: text,
          ),
        );
        await ports.refreshMailboxTimeline();
      }
      return result;
  }
}
