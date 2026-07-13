import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../session_history_capability.dart';

/// Locate Codex rollout JSONL under `$CODEX_HOME/sessions/**/rollout-*.jsonl`.
Future<AiTranscriptBundle?> locateCodexTranscript(
  SessionHistoryContext ctx,
) async {
  final path = await _locateRollout(ctx);
  if (path == null) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;

  return AiTranscriptBundle(
    adapterId: 'codex',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(path),
        bytes: bytes,
      ),
    ],
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

    return messages;
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
      messages.add(
        AiMessage(
          id: fallbackId(),
          role: AiRole.assistant,
          parts: [AiTextPart(text: message)],
          createdAt: timestamp,
        ),
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
    case 'message':
      // Prefer event_msg for user/agent text; skip developer / duplicate noise.
      return;
  }
}

bool _isEnvironmentContext(String message) {
  return message.contains('<environment_context>');
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
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    final parts = msg.parts;
    for (var j = 0; j < parts.length; j++) {
      final part = parts[j];
      if (part is! AiToolCallPart || part.toolCallId != toolUseId) continue;
      final updated = List<AiMessagePart>.of(parts);
      updated[j] = AiToolCallPart(
        toolCallId: part.toolCallId,
        toolName: part.toolName,
        args: part.args,
        argsText: part.argsText,
        result: result,
        isError: isError || part.isError,
      );
      messages[i] = AiMessage(
        id: msg.id,
        role: msg.role,
        parts: updated,
        createdAt: msg.createdAt,
        status: msg.status,
      );
      return;
    }
  }
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
