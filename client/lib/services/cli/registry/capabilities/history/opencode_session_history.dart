import 'dart:convert';

import '../session_history_capability.dart';

/// OpenCode history from on-disk storage under `$OPENCODE_DATA_DIR`.
///
/// Layout (no `opencode export` subprocess):
/// - `storage/session/**/ses_*.json` — session record (id discovery)
/// - `storage/message/{sessionId}/*.json` — message info (`role`, `time`)
/// - `storage/part/{messageId}/*.json` — parts (`text`, `tool`, …)
///
/// Aligns with OpenCode MessageV2 / Storage file layout.
final class OpencodeSessionHistory implements SessionHistoryCapability {
  const OpencodeSessionHistory();

  @override
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx) async {
    final sessionId = await _resolveSessionId(ctx);
    if (sessionId == null) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final dataDir = ctx.env['OPENCODE_DATA_DIR']?.trim() ?? '';
    if (dataDir.isEmpty) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final path = ctx.fs.pathContext;
    final messageDir = path.join(dataDir, 'storage', 'message', sessionId);
    final messageStat = await ctx.fs.stat(messageDir);
    if (!messageStat.isDirectory) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final messageFiles = await _listJsonFiles(ctx, messageDir);
    if (messageFiles.isEmpty) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final messages = <_OcMessage>[];
    for (final filePath in messageFiles) {
      final raw = await ctx.fs.readString(filePath);
      if (raw == null) continue;
      final obj = _tryDecodeObject(raw);
      if (obj == null) continue;
      final id = '${obj['id'] ?? ''}'.trim();
      final role = '${obj['role'] ?? ''}'.trim();
      if (id.isEmpty || (role != 'user' && role != 'assistant')) continue;
      messages.add(
        _OcMessage(
          id: id,
          role: role,
          createdMs: _createdMs(obj['time']),
        ),
      );
    }
    messages.sort((a, b) {
      final byTime = a.createdMs.compareTo(b.createdMs);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });

    final turns = <SessionHistoryTurn>[];
    for (final message in messages) {
      final partDir = path.join(dataDir, 'storage', 'part', message.id);
      final partFiles = await _listJsonFiles(ctx, partDir);
      for (final partPath in partFiles) {
        final raw = await ctx.fs.readString(partPath);
        if (raw == null) continue;
        final part = _tryDecodeObject(raw);
        if (part == null) continue;
        turns.addAll(_turnsFromPart(part, message));
      }
    }

    return SessionHistorySnapshot(
      turns: turns,
      status: SessionHistoryLoadStatus.ready,
    );
  }

  Future<String?> _resolveSessionId(SessionHistoryContext ctx) async {
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final dataDir = ctx.env['OPENCODE_DATA_DIR']?.trim() ?? '';
    if (dataDir.isEmpty) return null;
    final path = ctx.fs.pathContext;
    final sessionDir = path.join(dataDir, 'storage', 'session');

    var bestName = '';
    try {
      final entries = await ctx.fs.listDirRecursive(sessionDir);
      for (final e in entries) {
        if (e.isDirectory) continue;
        final name = path.basename(e.name);
        if (!name.startsWith('ses_') || !name.endsWith('.json')) continue;
        if (e.name.compareTo(bestName) > 0) bestName = e.name;
      }
    } on Object {
      return null;
    }
    if (bestName.isEmpty) return null;
    final name = path.basename(bestName);
    return name.substring(0, name.length - '.json'.length);
  }
}

class _OcMessage {
  const _OcMessage({
    required this.id,
    required this.role,
    required this.createdMs,
  });

  final String id;
  final String role;
  final int createdMs;
}

Future<List<String>> _listJsonFiles(
  SessionHistoryContext ctx,
  String dir,
) async {
  final stat = await ctx.fs.stat(dir);
  if (!stat.isDirectory) return const [];
  final path = ctx.fs.pathContext;
  final out = <String>[];
  try {
    final entries = await ctx.fs.listDir(dir);
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (!e.name.endsWith('.json')) continue;
      out.add(path.join(dir, e.name));
    }
  } on Object {
    return const [];
  }
  out.sort();
  return out;
}

Map<String, dynamic>? _tryDecodeObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

int _createdMs(Object? time) {
  if (time is Map) {
    final created = time['created'];
    if (created is num) return created.toInt();
  }
  return 0;
}

Iterable<SessionHistoryTurn> _turnsFromPart(
  Map<String, dynamic> part,
  _OcMessage message,
) {
  final type = part['type'];
  final timestamp = message.createdMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(message.createdMs, isUtc: true)
      : null;

  switch (type) {
    case 'text':
      if (part['synthetic'] == true || part['ignored'] == true) {
        return const [];
      }
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isEmpty) return const [];
      return [
        SessionHistoryTurn(
          role: message.role == 'user'
              ? SessionHistoryRole.user
              : SessionHistoryRole.assistant,
          markdown: text,
          timestamp: timestamp,
        ),
      ];
    case 'tool':
      final toolName = '${part['tool'] ?? ''}'.trim();
      final name = toolName.isEmpty ? null : toolName;
      final stateRaw = part['state'];
      if (stateRaw is! Map) {
        return [
          SessionHistoryTurn(
            role: SessionHistoryRole.tool,
            toolName: name,
            markdown: name ?? 'tool',
            timestamp: timestamp,
            collapsedByDefault: true,
          ),
        ];
      }
      final state = Map<String, dynamic>.from(stateRaw);
      final turns = <SessionHistoryTurn>[];
      final input = state['input'];
      final inputMarkdown = input == null
          ? (name ?? 'tool')
          : '```json\n${const JsonEncoder.withIndent('  ').convert(input)}\n```';
      turns.add(
        SessionHistoryTurn(
          role: SessionHistoryRole.tool,
          toolName: name,
          markdown: inputMarkdown,
          timestamp: timestamp,
          collapsedByDefault: true,
        ),
      );
      final status = '${state['status'] ?? ''}';
      if (status == 'completed') {
        final output = '${state['output'] ?? ''}';
        turns.add(
          SessionHistoryTurn(
            role: SessionHistoryRole.tool,
            toolName: name,
            markdown: output,
            timestamp: timestamp,
            collapsedByDefault: true,
          ),
        );
      } else if (status == 'error') {
        final error = '${state['error'] ?? ''}'.trim();
        if (error.isNotEmpty) {
          turns.add(
            SessionHistoryTurn(
              role: SessionHistoryRole.tool,
              toolName: name,
              markdown: error,
              timestamp: timestamp,
              collapsedByDefault: true,
            ),
          );
        }
      }
      return turns;
    default:
      return const [];
  }
}
