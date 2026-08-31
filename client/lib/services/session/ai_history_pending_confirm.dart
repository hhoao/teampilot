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
/// - a non-pending user message with [AiMessage.createdAt] >= record.createdAt
///   minus [skew], or
/// - normalized plain text equal to the record text.
bool transcriptConfirmsPendingRecord({
  required FailedMessageRecord record,
  required List<AiMessage> messages,
  Duration skew = kPendingConfirmClockSkew,
}) {
  final target = normalizeAiHistoryPendingText(record.text);
  if (target.isEmpty) return false;
  final earliest = record.createdAt.subtract(skew);
  for (final message in messages) {
    if (message.role != AiRole.user) continue;
    if (message.id.startsWith('pending:')) continue;
    final created = message.createdAt;
    if (created != null && !created.isBefore(earliest)) return true;
    final text = normalizeAiHistoryPendingText(
      message.parts.whereType<AiTextPart>().map((p) => p.text).join(' '),
    );
    if (text.isNotEmpty && text == target) return true;
  }
  return false;
}
