import 'package:ai_message_core/ai_message_core.dart';

/// Searchable plain-text projection of a session transcript, plus the start
/// offset of each message's block so a hit can be mapped back to a message.
class SessionTranscriptDoc {
  const SessionTranscriptDoc({required this.text, required this.messageStarts});

  final String text;
  final List<int> messageStarts;
}

/// Projects [messages] into one searchable plain-text document with a line per
/// role label / text / reasoning / tool call, so users can find sessions by
/// what was said or done — not just the title. Cheap: only string building,
/// no message enrichment or subagent attachment inflation.
///
/// `messageStarts[i]` maps 1:1 to `messages[i]` — the in-memory chat find
/// (`ChatTranscriptFindController`) relies on this alignment to turn a doc-text
/// offset back into a message index for jumping.
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
  return SessionTranscriptDoc(text: buffer.toString(), messageStarts: starts);
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

/// Hosts the pure transcript-search helpers shared by the in-memory chat find
/// ([ChatTranscriptFindController]) and the workspace search dialog's snippet
/// rendering. All statics are side-effect free over a [SessionTranscriptDoc].
class WorkspaceSessionContentIndex {
  WorkspaceSessionContentIndex._();

  /// First case-insensitive occurrence of [query] in [text], returning the
  /// start index into [text].
  ///
  /// Length-safe: `String.toLowerCase()` can change a string's length (e.g.
  /// `ß` → `ss`), so an index found on a lowercased copy misaligns against the
  /// original text. Matching on the original with a case-insensitive RegExp
  /// keeps the returned index valid for slicing.
  static int? caseInsensitiveIndexOf(String text, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final match = RegExp(
      RegExp.escape(q),
      caseSensitive: false,
    ).firstMatch(text);
    return match?.start;
  }

  /// Index into a transcript's message list that owns [offset] in its doc
  /// text — the largest `i` with `starts[i] <= offset`. Returns 0 when the
  /// offset precedes the first block.
  static int messageIndexAt(List<int> starts, int offset) {
    var index = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] > offset) break;
      index = i;
    }
    return index;
  }

  /// A short, single-line window around [start] in [text] (one hit snippet).
  static String snippetAround(
    String text,
    int start,
    int queryLength, {
    int lead = 48,
    int trail = 96,
  }) {
    final s = start - lead < 0 ? 0 : start - lead;
    final e = start + queryLength + trail > text.length
        ? text.length
        : start + queryLength + trail;
    return text.substring(s, e).replaceAll('\n', ' ').trim();
  }
}
