import 'package:ai_message_core/ai_message_core.dart';

/// Appends [part] onto [out] in place.
///
/// Tool calls start a new segment. Within a segment, a text (reasoning)
/// part concatenates onto the last text (reasoning) part, skipping the
/// other channel; if none exists yet in the segment, [part] is appended.
void appendAcpStreamChannelPart(
  List<AiMessagePart> out,
  AiMessagePart part,
) {
  switch (part) {
    case AiToolCallPart():
      out.add(part);
    case AiTextPart(:final text):
      for (var i = out.length - 1; i >= 0; i--) {
        final current = out[i];
        if (current is AiToolCallPart) break;
        if (current is AiTextPart) {
          out[i] = AiTextPart(text: '${current.text}$text');
          return;
        }
      }
      out.add(part);
    case AiReasoningPart(:final text):
      for (var i = out.length - 1; i >= 0; i--) {
        final current = out[i];
        if (current is AiToolCallPart) break;
        if (current is AiReasoningPart) {
          out[i] = AiReasoningPart(text: '${current.text}$text');
          return;
        }
      }
      out.add(part);
  }
}

/// Folds [parts] from an empty list through [appendAcpStreamChannelPart].
List<AiMessagePart> foldAcpStreamChannelParts(Iterable<AiMessagePart> parts) {
  final out = <AiMessagePart>[];
  for (final part in parts) {
    appendAcpStreamChannelPart(out, part);
  }
  return out;
}
