import 'dart:convert';

import '../resume/pinned_transcript_probe.dart';
import '../session_history_capability.dart';

/// flashskyai JSONL history under `{root}/workspaces/{bucket}/{taskId}.jsonl`.
///
/// Event shapes match Claude-style transcript lines (`type` + `message` with
/// string or content-block array: `text`, `tool_use`, `tool_result`), but the
/// on-disk layout uses `workspaces/` (not Claude's `projects/`).
final class FlashskyaiSessionHistory implements SessionHistoryCapability {
  const FlashskyaiSessionHistory();

  static const _layoutSegments = ['workspaces'];

  @override
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx) async {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: ctx.taskId,
      bucket: ctx.bucket,
      layoutSegments: _layoutSegments,
    );
    final path = probe.matchedPath;
    if (!probe.exists || path == null) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final stat = await ctx.fs.stat(path);
    if (!stat.isFile) {
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

    final toolNamesById = <String, String>{};
    final turns = <SessionHistoryTurn>[];
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final event = _tryDecodeObject(trimmed);
      if (event == null) continue;
      turns.addAll(_turnsFromEvent(event, toolNamesById));
    }

    return SessionHistorySnapshot(
      turns: turns,
      status: SessionHistoryLoadStatus.ready,
    );
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

Iterable<SessionHistoryTurn> _turnsFromEvent(
  Map<String, dynamic> event,
  Map<String, String> toolNamesById,
) {
  final type = event['type'];
  if (type != 'user' && type != 'assistant') return const [];

  final message = event['message'];
  if (message is! Map) return const [];
  final messageMap = Map<String, dynamic>.from(message);
  final content = messageMap['content'];
  final timestamp = _parseTimestamp(event['timestamp']);

  if (content is String) {
    final text = content.trim();
    if (text.isEmpty) return const [];
    return [
      SessionHistoryTurn(
        role: type == 'user'
            ? SessionHistoryRole.user
            : SessionHistoryRole.assistant,
        markdown: text,
        timestamp: timestamp,
      ),
    ];
  }

  if (content is! List) return const [];

  final turns = <SessionHistoryTurn>[];
  for (final block in content) {
    if (block is! Map) continue;
    final blockMap = Map<String, dynamic>.from(block);
    final blockType = blockMap['type'];
    switch (blockType) {
      case 'text':
        final text = '${blockMap['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        turns.add(
          SessionHistoryTurn(
            role: type == 'user'
                ? SessionHistoryRole.user
                : SessionHistoryRole.assistant,
            markdown: text,
            timestamp: timestamp,
          ),
        );
      case 'tool_use':
        final name = '${blockMap['name'] ?? 'tool'}';
        final id = blockMap['id'];
        if (id is String && id.isNotEmpty) {
          toolNamesById[id] = name;
        }
        final input = blockMap['input'];
        final inputMarkdown = input == null
            ? ''
            : const JsonEncoder.withIndent('  ').convert(input);
        turns.add(
          SessionHistoryTurn(
            role: SessionHistoryRole.tool,
            toolName: name,
            markdown: inputMarkdown.isEmpty
                ? name
                : '```json\n$inputMarkdown\n```',
            timestamp: timestamp,
            collapsedByDefault: true,
          ),
        );
      case 'tool_result':
        final resultContent = blockMap['content'];
        final markdown = switch (resultContent) {
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
          _ => '$resultContent',
        };
        final toolUseId = blockMap['tool_use_id'];
        final correlatedName = toolUseId is String
            ? toolNamesById[toolUseId]
            : null;
        turns.add(
          SessionHistoryTurn(
            role: SessionHistoryRole.tool,
            toolName: correlatedName,
            markdown: markdown,
            timestamp: timestamp,
            collapsedByDefault: true,
          ),
        );
      default:
        continue;
    }
  }
  return turns;
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
