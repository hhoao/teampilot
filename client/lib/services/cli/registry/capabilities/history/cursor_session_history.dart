import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../../provider/cursor/cursor_home_layout.dart';
import '../session_history_capability.dart';

/// Cursor agent history from the **session-isolated** cursor config tree.
///
/// Chat id discovery (same as CursorResumeStrategy):
/// [SessionHistoryContext.persistedNativeId], else `meta.json` scan under
/// `{cursorRoot}/chats/{workspaceHash}/{chatId}/`.
///
/// Transcript path (primary — under the isolated tree, not the user's global
/// home):
/// ```
/// {CURSOR_CONFIG_DIR|HOME/.cursor}/projects/{projectSlug}/agent-transcripts/{chatId}/{chatId}.jsonl
/// ```
/// Also accepts a flat sibling `{chatId}.jsonl` directly under
/// `agent-transcripts/` when present. Chat dirs themselves hold `meta.json` +
/// `store.db` only — this adapter does not parse `store.db`.
///
/// JSONL lines follow the Cursor Agent transcript / tokenuse shape:
/// `{ role, message: { content: [ text | tool_use | tool_result ] } }`.
final class CursorSessionHistory implements SessionHistoryCapability {
  const CursorSessionHistory();

  @override
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx) async {
    final transcriptPath = await _locateAgentTranscript(ctx);
    if (transcriptPath == null) {
      return const SessionHistorySnapshot(
        turns: [],
        status: SessionHistoryLoadStatus.empty,
      );
    }

    final content = await ctx.fs.readString(transcriptPath);
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

  Future<String?> _locateAgentTranscript(SessionHistoryContext ctx) async {
    final configDir = _cursorConfigRoot(ctx.env, ctx.fs.pathContext);
    if (configDir == null) return null;
    final path = ctx.fs.pathContext;
    final chatsRoot = path.join(configDir, 'chats');

    final chatId = await _resolveChatId(ctx, chatsRoot);
    if (chatId == null || chatId.isEmpty) return null;

    final projectsRoot = path.join(configDir, 'projects');
    try {
      for (final project in await ctx.fs.listDir(projectsRoot)) {
        if (!project.isDirectory) continue;
        final transcriptsRoot = path.join(
          projectsRoot,
          project.name,
          'agent-transcripts',
        );
        final nested = path.join(transcriptsRoot, chatId, '$chatId.jsonl');
        if ((await ctx.fs.stat(nested)).isFile) return nested;
        final flat = path.join(transcriptsRoot, '$chatId.jsonl');
        if ((await ctx.fs.stat(flat)).isFile) return flat;
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<String?> _resolveChatId(
    SessionHistoryContext ctx,
    String chatsRoot,
  ) async {
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final path = ctx.fs.pathContext;
    String? best;
    var bestUpdated = -1;
    try {
      for (final wsHash in await ctx.fs.listDir(chatsRoot)) {
        if (!wsHash.isDirectory) continue;
        final wsDir = path.join(chatsRoot, wsHash.name);
        for (final chat in await ctx.fs.listDir(wsDir)) {
          if (!chat.isDirectory) continue;
          final metaRaw = await ctx.fs.readString(
            path.join(wsDir, chat.name, 'meta.json'),
          );
          if (metaRaw == null || metaRaw.isEmpty) continue;
          final meta = _tryDecodeObject(metaRaw);
          if (meta == null || meta['hasConversation'] != true) continue;
          final updated = (meta['updatedAtMs'] as num?)?.toInt() ?? 0;
          if (updated > bestUpdated) {
            bestUpdated = updated;
            best = chat.name;
          }
        }
      }
    } on Object {
      return null;
    }
    return best;
  }

  static String? _cursorConfigRoot(Map<String, String> env, p.Context path) {
    final explicit = env['CURSOR_CONFIG_DIR']?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final home = env['HOME']?.trim() ?? '';
    if (home.isEmpty) return null;
    return path.join(home, CursorHomeLayout.cursorDirName);
  }
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

Iterable<SessionHistoryTurn> _turnsFromEvent(
  Map<String, dynamic> event,
  Map<String, String> toolNamesById,
) {
  final role = event['role'];
  if (role != 'user' && role != 'assistant') return const [];

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
        role: role == 'user'
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
            role: role == 'user'
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
