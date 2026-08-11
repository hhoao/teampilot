import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

Map<String, dynamic>? tryDecodeJsonlLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// Appends/merges one decoded event into [messages]. Returns false for noise
/// records that carry no display content. Streamed assistant partials sharing
/// a logical `message.id` merge into the previous message. Used by both the
/// full parser and the incremental tailer.
bool appendClaudeJsonlEvent(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}) {
  // Claude/flashskyai put the speaker on the top-level `type` field; Cursor
  // agent-transcripts use a top-level `role` field with the same values.
  final type = event['type'] ?? event['role'];
  if (type != 'user' && type != 'assistant') return false;

  final message = event['message'];
  if (message is! Map) return false;
  final messageMap = Map<String, dynamic>.from(message);
  final content = messageMap['content'];
  final timestamp = _parseTimestamp(event['timestamp']);

  // Lazily compute the logical message id so an event that ends up discarded
  // (empty text / tool_result-only batch) never consumes a fallback id:
  // the incremental tailer's fallback seq must advance exactly like the full
  // parse's, otherwise message ids flip between incremental and rebuild.
  String? memoId;
  String id() => memoId ??= _logicalMessageId(event, fallbackId);

  if (content is String) {
    final text = content.trim();
    if (text.isEmpty) return false;
    _addOrMerge(
      messages,
      AiMessage(
        id: id(),
        role: type == 'user' ? AiRole.user : AiRole.assistant,
        parts: [AiTextPart(text: text)],
        createdAt: timestamp,
      ),
    );
    return true;
  }

  if (content is! List) return false;

  final textParts = <AiMessagePart>[];
  final toolParts = <AiToolCallPart>[];
  final toolResults = <({String toolUseId, Object? result, bool isError})>[];

  for (final block in content) {
    if (block is! Map) continue;
    final blockMap = Map<String, dynamic>.from(block);
    switch (blockMap['type']) {
      case 'text':
        final text = '${blockMap['text'] ?? ''}'.trim();
        if (text.isNotEmpty) {
          textParts.add(AiTextPart(text: text));
        }
      case 'thinking':
        final thinking = '${blockMap['thinking'] ?? ''}'.trim();
        if (thinking.isNotEmpty) {
          textParts.add(AiReasoningPart(text: thinking));
        }
      case 'tool_use':
        final toolCallId = '${blockMap['id'] ?? ''}'.trim();
        if (toolCallId.isEmpty) continue;
        final name = '${blockMap['name'] ?? 'tool'}';
        toolParts.add(
          AiToolCallPart(
            toolCallId: toolCallId,
            toolName: name,
            args: _asArgs(blockMap['input']),
          ),
        );
      case 'tool_result':
        final toolUseId = blockMap['tool_use_id'];
        if (toolUseId is! String || toolUseId.isEmpty) continue;
        toolResults.add((
          toolUseId: toolUseId,
          result: _toolResultValue(blockMap['content']),
          isError: blockMap['is_error'] == true,
        ));
      default:
        continue;
    }
  }

  var appliedAny = false;
  for (final result in toolResults) {
    appliedAny = _applyToolResult(
          messages,
          toolUseId: result.toolUseId,
          result: result.result,
          isError: result.isError,
        ) ||
        appliedAny;
  }

  final parts = <AiMessagePart>[
    ...textParts,
    if (type == 'assistant') ...toolParts,
  ];
  if (parts.isEmpty) return appliedAny;

  _addOrMerge(
    messages,
    AiMessage(
      id: id(),
      role: type == 'user' ? AiRole.user : AiRole.assistant,
      parts: parts,
      createdAt: timestamp,
    ),
  );
  return true;
}

/// Shared Claude Code / flashskyai JSONL → [AiMessage] parser.
///
/// Real transcripts stream one logical assistant turn across multiple lines that
/// share [message.id] (different event `uuid`s). We merge those into one
/// [AiMessage]. `thinking` blocks become [AiReasoningPart].
List<AiMessage> parseClaudeCompatibleJsonl(
  String content, {
  required String Function() fallbackId,
}) {
  final messages = <AiMessage>[];
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final event = tryDecodeJsonlLine(trimmed);
    if (event == null) continue;
    appendClaudeJsonlEvent(messages, event, fallbackId: fallbackId);
  }
  return finalizeAiMessagesForHistory(messages);
}

/// Prefer Claude/flashskyai `message.id` so streamed partial lines coalesce.
String _logicalMessageId(
  Map<String, dynamic> event,
  String Function() fallbackId,
) {
  final message = event['message'];
  if (message is Map) {
    final mid = message['id'];
    if (mid is String && mid.isNotEmpty) return mid;
  }
  final uuid = event['uuid'];
  if (uuid is String && uuid.isNotEmpty) return uuid;
  return fallbackId();
}

void _addOrMerge(List<AiMessage> messages, AiMessage next) {
  if (messages.isNotEmpty) {
    final last = messages.last;
    if (last.id == next.id && last.role == next.role) {
      messages[messages.length - 1] = AiMessage(
        id: last.id,
        role: last.role,
        parts: _mergeParts(last.parts, next.parts),
        createdAt: last.createdAt ?? next.createdAt,
        status: next.status,
      );
      return;
    }
  }
  messages.add(next);
}

/// Same-id merge: coalesce the boundary text run (trailing text parts of [a]
/// plus leading text parts of [b]) into a single [AiTextPart], so streamed
/// partial chunks render as one text block. Parts are trimmed individually
/// by the caller, so the boundary run joins with a space.
List<AiMessagePart> _mergeParts(
  List<AiMessagePart> a,
  List<AiMessagePart> b,
) {
  var lastRunStart = a.length;
  while (lastRunStart > 0 && a[lastRunStart - 1] is AiTextPart) {
    lastRunStart--;
  }
  var firstRunEnd = 0;
  while (firstRunEnd < b.length && b[firstRunEnd] is AiTextPart) {
    firstRunEnd++;
  }
  if (lastRunStart == a.length || firstRunEnd == 0) {
    return [...a, ...b];
  }
  final joined =
      [
        for (final p in a.sublist(lastRunStart)) (p as AiTextPart).text,
        for (final p in b.sublist(0, firstRunEnd)) (p as AiTextPart).text,
      ].join(' ');
  return [
    ...a.sublist(0, lastRunStart),
    AiTextPart(text: joined),
    ...b.sublist(firstRunEnd),
  ];
}

Map<String, Object?>? _asArgs(Object? input) {
  if (input is! Map) return null;
  return {
    for (final entry in input.entries) '${entry.key}': entry.value,
  };
}

Object? _toolResultValue(Object? content) {
  return switch (content) {
    String s => s,
    List list => list
        .map((item) {
          if (item is Map && item['type'] == 'text') {
            return '${item['text'] ?? ''}';
          }
          return '$item';
        })
        .join('\n'),
    null => '',
    _ => content,
  };
}

bool _applyToolResult(
  List<AiMessage> messages, {
  required String toolUseId,
  required Object? result,
  required bool isError,
}) {
  return applyAiToolResult(
    messages,
    toolUseId: toolUseId,
    result: result,
    isError: isError,
  );
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
