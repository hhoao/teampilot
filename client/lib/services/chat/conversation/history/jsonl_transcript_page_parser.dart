import 'package:ai_message_core/ai_message_core.dart';

import '../../../cli/registry/capabilities/ai_history_capability.dart';
import 'jsonl_decode_worker.dart';

final class JsonlTranscriptLine {
  const JsonlTranscriptLine({
    required this.offset,
    required this.bytes,
    this.decodedEvent,
  });

  final int offset;
  final List<int> bytes;

  /// Set only by [JsonlPageWorker] after decoding in its resident isolate.
  final Map<String, dynamic>? decodedEvent;
}

/// Assembles a decoded JSONL slice into the same page contract as the reader.
///
/// The append hook is injected so the worker can select the built-in adapter
/// semantics while tests can exercise the parser with a focused hook.
final class JsonlTranscriptPageParser {
  const JsonlTranscriptPageParser({
    required this.lineAppend,
    required this.fallbackPrefix,
  });

  final AiTranscriptLineAppend lineAppend;
  final String fallbackPrefix;

  AiHistoryPage? parse({
    required List<JsonlTranscriptLine> lines,
    required int limit,
    required String sourceToken,
    required bool rebuilt,
  }) {
    if (lines.isEmpty) {
      return AiHistoryPage(
        messages: const [],
        hasOlder: false,
        nextCursor: null,
        sourceToken: sourceToken,
        rebuilt: rebuilt,
      );
    }

    final events = [
      for (final line in lines)
        line.decodedEvent ?? decodeJsonlLinesSync([line.bytes]).single,
    ];
    final parsed = _parseFrom(events, 0);
    final prefixComplete = lines.first.offset == 0;
    // Suffix windows: orphan tool_result / fallback ids cannot be proven.
    // Byte-0 windows match adapter.parse, including compaction leftovers
    // whose tool_use was removed — those orphans must not force a second
    // full-file decode via the loader fallback.
    if ((!prefixComplete && parsed.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: parsed.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }
    // Ignore decoded noise and inspect the first event that the injected CLI
    // append semantics actually turns into a logical message. On a suffix
    // window, an assistant as the first consumed role may continue an omitted
    // fragment. On a byte-0 window, preamble lines (session_meta, etc.) make
    // the first message offset > 0 even when the transcript is complete.
    final firstConsumedIndex = parsed.firstConsumedIndex;
    if (!prefixComplete &&
        firstConsumedIndex != null &&
        parsed.firstConsumedRole == AiRole.assistant) {
      return null;
    }
    final rawStart = _rawStartIndex(
      parsed.messageCounts,
      parsed.messages.length,
      limit,
    );
    var contextStart = rawStart > 0 ? rawStart - 1 : rawStart;
    while (contextStart > 0) {
      final previousRole = parsed.consumedRoles[contextStart - 1];
      if (previousRole != null && previousRole != AiRole.assistant) break;
      contextStart--;
    }
    final contextual = _parseFrom(events, contextStart);
    if ((!prefixComplete && contextual.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: contextual.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }
    final plain = contextStart == rawStart
        ? contextual
        : _parseFrom(events, rawStart);
    if ((!prefixComplete && plain.unresolvedDependency) ||
        _unsafeFallback(
          fallbackUsed: plain.fallbackUsed,
          prefixComplete: prefixComplete,
        )) {
      return null;
    }

    final completeMessages = prefixComplete
        ? finalizeAiMessagesForHistory(List<AiMessage>.of(parsed.messages))
        : null;
    final contextualMessages = finalizeAiMessagesForHistory(
      contextual.messages,
    );
    final plainMessages = finalizeAiMessagesForHistory(plain.messages);
    final contextualWindow = contextualMessages.length > limit
        ? contextualMessages.sublist(contextualMessages.length - limit)
        : contextualMessages;
    final needsContext =
        contextStart != rawStart &&
        !_sameMessages(contextualWindow, plainMessages);
    // Prefer the byte-0 finalize when available so first-paint ids match the
    // complete index (mid-slice fallback sequences renumber from zero).
    final output = completeMessages != null
        ? (completeMessages.length > limit
              ? completeMessages.sublist(completeMessages.length - limit)
              : completeMessages)
        : (contextualMessages.length > limit
              ? contextualMessages.sublist(contextualMessages.length - limit)
              : contextualMessages);
    final cursorLineIndex = needsContext ? contextStart : rawStart;
    final cursorLine = lines[cursorLineIndex];
    final hasOlder = cursorLine.offset > 0;
    return AiHistoryPage(
      messages: output,
      hasOlder: hasOlder,
      nextCursor: hasOlder
          ? AiHistoryCursor(
              sourceToken: sourceToken,
              offset: cursorLine.offset,
              lineHash: lineHash(cursorLine.bytes),
            )
          : null,
      sourceToken: sourceToken,
      rebuilt: rebuilt,
      completeMessages: completeMessages,
    );
  }

  _ParsedLines _parseFrom(List<Map<String, dynamic>?> events, int start) {
    final messages = <AiMessage>[];
    final counts = <int>[];
    var fallbackSeq = 0;
    var fallbackUsed = false;
    var unresolvedDependency = false;
    int? firstConsumedIndex;
    AiRole? firstConsumedRole;
    final consumedRoles = <AiRole?>[];
    for (var i = start; i < events.length; i++) {
      final event = events[i];
      AiRole? consumedRole;
      if (event != null) {
        final before = fallbackSeq;
        final consumed = lineAppend(
          messages,
          event,
          fallbackId: () {
            fallbackUsed = true;
            return '$fallbackPrefix-${fallbackSeq++}';
          },
        );
        if (!consumed) fallbackSeq = before;
        if (consumed && firstConsumedIndex == null && messages.isNotEmpty) {
          firstConsumedIndex = i;
          firstConsumedRole = messages.last.role;
        }
        if (consumed && messages.isNotEmpty) consumedRole = messages.last.role;
        if (_containsToolResult(event) && !consumed) {
          unresolvedDependency = true;
        }
      }
      counts.add(messages.length);
      consumedRoles.add(consumedRole);
    }
    return _ParsedLines(
      messages: messages,
      messageCounts: counts,
      fallbackUsed: fallbackUsed,
      unresolvedDependency: unresolvedDependency,
      firstConsumedIndex: firstConsumedIndex,
      firstConsumedRole: firstConsumedRole,
      consumedRoles: consumedRoles,
    );
  }

  static bool _containsToolResult(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is Map && _contentContainsToolResult(message['content'])) {
      return true;
    }
    final payload = event['payload'];
    if (payload is Map) {
      final type = payload['type'];
      return type == 'function_call_output' ||
          type == 'custom_tool_call_output' ||
          type == 'tool_result';
    }
    return false;
  }

  static bool _contentContainsToolResult(Object? content) {
    if (content is! List) return false;
    for (final block in content) {
      if (block is Map && block['type'] == 'tool_result') return true;
    }
    return false;
  }

  static bool _unsafeFallback({
    required bool fallbackUsed,
    required bool prefixComplete,
  }) {
    if (!fallbackUsed) return false;
    // Byte-0 windows already own the full prefix. Mid-slice fallback ids are
    // provisional for pagination cursors; [AiHistoryPage.completeMessages]
    // carries the adapter-equivalent full finalize for the loader.
    if (prefixComplete) return false;
    return true;
  }

  int _rawStartIndex(List<int> counts, int messageCount, int limit) {
    if (messageCount <= limit) return 0;
    final target = messageCount - limit;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > target) return i;
    }
    return 0;
  }

  static int lineHash(List<int> line) {
    var hash = 0x811F9DC5;
    for (final byte in line) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static bool _sameMessages(List<AiMessage> a, List<AiMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.role != right.role ||
          left.status != right.status ||
          left.createdAt != right.createdAt ||
          left.parts.length != right.parts.length) {
        return false;
      }
      for (var j = 0; j < left.parts.length; j++) {
        if (!_samePart(left.parts[j], right.parts[j])) return false;
      }
    }
    return true;
  }

  static bool _samePart(AiMessagePart a, AiMessagePart b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a is AiTextPart && b is AiTextPart) return a.text == b.text;
    if (a is AiReasoningPart && b is AiReasoningPart) return a.text == b.text;
    if (a is AiToolCallPart && b is AiToolCallPart) {
      return a.toolCallId == b.toolCallId &&
          a.toolName == b.toolName &&
          a.argsText == b.argsText &&
          a.result.toString() == b.result.toString() &&
          a.status == b.status &&
          a.isError == b.isError;
    }
    return false;
  }
}

final class _ParsedLines {
  const _ParsedLines({
    required this.messages,
    required this.messageCounts,
    required this.fallbackUsed,
    required this.unresolvedDependency,
    required this.firstConsumedIndex,
    required this.firstConsumedRole,
    required this.consumedRoles,
  });

  final List<AiMessage> messages;
  final List<int> messageCounts;
  final bool fallbackUsed;
  final bool unresolvedDependency;
  final int? firstConsumedIndex;
  final AiRole? firstConsumedRole;
  final List<AiRole?> consumedRoles;
}
