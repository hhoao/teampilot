import 'message.dart';

/// Plain-text export for action-bar Copy (assistant-ui Copy semantics).
///
/// Includes user/assistant prose and a compact tool summary; omits raw
/// tool args/results (those stay in the expandable tool UI).
String plainTextForCopy(AiMessage message) {
  final chunks = <String>[];
  for (final part in message.parts) {
    switch (part) {
      case AiTextPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) chunks.add(t);
      case AiReasoningPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) chunks.add(t);
      case AiToolCallPart(:final toolName):
        chunks.add('Used tool: $toolName');
    }
  }
  return chunks.join('\n\n');
}
