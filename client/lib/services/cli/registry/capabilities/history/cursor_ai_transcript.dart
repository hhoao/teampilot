import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import '../../../../provider/cursor/cursor_home_layout.dart';
import '../../../../session/session_history_context.dart';

/// Locate Cursor agent transcript under CURSOR_CONFIG_DIR / projects.
Future<AiTranscriptBundle?> locateCursorTranscript(
  SessionHistoryContext ctx,
) async {
  final transcriptPath = await _locateAgentTranscript(ctx);
  if (transcriptPath == null) return null;

  final bytes = await ctx.fs.readBytes(transcriptPath);
  if (bytes == null) return null;

  return AiTranscriptBundle(
    adapterId: 'cursor',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(transcriptPath),
        bytes: bytes,
      ),
    ],
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

String? _cursorConfigRoot(Map<String, String> env, p.Context path) {
  final explicit = env['CURSOR_CONFIG_DIR']?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final home = env['HOME']?.trim() ?? '';
  if (home.isEmpty) return null;
  return path.join(home, CursorHomeLayout.cursorDirName);
}

/// Cursor agent JSONL → [AiMessage] (role + text/tool_use/tool_result blocks).
final class CursorAiTranscriptAdapter implements AiTranscriptAdapter {
  const CursorAiTranscriptAdapter();

  @override
  String get id => 'cursor';

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
        _appendFromEvent(
          messages,
          event,
          fallbackId: () => 'cursor-${fallbackSeq++}',
        );
      }
    }

    return messages;
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

void _appendFromEvent(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}) {
  final role = event['role'];
  if (role != 'user' && role != 'assistant') return;

  final message = event['message'];
  if (message is! Map) return;
  final messageMap = Map<String, dynamic>.from(message);
  final content = messageMap['content'];
  final timestamp = _parseTimestamp(event['timestamp']);
  final id = _messageId(event, fallbackId);

  if (content is String) {
    final text = content.trim();
    if (text.isEmpty) return;
    messages.add(
      AiMessage(
        id: id,
        role: role == 'user' ? AiRole.user : AiRole.assistant,
        parts: [AiTextPart(text: text)],
        createdAt: timestamp,
      ),
    );
    return;
  }

  if (content is! List) return;

  final textParts = <AiTextPart>[];
  final toolParts = <AiToolCallPart>[];
  final toolResults = <({String toolUseId, Object? result, bool isError})>[];
  var toolSeq = 0;

  for (final block in content) {
    if (block is! Map) continue;
    final blockMap = Map<String, dynamic>.from(block);
    switch (blockMap['type']) {
      case 'text':
        final text = _cursorVisibleText('${blockMap['text'] ?? ''}');
        if (text != null) {
          textParts.add(AiTextPart(text: text));
        }
      case 'tool_use':
        // Cursor agent-transcripts often omit `id` on tool_use. Without a
        // fallback we previously dropped every tool and left only the
        // adjacent `[REDACTED]` text sentinel visible.
        final rawId = '${blockMap['id'] ?? ''}'.trim();
        final toolCallId =
            rawId.isNotEmpty ? rawId : '$id-tool-${toolSeq++}';
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

  for (final result in toolResults) {
    _applyToolResult(
      messages,
      toolUseId: result.toolUseId,
      result: result.result,
      isError: result.isError,
    );
  }

  final parts = <AiMessagePart>[
    ...textParts,
    if (role == 'assistant') ...toolParts,
  ];
  if (parts.isEmpty) return;

  final next = AiMessage(
    id: id,
    role: role == 'user' ? AiRole.user : AiRole.assistant,
    parts: parts,
    createdAt: timestamp,
  );

  // Real agent-transcripts often split one turn across multiple assistant
  // lines (tools, then final prose). Merge consecutive assistant messages.
  if (role == 'assistant' &&
      messages.isNotEmpty &&
      messages.last.role == AiRole.assistant) {
    final last = messages.last;
    messages[messages.length - 1] = AiMessage(
      id: last.id,
      role: last.role,
      parts: [...last.parts, ...next.parts],
      createdAt: last.createdAt ?? next.createdAt,
      status: next.status,
    );
    return;
  }

  messages.add(next);
}

/// Cursor parent-facing transcripts put a literal `[REDACTED]` text block
/// next to `tool_use` (standing in for redacted thinking). That is not
/// user-visible prose — drop the sentinel / trailing marker only.
String? _cursorVisibleText(String raw) {
  var text = raw.trim();
  if (text.isEmpty || text == '[REDACTED]') return null;
  if (text.endsWith('[REDACTED]')) {
    text = text.substring(0, text.length - '[REDACTED]'.length).trimRight();
  }
  if (text.isEmpty) return null;
  return text;
}

String _messageId(Map<String, dynamic> event, String Function() fallbackId) {
  final uuid = event['uuid'] ?? event['id'];
  if (uuid is String && uuid.isNotEmpty) return uuid;
  final message = event['message'];
  if (message is Map) {
    final mid = message['id'];
    if (mid is String && mid.isNotEmpty) return mid;
  }
  return fallbackId();
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
