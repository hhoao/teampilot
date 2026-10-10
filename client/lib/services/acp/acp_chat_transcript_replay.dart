import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

String encodeAcpChatTranscript(List<AiMessage> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    final line = _encodeMessage(message);
    if (line == null) continue;
    buffer.writeln(jsonEncode(line));
  }
  return buffer.toString();
}

List<AiMessage> decodeAcpChatTranscript(String? jsonl) {
  if (jsonl == null || jsonl.isEmpty) return const [];
  final messages = <AiMessage>[];
  for (final raw in jsonl.split('\n')) {
    if (raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final message = _decodeMessage(Map<String, Object?>.from(decoded));
      if (message != null) messages.add(message);
    } on FormatException {
      continue;
    }
  }
  return messages;
}

/// Compatibility alias until Task 2 switches the writer to encode/decode.
List<AiMessage> replayAcpChatTranscript(String? jsonl) =>
    decodeAcpChatTranscript(jsonl);

List<AiMessage> mergeHydratedAcpMessages({
  required List<AiMessage> loaded,
  required List<AiMessage> live,
}) {
  if (loaded.isEmpty) return live;
  if (live.isEmpty) return loaded;
  final skipLiveFirst =
      _userText(loaded.last) != null &&
      _userText(loaded.last) == _userText(live.first);
  return [...loaded, ...live.skip(skipLiveFirst ? 1 : 0)];
}

String? _userText(AiMessage message) {
  if (message.role != AiRole.user) return null;
  return message.parts.whereType<AiTextPart>().map((p) => p.text).join();
}

Map<String, Object?>? _encodeMessage(AiMessage message) {
  final at = message.createdAt?.toUtc().toIso8601String();
  switch (message.role) {
    case AiRole.user:
      final text = message.parts.whereType<AiTextPart>().map((p) => p.text).join();
      if (text.isEmpty) return null;
      return {
        'v': 1,
        'type': 'user',
        'id': message.id,
        'text': text,
        if (at != null) 'at': at,
      };
    case AiRole.system:
      final text = message.parts.whereType<AiTextPart>().map((p) => p.text).join();
      if (text.isEmpty) return null;
      return {
        'v': 1,
        'type': 'system',
        'id': message.id,
        'message': text,
        if (at != null) 'at': at,
      };
    case AiRole.assistant:
      final parts = <Map<String, Object?>>[
        for (final part in message.parts)
          if (_encodePart(part) case final encoded?) encoded,
      ];
      if (parts.isEmpty) return null;
      return {
        'v': 1,
        'type': 'assistant',
        'id': message.id,
        if (at != null) 'at': at,
        'parts': parts,
      };
  }
}

Map<String, Object?>? _encodePart(AiMessagePart part) {
  switch (part) {
    case AiTextPart(:final text):
      if (text.isEmpty) return null;
      return {'kind': 'text', 'text': text};
    case AiReasoningPart(:final text):
      if (text.isEmpty) return null;
      return {'kind': 'reasoning', 'text': text};
    case AiToolCallPart():
      return {
        'kind': 'tool',
        'toolCallId': part.toolCallId,
        'title': part.toolName,
        'status': part.status.name,
        'isError': part.isError,
      };
  }
}

AiMessage? _decodeMessage(Map<String, Object?> entry) {
  if (entry['v'] != 1) return null;
  final id = entry['id'];
  if (id is! String || id.isEmpty) return null;
  final at = _at(entry);
  switch (entry['type']) {
    case 'user':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
        createdAt: at,
      );
    case 'system':
      final message = entry['message'];
      if (message is! String || message.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.system,
        parts: [AiTextPart(text: message)],
        createdAt: at,
      );
    case 'assistant':
      final rawParts = entry['parts'];
      if (rawParts is! List) return null;
      final parts = <AiMessagePart>[];
      for (final item in rawParts) {
        if (item is! Map) continue;
        final part = _decodePart(Map<String, Object?>.from(item));
        if (part != null) parts.add(part);
      }
      if (parts.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: parts,
        createdAt: at,
      );
    default:
      return null;
  }
}

AiMessagePart? _decodePart(Map<String, Object?> entry) {
  switch (entry['kind']) {
    case 'text':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiTextPart(text: text);
    case 'reasoning':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiReasoningPart(text: text);
    case 'tool':
      final toolCallId = entry['toolCallId'];
      if (toolCallId is! String || toolCallId.isEmpty) return null;
      final title = entry['title'];
      return AiToolCallPart(
        toolCallId: toolCallId,
        toolName: title is String && title.isNotEmpty ? title : toolCallId,
        status: _status(entry['status']),
        isError: entry['isError'] == true,
      );
    default:
      return null;
  }
}

AiToolCallStatus _status(Object? raw) {
  if (raw is! String) return AiToolCallStatus.incomplete;
  for (final value in AiToolCallStatus.values) {
    if (value.name == raw) return value;
  }
  return AiToolCallStatus.incomplete;
}

DateTime? _at(Map<String, Object?> entry) {
  final at = entry['at'];
  if (at is! String || at.isEmpty) return null;
  return DateTime.tryParse(at);
}
