import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../resume/pinned_transcript_probe.dart';
import '../session_history_capability.dart';

/// Locate flashskyai JSONL under `{root}/workspaces/{bucket}/{taskId}.jsonl`.
Future<AiTranscriptBundle?> locateFlashskyaiTranscript(
  SessionHistoryContext ctx,
) async {
  final probe = await probePinnedTranscript(
    fs: ctx.fs,
    toolRoots: ctx.transcriptRoots,
    sessionId: ctx.taskId,
    bucket: ctx.bucket,
    layoutSegments: const ['workspaces'],
  );
  final path = probe.matchedPath;
  if (!probe.exists || path == null) return null;

  final stat = await ctx.fs.stat(path);
  if (!stat.isFile) return null;

  final bytes = await ctx.fs.readBytes(path);
  if (bytes == null) return null;

  return AiTranscriptBundle(
    adapterId: 'flashskyai',
    fragments: [
      AiTranscriptFragment(
        name: ctx.fs.pathContext.basename(path),
        bytes: bytes,
      ),
    ],
  );
}

/// flashskyai JSONL → [AiMessage] (same shapes as Claude Code).
final class FlashskyaiAiTranscriptAdapter implements AiTranscriptAdapter {
  const FlashskyaiAiTranscriptAdapter();

  @override
  String get id => 'flashskyai';

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
          fallbackId: () => 'flashskyai-${fallbackSeq++}',
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

void _appendFromEvent(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}) {
  final type = event['type'];
  if (type != 'user' && type != 'assistant') return;

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
        role: type == 'user' ? AiRole.user : AiRole.assistant,
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

  for (final block in content) {
    if (block is! Map) continue;
    final blockMap = Map<String, dynamic>.from(block);
    switch (blockMap['type']) {
      case 'text':
        final text = '${blockMap['text'] ?? ''}'.trim();
        if (text.isNotEmpty) {
          textParts.add(AiTextPart(text: text));
        }
      case 'tool_use':
        final toolCallId = '${blockMap['id'] ?? ''}';
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
    if (type == 'assistant') ...toolParts,
  ];
  if (parts.isEmpty) return;

  messages.add(
    AiMessage(
      id: id,
      role: type == 'user' ? AiRole.user : AiRole.assistant,
      parts: parts,
      createdAt: timestamp,
    ),
  );
}

String _messageId(Map<String, dynamic> event, String Function() fallbackId) {
  final uuid = event['uuid'];
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
