import 'package:ai_message_core/ai_message_core.dart';

import '../../models/failed_message_record.dart';
import 'ai_history_pending_text.dart';

/// Clock skew allowed when matching [FailedMessageRecord.createdAt] to a CLI
/// user turn's [AiMessage.createdAt] during hydrate confirm.
const Duration kPendingConfirmClockSkew = Duration(seconds: 2);

/// Whether a loaded transcript already reflects [record] so hydrate should
/// drop it (silent success) instead of restoring a failed overlay.
///
/// Either signal confirms:
/// - normalized plain text of some loaded user message **contains** the record
///   text (the primary signal; covers missing CLI timestamps and CLI rewrites
///   that append context around the typed prompt), or
/// - the newest user turn sits at/after `record.createdAt - skew` and no user
///   turn with different text opened a **later** send window. A later
///   unrelated send (B after a failed A) must not confirm-and-delete A.
bool transcriptConfirmsPendingRecord({
  required FailedMessageRecord record,
  required List<AiMessage> messages,
  Duration skew = kPendingConfirmClockSkew,
}) {
  final target = normalizeAiHistoryPendingText(record.text);
  if (target.isEmpty) return false;
  final earliest = record.createdAt.subtract(skew);

  var sawUserTurnAtOrAfterRecord = false;
  var sawLaterDifferentSend = false;
  for (final message in messages) {
    if (message.role != AiRole.user) continue;
    if (message.id.startsWith('pending:')) continue;
    final text = normalizeAiHistoryPendingText(
      message.parts.whereType<AiTextPart>().map((p) => p.text).join(' '),
    );
    if (text.contains(target)) return true;
    final created = message.createdAt;
    if (created == null) continue;
    if (!created.isBefore(earliest)) sawUserTurnAtOrAfterRecord = true;
    // A turn landing after the record's window with text that does not cover
    // the record is evidence of a *newer* send — its window starts after the
    // record's, so it cannot be the confirmation of this one.
    if (created.isAfter(record.createdAt) &&
        text.isNotEmpty &&
        !text.contains(target)) {
      sawLaterDifferentSend = true;
    }
  }
  return sawUserTurnAtOrAfterRecord && !sawLaterDifferentSend;
}
