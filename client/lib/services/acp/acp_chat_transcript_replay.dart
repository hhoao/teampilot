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
      final text = message.parts
          .whereType<AiTextPart>()
          .map((p) => p.text)
          .join();
      if (text.isEmpty) return null;
      return {
        'v': 1,
        'type': 'user',
        'id': message.id,
        'text': text,
        if (at != null) 'at': at,
      };
    case AiRole.system:
      final text = message.parts
          .whereType<AiTextPart>()
          .map((p) => p.text)
          .join();
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
      final args = _jsonSafeMap(part.args);
      return {
        'kind': 'tool',
        'toolCallId': part.toolCallId,
        'title': part.toolName,
        'status': part.status.name,
        'isError': part.isError,
        if (args != null) 'args': args,
        if (part.category != AiToolCallCategory.other)
          'category': part.category.name,
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
        args: _decodeArgs(entry['args']),
        category: _category(entry['category']),
      );
    default:
      return null;
  }
}

Map<String, Object?>? _jsonSafeMap(Map<String, Object?>? args) {
  if (args == null) return null;
  try {
    final encoded = jsonDecode(jsonEncode(args));
    if (encoded is! Map) return null;
    return _asStringKeyedMap(encoded);
  } on Object {
    return null;
  }
}

Map<String, Object?>? _decodeArgs(Object? raw) {
  if (raw is! Map) return null;
  return _asStringKeyedMap(raw);
}

Map<String, Object?> _asStringKeyedMap(Map<dynamic, dynamic> raw) => {
  for (final entry in raw.entries) '${entry.key}': _normalizeJson(entry.value),
};

Object? _normalizeJson(Object? value) {
  if (value is Map) return _asStringKeyedMap(value);
  if (value is List) return [for (final item in value) _normalizeJson(item)];
  return value;
}

AiToolCallCategory _category(Object? raw) {
  if (raw is! String) return AiToolCallCategory.other;
  for (final value in AiToolCallCategory.values) {
    if (value.name == raw) return value;
  }
  return AiToolCallCategory.other;
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
