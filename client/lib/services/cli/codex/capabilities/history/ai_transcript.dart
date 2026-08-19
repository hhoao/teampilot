import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/ai_history_cache_token.dart';
import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';
import 'root_rollout.dart';

/// Locate Codex rollout JSONL under `$CODEX_HOME/sessions/**/rollout-*.jsonl`.
Future<AiTranscriptBundle?> locateCodexTranscript(
  SessionHistoryContext ctx,
) async {
  final path = await _locateRollout(ctx);
  if (path == null) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;

  final cacheToken = await aiHistoryPathCacheToken(
    fs: ctx.fs,
    path: path,
    byteLength: bytes.length,
  );
  return AiTranscriptBundle(
    adapterId: 'codex',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(path),
        bytes: bytes,
      ),
    ],
    hints: {
      'cacheToken': cacheToken,
      ...AiHistoryWatchMeta(
        changeWatchRoot: ctx.fs.pathContext.dirname(path),
        cacheTokenPaths: [path],
      ).toHints(),
    },
  );
}

Future<String?> _locateRollout(SessionHistoryContext ctx) async {
  final home = ctx.env['CODEX_HOME']?.trim() ?? '';
  if (home.isEmpty) return null;
  final hit = await pickCodexRootRollout(
    fs: ctx.fs,
    codexHome: home,
    persistedNativeId: ctx.persistedNativeId,
  );
  return hit?.path;
}

/// Codex rollout JSONL → [AiMessage] with text / tool-call parts.
final class CodexAiTranscriptAdapter implements AiTranscriptAdapter {
  const CodexAiTranscriptAdapter();

  @override
  String get id => 'codex';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final messages = <AiMessage>[];
    var fallbackSeq = 0;

    for (final fragment in bundle.fragments) {
      final content = utf8.decode(fragment.bytes, allowMalformed: true);
      for (final line in const LineSplitter().convert(content)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final event = _tryDecodeObject(trimmed);
        if (event == null) continue;
        appendCodexJsonlEvent(
          messages,
          event,
          fallbackId: () => 'codex-${fallbackSeq++}',
        );
      }
    }

    return finalizeAiMessagesForHistory(messages);
  }
}

Map<String, dynamic>? _tryDecodeObject(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// Appends one Codex transcript record into [messages]. Used by
/// [CodexAiTranscriptAdapter.parse] to parse codex's `payload`-wrapped
/// `event_msg`/`response_item` rows. Returns whether the event was consumed
/// (produced or modified a message).
bool appendCodexJsonlEvent(
  List<AiMessage> messages,
  Map<String, dynamic> record, {
  required String Function() fallbackId,
}) {
  final type = record['type'];
  final timestamp = _parseTimestamp(record['timestamp']);
  final payloadRaw = record['payload'];
  if (payloadRaw is! Map) return false;
  final payload = Map<String, dynamic>.from(payloadRaw);

  switch (type) {
    case 'event_msg':
      return _appendFromEventMsg(
        messages,
        payload,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    case 'response_item':
      return _appendFromResponseItem(
        messages,
        payload,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    default:
      return false;
  }
}

bool _appendFromEventMsg(
  List<AiMessage> messages,
  Map<String, dynamic> payload, {
  required DateTime? timestamp,
  required String Function() fallbackId,
}) {
  final kind = payload['type'];
  switch (kind) {
    case 'user_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return false;
      if (_isEnvironmentContext(message)) return false;
      // Older codex wrote the same text as response_item.message role=user
      // (echo) right before this event_msg — keep only the first.
      if (_isAdjacentDuplicateUserText(messages, message)) return false;
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.user,
          parts: [AiTextPart(text: message)],
          createdAt: timestamp,
        ),
      );
      return true;
    case 'agent_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return false;
      // commentary + final_answer can emit identical text for one turn.
      if (_isAdjacentDuplicateAssistantText(messages, message)) return false;
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.assistant,
          parts: [AiTextPart(text: message)],
          createdAt: timestamp,
        ),
      );
      return true;
    case 'agent_reasoning':
      final text = '${payload['text'] ?? ''}'.trim();
      if (text.isEmpty) return false;
      return _appendAssistantReasoning(
        messages,
        text: text,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    default:
      return false;
  }
}

bool _appendFromResponseItem(
  List<AiMessage> messages,
  Map<String, dynamic> payload, {
  required DateTime? timestamp,
  required String Function() fallbackId,
}) {
  final kind = payload['type'];
  switch (kind) {
    case 'function_call':
      final name = '${payload['name'] ?? ''}'.trim();
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return false;
      final toolName = name.isEmpty ? 'tool' : name;
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: callId,
              toolName: toolName,
              args: _parseArgs(payload['arguments']),
              argsText: _argsText(payload['arguments']),
            ),
          ],
          createdAt: timestamp,
        ),
      );
      return true;
    case 'function_call_output':
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return false;
      return _applyToolResult(
        messages,
        toolUseId: callId,
        result: '${payload['output'] ?? ''}',
        isError: false,
      );
    case 'custom_tool_call':
      final name = '${payload['name'] ?? ''}'.trim();
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return false;
      final toolName = name.isEmpty ? 'tool' : name;
      final input = payload['input'];
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: callId,
              toolName: toolName,
              // 统一 G2 语义：input 为 Map 或 JSON 字符串 → args Map；
              // 非 JSON 字符串 → args=null，argsText 保留原样。
              argsText: _argsText(input),
              args: _parseArgs(input),
            ),
          ],
          createdAt: timestamp,
        ),
      );
      return true;
    case 'custom_tool_call_output':
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return false;
      return _applyToolResult(
        messages,
        toolUseId: callId,
        result: '${payload['output'] ?? ''}',
        isError: false,
      );
    case 'reasoning':
      // Dual-written with event_msg agent_reasoning — keep the first only.
      final text = _reasoningSummaryText(payload);
      if (text == null) return false;
      return _appendAssistantReasoning(
        messages,
        text: text,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    case 'message':
      // codex ≥0.147 writes user/assistant text as response_item.message
      // (older versions used event_msg.user_message / agent_message, and
      // echoed the text here too). Surface user/assistant, dedup the echo,
      // and keep developer / system / tool roles hidden.
      final role = payload['role'];
      final text = _messageText(payload['content']);
      if (text == null || text.isEmpty) return false;
      if (role == 'user') {
        if (_isEnvironmentContext(text)) return false;
        if (_isAdjacentDuplicateUserText(messages, text)) return false;
        messages.add(
          AiMessage(
            id: fallbackId(),
            role: AiRole.user,
            parts: [AiTextPart(text: text)],
            createdAt: timestamp,
          ),
        );
        return true;
      } else if (role == 'assistant') {
        if (_isAdjacentDuplicateAssistantText(messages, text)) return false;
        messages.add(
          AiMessage(
            id: fallbackId(),
            role: AiRole.assistant,
            parts: [AiTextPart(text: text)],
            createdAt: timestamp,
          ),
        );
        return true;
      }
      return false;
    default:
      return false;
  }
}

/// Joins the input_text / output_text chunks of a `response_item.message`
/// content array into one text block; null when there is nothing to surface.
String? _messageText(Object? contentRaw) {
  if (contentRaw is! List) return null;
  final chunks = <String>[];
  for (final item in contentRaw) {
    if (item is! Map) continue;
    final type = item['type'];
    if (type != 'input_text' && type != 'output_text') continue;
    final text = '${item['text'] ?? ''}'.trim();
    if (text.isNotEmpty) chunks.add(text);
  }
  if (chunks.isEmpty) return null;
  return chunks.join('\n');
}

/// Codex often logs the same reasoning as both `event_msg.agent_reasoning`
/// and `response_item.reasoning`. Keep whichever arrives first.
bool _appendAssistantReasoning(
  List<AiMessage> messages, {
  required String text,
  required DateTime? timestamp,
  required String Function() fallbackId,
}) {
  if (_isAdjacentDuplicateAssistantReasoning(messages, text)) return false;
  messages.add(
    AiMessage(
      id: fallbackId(),
      role: AiRole.assistant,
      parts: [AiReasoningPart(text: text)],
      createdAt: timestamp,
    ),
  );
  return true;
}

bool _isAdjacentDuplicateAssistantReasoning(
  List<AiMessage> messages,
  String text,
) {
  if (messages.isEmpty) return false;
  final last = messages.last;
  if (last.role != AiRole.assistant || last.parts.length != 1) return false;
  final part = last.parts.single;
  return part is AiReasoningPart && part.text == text;
}

bool _isAdjacentDuplicateUserText(List<AiMessage> messages, String text) {
  if (messages.isEmpty) return false;
  final last = messages.last;
  if (last.role != AiRole.user || last.parts.length != 1) return false;
  final part = last.parts.single;
  return part is AiTextPart && part.text == text;
}

bool _isAdjacentDuplicateAssistantText(List<AiMessage> messages, String text) {
  if (messages.isEmpty) return false;
  final last = messages.last;
  if (last.role != AiRole.assistant || last.parts.length != 1) return false;
  final part = last.parts.single;
  return part is AiTextPart && part.text == text;
}

bool _isEnvironmentContext(String message) {
  return message.contains('<environment_context>');
}

String? _reasoningSummaryText(Map<String, dynamic> payload) {
  final summary = payload['summary'];
  if (summary is! List) return null;
  final chunks = <String>[];
  for (final item in summary) {
    if (item is! Map) continue;
    if (item['type'] != 'summary_text') continue;
    final text = '${item['text'] ?? ''}'.trim();
    if (text.isNotEmpty) chunks.add(text);
  }
  if (chunks.isEmpty) return null;
  return chunks.join('\n\n');
}

Map<String, Object?>? _parseArgs(Object? argsRaw) {
  if (argsRaw == null) return null;
  if (argsRaw is Map) {
    return {
      for (final entry in argsRaw.entries) '${entry.key}': entry.value,
    };
  }
  if (argsRaw is String) {
    final trimmed = argsRaw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } on FormatException {
      return null;
    }
  }
  return null;
}

String? _argsText(Object? argsRaw) {
  if (argsRaw is String) {
    final trimmed = argsRaw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
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
