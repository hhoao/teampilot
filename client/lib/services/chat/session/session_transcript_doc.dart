import 'dart:typed_data';

import 'package:ai_message_core/ai_message_core.dart';

/// Searchable plain-text projection of a session transcript, plus the start
/// offset of each message's block so a hit can be mapped back to a message.
class SessionTranscriptDoc {
  const SessionTranscriptDoc({
    required this.text,
    required this.messageStarts,
    required this.folded,
  });

  final String text;
  final List<int> messageStarts;

  /// [text] with ASCII (and same-length non-ASCII) letters lowercased, so a
  /// query is a plain `indexOf` instead of a case-insensitive regex scan on
  /// every keystroke. Always the same length as [text], so offsets found here
  /// are valid in [text] too.
  final String folded;
}

/// Projects [messages] into one searchable plain-text document with a line per
/// role label / text / reasoning / tool call, so users can find sessions by
/// what was said or done — not just the title. Cheap: only string building,
/// no message enrichment or subagent attachment inflation.
SessionTranscriptDoc buildTranscriptDoc(List<AiMessage> messages) {
  final buffer = StringBuffer();
  final starts = <int>[];
  for (final message in messages) {
    starts.add(buffer.length);
    buffer.write(_roleLabel(message.role));
    buffer.write(': ');
    for (final part in message.parts) {
      if (part is AiTextPart) {
        buffer.writeln(part.text);
      } else if (part is AiReasoningPart) {
        buffer.writeln('[thought] ${part.text}');
      } else if (part is AiToolCallPart) {
        buffer.writeln(
          '[tool] ${part.toolName}${_toolArgsSuffix(part.argsText)}',
        );
      }
    }
    buffer.writeln();
  }
  final text = buffer.toString();
  return SessionTranscriptDoc(
    text: text,
    messageStarts: starts,
    folded: foldCasePreservingLength(text),
  );
}

/// Lowercases [text] **without changing its length**, so an offset found in the
/// result is also valid in the original (a plain `toLowerCase()` can expand
/// `ß` → `ss` and shift every later offset). Only ASCII is folded for speed;
/// non-ASCII code units are folded when the lowercase form is still a single
/// code unit, and kept as-is otherwise.
String foldCasePreservingLength(String text) {
  final units = Uint16List(text.length);
  var changed = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    var folded = unit;
    if (unit >= 0x41 && unit <= 0x5A) {
      folded = unit + 0x20;
    } else if (unit > 0x7F && unit < 0xD800) {
      final lower = String.fromCharCode(unit).toLowerCase();
      if (lower.length == 1) folded = lower.codeUnitAt(0);
    }
    if (folded != unit) changed = true;
    units[i] = folded;
  }
  return changed ? String.fromCharCodes(units) : text;
}

String _roleLabel(AiRole role) => switch (role) {
  AiRole.user => 'user',
  AiRole.assistant => 'assistant',
  AiRole.system => 'system',
};

String _toolArgsSuffix(String? argsText) {
  final args = argsText?.trim() ?? '';
  if (args.isEmpty) return '';
  final inline = args.replaceAll(RegExp(r'\s+'), ' ');
  final max = 160;
  return inline.length <= max ? ' $inline' : ' ${inline.substring(0, max)}…';
}
