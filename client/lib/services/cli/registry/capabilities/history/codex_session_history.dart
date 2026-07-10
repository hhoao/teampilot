import 'dart:convert';

import '../session_history_capability.dart';

/// Codex rollout JSONL under `$CODEX_HOME/sessions/**/rollout-*.jsonl`.
///
/// Aligns with agenthud Codex session schema: `session_meta`, `event_msg`,
/// `response_item`. Prefers `event_msg` user/agent text; attaches tool names
/// from `response_item.function_call` / `function_call_output` via `call_id`.
/// Filters `<environment_context>` and developer-role noise.
final class CodexSessionHistory implements SessionHistoryCapability {
  const CodexSessionHistory();

  static final _rolloutId = RegExp(
    r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
  );

  @override
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx) async {
    final path = await _locateRollout(ctx);
    if (path == null) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final content = await ctx.fs.readString(path);
    if (content == null) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final toolNamesByCallId = <String, String>{};
    final turns = <SessionHistoryTurn>[];
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final event = _tryDecodeObject(trimmed);
      if (event == null) continue;
      turns.addAll(_turnsFromRecord(event, toolNamesByCallId));
    }

    return SessionHistorySnapshot(
      turns: turns,
      status: SessionHistoryLoadStatus.ready,
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

Iterable<SessionHistoryTurn> _turnsFromRecord(
  Map<String, dynamic> record,
  Map<String, String> toolNamesByCallId,
) {
  final type = record['type'];
  final timestamp = _parseTimestamp(record['timestamp']);
  final payloadRaw = record['payload'];
  if (payloadRaw is! Map) return const [];
  final payload = Map<String, dynamic>.from(payloadRaw);

  switch (type) {
    case 'event_msg':
      return _turnsFromEventMsg(payload, timestamp);
    case 'response_item':
      return _turnsFromResponseItem(payload, timestamp, toolNamesByCallId);
    default:
      return const [];
  }
}

Iterable<SessionHistoryTurn> _turnsFromEventMsg(
  Map<String, dynamic> payload,
  DateTime? timestamp,
) {
  final kind = payload['type'];
  switch (kind) {
    case 'user_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return const [];
      if (_isEnvironmentContext(message)) return const [];
      return [
        SessionHistoryTurn(
          role: SessionHistoryRole.user,
          markdown: message,
          timestamp: timestamp,
        ),
      ];
    case 'agent_message':
      final message = '${payload['message'] ?? ''}'.trim();
      if (message.isEmpty) return const [];
      return [
        SessionHistoryTurn(
          role: SessionHistoryRole.assistant,
          markdown: message,
          timestamp: timestamp,
        ),
      ];
    default:
      return const [];
  }
}

Iterable<SessionHistoryTurn> _turnsFromResponseItem(
  Map<String, dynamic> payload,
  DateTime? timestamp,
  Map<String, String> toolNamesByCallId,
) {
  final kind = payload['type'];
  switch (kind) {
    case 'function_call':
      final name = '${payload['name'] ?? ''}'.trim();
      final callId = payload['call_id'];
      if (callId is String && callId.isNotEmpty && name.isNotEmpty) {
        toolNamesByCallId[callId] = name;
      }
      final argsRaw = payload['arguments'];
      final markdown = _formatFunctionArgs(argsRaw, fallbackName: name);
      return [
        SessionHistoryTurn(
          role: SessionHistoryRole.tool,
          toolName: name.isEmpty ? null : name,
          markdown: markdown,
          timestamp: timestamp,
          collapsedByDefault: true,
        ),
      ];
    case 'function_call_output':
      final callId = payload['call_id'];
      final correlated = callId is String ? toolNamesByCallId[callId] : null;
      final output = '${payload['output'] ?? ''}';
      return [
        SessionHistoryTurn(
          role: SessionHistoryRole.tool,
          toolName: correlated,
          markdown: output,
          timestamp: timestamp,
          collapsedByDefault: true,
        ),
      ];
    case 'message':
      // Prefer event_msg for user/agent text; skip developer / duplicate noise.
      return const [];
    default:
      return const [];
  }
}

bool _isEnvironmentContext(String message) {
  return message.contains('<environment_context>');
}

String _formatFunctionArgs(Object? argsRaw, {required String fallbackName}) {
  if (argsRaw == null) return fallbackName.isEmpty ? 'tool' : fallbackName;
  if (argsRaw is String) {
    final trimmed = argsRaw.trim();
    if (trimmed.isEmpty) return fallbackName.isEmpty ? 'tool' : fallbackName;
    try {
      final decoded = jsonDecode(trimmed);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      return '```json\n$pretty\n```';
    } on FormatException {
      return trimmed;
    }
  }
  final pretty = const JsonEncoder.withIndent('  ').convert(argsRaw);
  return '```json\n$pretty\n```';
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
