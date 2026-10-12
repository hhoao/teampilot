import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

/// OpenCode v2 `session_message` rows → [AiMessage].
///
/// Fragments are `session_message/{id}.json` objects with `type` plus the
/// projected payload (`text` / `content` / `state`). V1 `message/` + `part/`
/// trees are not read.
final class OpencodeAiTranscriptAdapter implements AiTranscriptAdapter {
  const OpencodeAiTranscriptAdapter();

  @override
  String get id => 'opencode';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final messages = <AiMessage>[];
    for (final fragment in bundle.fragments) {
      if (!fragment.name.startsWith('session_message/')) continue;
      final obj = _tryDecodeObject(
        utf8.decode(fragment.bytes, allowMalformed: true),
      );
      if (obj == null) continue;
      final parsed = _messageFromV2(obj);
      if (parsed != null) messages.add(parsed);
    }
    messages.sort((a, b) {
      final aMs = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bMs = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final byTime = aMs.compareTo(bMs);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return finalizeAiMessagesForHistory(messages);
  }
}

AiMessage? _messageFromV2(Map<String, dynamic> obj) {
  final id = '${obj['id'] ?? ''}'.trim();
  if (id.isEmpty) return null;
  final type = '${obj['type'] ?? ''}'.trim();
  final createdMs = _createdMs(obj['time']);
  final createdAt = createdMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true)
      : null;

  switch (type) {
    case 'user':
      final text = '${obj['text'] ?? ''}'.trim();
      if (text.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
        createdAt: createdAt,
      );
    case 'assistant':
      final parts = _assistantParts(obj['content']);
      if (parts.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: parts,
        createdAt: createdAt,
      );
    case 'shell':
      final command = '${obj['command'] ?? ''}'.trim();
      final shellId = '${obj['shellID'] ?? obj['id'] ?? id}'.trim();
      if (shellId.isEmpty) return null;
      final statusRaw = '${obj['status'] ?? ''}';
      final completed = statusRaw == 'completed' || statusRaw == 'error';
      return AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: shellId,
            toolName: 'shell',
            args: command.isEmpty ? null : {'command': command},
            result: obj['output'],
            status: completed
                ? AiToolCallStatus.complete
                : AiToolCallStatus.incomplete,
            isError:
                statusRaw == 'error' ||
                (obj['exit'] is num && obj['exit'] != 0),
          ),
        ],
        createdAt: createdAt,
      );
    default:
      return null;
  }
}

List<AiMessagePart> _assistantParts(Object? content) {
  if (content is! List) return const [];
  final parts = <AiMessagePart>[];
  for (final item in content) {
    if (item is! Map) continue;
    final part = Map<String, dynamic>.from(item);
    final kind = '${part['type'] ?? ''}';
    if (kind == 'text') {
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isNotEmpty) parts.add(AiTextPart(text: text));
    } else if (kind == 'reasoning') {
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isNotEmpty) parts.add(AiReasoningPart(text: text));
    } else if (kind == 'tool') {
      final tool = _toolPart(part);
      if (tool != null) parts.add(tool);
    }
  }
  return parts;
}

AiToolCallPart? _toolPart(Map<String, dynamic> part) {
  final callId = '${part['id'] ?? ''}'.trim();
  if (callId.isEmpty) return null;
  final name = '${part['name'] ?? ''}'.trim();
  final stateRaw = part['state'];
  if (stateRaw is! Map) {
    return AiToolCallPart(
      toolCallId: callId,
      toolName: name.isEmpty ? 'tool' : name,
    );
  }
  final state = Map<String, dynamic>.from(stateRaw);
  final statusRaw = '${state['status'] ?? ''}';
  final isError = statusRaw == 'error';
  Object? result;
  var status = AiToolCallStatus.incomplete;
  if (statusRaw == 'completed') {
    result = _completedToolResult(state);
    status = AiToolCallStatus.complete;
  } else if (isError) {
    result = _errorToolResult(state);
    status = AiToolCallStatus.complete;
  }
  return AiToolCallPart(
    toolCallId: callId,
    toolName: name.isEmpty ? 'tool' : name,
    args: _asArgs(state['input']),
    result: result,
    status: status,
    isError: isError,
  );
}

Object? _completedToolResult(Map<String, dynamic> state) {
  final content = state['content'];
  if (content is List) {
    final texts = <String>[
      for (final item in content)
        if (item is Map && item['type'] == 'text')
          '${item['text'] ?? ''}'.trim(),
    ]..removeWhere((t) => t.isEmpty);
    if (texts.isNotEmpty) return texts.join('\n');
  }
  return null;
}

Object? _errorToolResult(Map<String, dynamic> state) {
  final error = state['error'];
  if (error is Map) {
    final message = '${error['message'] ?? ''}'.trim();
    if (message.isNotEmpty) return message;
  }
  if (error is String && error.trim().isNotEmpty) return error.trim();
  return null;
}

Map<String, Object?>? _asArgs(Object? input) {
  if (input is! Map) return null;
  return {for (final entry in input.entries) '${entry.key}': entry.value};
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
