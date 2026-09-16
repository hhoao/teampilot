import 'package:ai_message_core/ai_message_core.dart';
import 'package:meta/meta.dart';

/// Opaque position in a transcript snapshot.
///
/// Only the page reader that created a cursor may interpret its source token.
@immutable
final class AiHistoryCursor {
  const AiHistoryCursor({
    required this.sourceToken,
    required this.offset,
    required this.lineHash,
  });

  final String sourceToken;
  final int offset;
  final int lineHash;
}

/// A display page and the cursor needed to request the preceding page.
@immutable
final class AiHistoryPage {
  AiHistoryPage({
    required List<AiMessage> messages,
    required this.hasOlder,
    required this.nextCursor,
    required this.sourceToken,
    required this.rebuilt,
    List<AiMessage>? completeMessages,
  }) : messages = List<AiMessage>.unmodifiable(messages),
       completeMessages = completeMessages == null
           ? null
           : List<AiMessage>.unmodifiable(completeMessages) {
    if (hasOlder && nextCursor == null) {
      throw ArgumentError('hasOlder requires nextCursor');
    }
  }

  final List<AiMessage> messages;
  final bool hasOlder;
  final AiHistoryCursor? nextCursor;
  final String sourceToken;
  final bool rebuilt;

  /// Full finalized transcript when the reader scanned from byte 0.
  ///
  /// Lets the loader publish a complete index without decoding the same
  /// JSONL again after a paginated first-paint window.
  final List<AiMessage>? completeMessages;
}
