import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/ai_history_cache_token.dart';
import '../../../../session/ai_history_watch_meta.dart';
import '../../../../session/session_history_context.dart';

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
  final path = ctx.fs.pathContext;
  final sessionsDir = path.join(home, 'sessions');
  final wanted = ctx.persistedNativeId?.trim() ?? '';

  var bestRel = '';
  try {
    final entries = await ctx.fs.listDirRecursive(sessionsDir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      final name = path.basename(e.name);
      final match = _rolloutId.firstMatch(name);
      if (match == null) continue;
      if (wanted.isNotEmpty && match.group(1) != wanted) continue;
      // Lexicographic max over timestamp-prefixed names == newest.
      if (e.name.compareTo(bestRel) > 0) bestRel = e.name;
    }
  } on Object {
    return null;
  }
  if (bestRel.isEmpty) return null;
  return path.join(sessionsDir, bestRel);
}

final _rolloutId = RegExp(
  r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
);

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
        _appendFromRecord(
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

void _appendFromRecord(
  List<AiMessage> messages,
  Map<String, dynamic> record, {
  required String Function() fallbackId,
}) {
  final type = record['type'];
  final timestamp = _parseTimestamp(record['timestamp']);
  final payloadRaw = record['payload'];
  if (payloadRaw is! Map) return;
  final payload = Map<String, dynamic>.from(payloadRaw);

  switch (type) {
    case 'event_msg':
      _appendFromEventMsg(
        messages,
        payload,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    case 'response_item':
      _appendFromResponseItem(
        messages,
        payload,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
  }
}

void _appendFromEventMsg(
  List<AiMessage> messages,
  Map<String, dynamic> payload, {
  required DateTime? timestamp,
  required String Function() fallbackId,
}) {
  final kind = payload['type'];
  switch (kind) {
    case 'user_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return;
      if (_isEnvironmentContext(message)) return;
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.user,
          parts: [AiTextPart(text: message)],
          createdAt: timestamp,
        ),
      );
    case 'agent_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return;
      // commentary + final_answer can emit identical text for one turn.
      if (_isAdjacentDuplicateAssistantText(messages, message)) return;
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.assistant,
          parts: [AiTextPart(text: message)],
          createdAt: timestamp,
        ),
      );
    case 'agent_reasoning':
      final text = '${payload['text'] ?? ''}'.trim();
      if (text.isEmpty) return;
      _appendAssistantReasoning(
        messages,
        text: text,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
  }
}

void _appendFromResponseItem(
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
      if (callId is! String || callId.isEmpty) return;
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
    case 'function_call_output':
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return;
      _applyToolResult(
        messages,
        toolUseId: callId,
        result: '${payload['output'] ?? ''}',
        isError: false,
      );
    case 'custom_tool_call':
      final name = '${payload['name'] ?? ''}'.trim();
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return;
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
              argsText: input is String ? input : null,
              args: input is Map ? _parseArgs(input) : null,
            ),
          ],
          createdAt: timestamp,
        ),
      );
    case 'custom_tool_call_output':
      final callId = payload['call_id'];
      if (callId is! String || callId.isEmpty) return;
      _applyToolResult(
        messages,
        toolUseId: callId,
        result: '${payload['output'] ?? ''}',
        isError: false,
      );
    case 'reasoning':
      // Dual-written with event_msg agent_reasoning — keep the first only.
      final text = _reasoningSummaryText(payload);
      if (text == null) return;
      _appendAssistantReasoning(
        messages,
        text: text,
        timestamp: timestamp,
        fallbackId: fallbackId,
      );
    case 'message':
      // Prefer event_msg for user/agent text; skip developer / duplicate noise.
      return;
  }
}

/// Codex often logs the same reasoning as both `event_msg.agent_reasoning`
/// and `response_item.reasoning`. Keep whichever arrives first.
void _appendAssistantReasoning(
  List<AiMessage> messages, {
  required String text,
  required DateTime? timestamp,
  required String Function() fallbackId,
}) {
  if (_isAdjacentDuplicateAssistantReasoning(messages, text)) return;
  messages.add(
    AiMessage(
      id: fallbackId(),
      role: AiRole.assistant,
      parts: [AiReasoningPart(text: text)],
      createdAt: timestamp,
    ),
  );
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

void _applyToolResult(
  List<AiMessage> messages, {
  required String toolUseId,
  required Object? result,
  required bool isError,
}) {
  applyAiToolResult(
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
