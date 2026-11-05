import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

/// Current on-disk schema of the app-owned ACP chat transcript.
///
/// v1 was a **whole-message snapshot**: one line per message with every part
/// inline. Every commit re-encoded and rewrote the entire file, so a long
/// streaming turn (one message growing to thousands of parts) cost O(n²) of
/// JSON encoding plus a multi-MB disk write on every tool-call update.
///
/// v2 is an **append-only log of keyed records**:
///
/// * `{"v":2,"type":"user"|"assistant"|"system","id":...,"at":...}` — message
///   header (metadata only; never clears parts).
/// * `{"v":2,"type":"part","mid":...,"i":...,"part":{...}}` — set the part at
///   index `i` of message `mid`.
/// * `{"v":2,"type":"text","mid":...,"i":...,"kind":"text"|"reasoning",
///   "append":...}` — append to the text/reasoning part at index `i`, so a
///   streaming text part does not re-write its whole cumulative text.
/// * `{"v":2,"type":"drop","id":...}` — drop a message.
/// * `{"v":2,"type":"reset"}` — clear everything (reserved).
///
/// Replay folds records in order into an insertion-ordered map: `part` records
/// are keyed upserts, `text` records extend the part built by earlier records.
/// A torn trailing line is skipped, and the next commit re-emits the missing
/// delta. v1 lines are still understood and migrated to v2 on the next write.
const int acpChatTranscriptVersion = 2;

/// Replay outcome: folded messages plus whether legacy v1 records were seen.
class AcpTranscriptDecodeResult {
  const AcpTranscriptDecodeResult({
    required this.messages,
    required this.hasLegacyRecords,
  });

  final List<AiMessage> messages;
  final bool hasLegacyRecords;
}

/// Full compact v2 snapshot: one header line per message + one line per part.
///
/// Used for the first write, v1 migration, and periodic compaction — never on
/// the per-commit hot path.
String encodeAcpChatTranscript(List<AiMessage> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    buffer.writeln(jsonEncode(_messageRecord(message)));
    for (var i = 0; i < message.parts.length; i++) {
      buffer.writeln(jsonEncode(_partRecord(message.id, i, message.parts[i])));
    }
  }
  return buffer.toString();
}

/// v1 encoder. Kept so legacy fixtures (and migration tooling) can produce the
/// old whole-message snapshot format; production writes v2 via
/// [encodeAcpChatTranscript].
String encodeAcpChatTranscriptV1(List<AiMessage> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    final line = _encodeMessage(message);
    if (line == null) continue;
    buffer.writeln(jsonEncode(line));
  }
  return buffer.toString();
}

/// Replays a v1 or v2 transcript into folded messages.
AcpTranscriptDecodeResult decodeAcpChatTranscriptResult(String? jsonl) {
  if (jsonl == null || jsonl.isEmpty) {
    return const AcpTranscriptDecodeResult(
      messages: [],
      hasLegacyRecords: false,
    );
  }
  final builders = <String, _MessageBuilder>{};
  var hasLegacyRecords = false;
  for (final raw in _lines(jsonl)) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // A trailing line can be torn mid-append; skip it like a corrupt line.
      continue;
    }
    if (decoded is! Map) continue;
    final entry = Map<String, Object?>.from(decoded);
    final version = entry['v'];
    if (version == 1) {
      hasLegacyRecords = true;
      final message = _decodeMessage(entry);
      if (message != null) builders[message.id] = _MessageBuilder.of(message);
      continue;
    }
    if (version != acpChatTranscriptVersion) continue;
    final type = entry['type'];
    if (type == 'user' || type == 'assistant' || type == 'system') {
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      final existing = builders[id];
      if (existing == null) {
        builders[id] = _MessageBuilder(
          id: id,
          role: _role(type),
          createdAt: _at(entry),
          status: _messageStatus(entry['status']),
          deliveryChannel: _string(entry['channel']),
        );
      } else {
        existing.role = _role(type);
        final at = _at(entry);
        if (at != null) existing.createdAt = at;
        if (entry.containsKey('status')) {
          existing.status = _messageStatus(entry['status']);
        }
        if (entry.containsKey('channel')) {
          existing.deliveryChannel = _string(entry['channel']);
        }
      }
    } else if (type == 'part') {
      final mid = entry['mid'];
      final index = entry['i'];
      if (mid is! String || index is! int || index < 0) continue;
      final builder = builders[mid];
      if (builder == null) continue;
      final part = entry['part'];
      builder.setPart(
        index,
        part is Map ? _decodePart(Map<String, Object?>.from(part)) : null,
      );
    } else if (type == 'text') {
      final mid = entry['mid'];
      final index = entry['i'];
      final append = entry['append'];
      if (mid is! String || index is! int || index < 0 || append is! String) {
        continue;
      }
      final builder = builders[mid];
      if (builder == null) continue;
      final previous = index < builder.parts.length
          ? builder.parts[index]
          : null;
      if (entry['kind'] == 'reasoning') {
        final text = previous is AiReasoningPart
            ? previous.text + append
            : append;
        builder.setPart(index, AiReasoningPart(text: text));
      } else {
        final text = previous is AiTextPart ? previous.text + append : append;
        builder.setPart(index, AiTextPart(text: text));
      }
    } else if (type == 'drop') {
      final id = entry['id'];
      if (id is String) builders.remove(id);
    } else if (type == 'reset') {
      builders.clear();
    }
  }
  return AcpTranscriptDecodeResult(
    messages: [for (final builder in builders.values) builder.build()],
    hasLegacyRecords: hasLegacyRecords,
  );
}

List<AiMessage> decodeAcpChatTranscript(String? jsonl) =>
    decodeAcpChatTranscriptResult(jsonl).messages;

/// Records that bring [previous] to [next], or `null` when the change is
/// structural (reordering / part removal) and requires a compact rewrite.
///
/// Unchanged parts are detected by instance identity: the ACP runtime cubit
/// rebuilds messages with `copyWith`, which keeps untouched part instances.
/// `identical` is therefore a zero-cost "unchanged" test — no deep JSON
/// comparison of thousands of tool results on the UI isolate.
List<Map<String, Object?>>? buildAcpChatTranscriptDelta({
  required List<AiMessage> previous,
  required List<AiMessage> next,
}) {
  final prevById = <String, AiMessage>{for (final m in previous) m.id: m};
  final nextIds = <String>{for (final m in next) m.id};
  final records = <Map<String, Object?>>[
    for (final message in previous)
      if (!nextIds.contains(message.id)) _dropRecord(message.id),
  ];
  final keptPrev = [
    for (final message in previous)
      if (nextIds.contains(message.id)) message.id,
  ];
  final keptNext = [
    for (final message in next)
      if (prevById.containsKey(message.id)) message.id,
  ];
  if (!_sameIds(keptPrev, keptNext)) return null;

  for (final message in next) {
    final prev = prevById[message.id];
    if (prev == null) {
      records.add(_messageRecord(message));
      for (var i = 0; i < message.parts.length; i++) {
        records.add(_partRecord(message.id, i, message.parts[i]));
      }
      continue;
    }
    if (_metadataChanged(prev, message)) records.add(_messageRecord(message));
    // A shortened part list shifts indices — replay would misalign. Rewrite.
    if (message.parts.length < prev.parts.length) return null;
    var earlierChanged = false;
    for (var i = 0; i < message.parts.length; i++) {
      final part = message.parts[i];
      final old = i < prev.parts.length ? prev.parts[i] : null;
      if (old != null && identical(old, part)) continue;
      // Only the first changed part may be a pure text growth. Once anything
      // else moved, emit a full part record for the rest of this message.
      final suffix = !earlierChanged && old != null
          ? _textSuffix(old, part)
          : null;
      earlierChanged = true;
      if (suffix != null) {
        if (suffix.isEmpty) continue;
        records.add(_textRecord(message.id, i, part, suffix));
        continue;
      }
      records.add(_partRecord(message.id, i, part));
    }
  }
  return records;
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

// ----- v2 records -----

Map<String, Object?> _messageRecord(AiMessage message) {
  final at = message.createdAt?.toUtc().toIso8601String();
  return {
    'v': acpChatTranscriptVersion,
    'type': message.role.name,
    'id': message.id,
    if (at != null) 'at': at,
    if (message.status != AiMessageStatus.complete)
      'status': message.status.name,
    if (message.deliveryChannel != null) 'channel': message.deliveryChannel,
  };
}

Map<String, Object?> _partRecord(
  String mid,
  int index,
  AiMessagePart part,
) => {
  'v': acpChatTranscriptVersion,
  'type': 'part',
  'mid': mid,
  'i': index,
  'part': _encodePart(part),
};

Map<String, Object?> _textRecord(
  String mid,
  int index,
  AiMessagePart part,
  String append,
) => {
  'v': acpChatTranscriptVersion,
  'type': 'text',
  'mid': mid,
  'i': index,
  'kind': part is AiReasoningPart ? 'reasoning' : 'text',
  'append': append,
};

Map<String, Object?> _dropRecord(String id) => {
  'v': acpChatTranscriptVersion,
  'type': 'drop',
  'id': id,
};

bool _metadataChanged(AiMessage a, AiMessage b) =>
    a.role != b.role ||
    a.createdAt != b.createdAt ||
    a.status != b.status ||
    a.deliveryChannel != b.deliveryChannel;

/// Growth suffix when [next] is the same text-ish part with [old] as a prefix.
String? _textSuffix(AiMessagePart old, AiMessagePart next) {
  if (old is AiTextPart &&
      next is AiTextPart &&
      next.text.startsWith(old.text)) {
    return next.text.substring(old.text.length);
  }
  if (old is AiReasoningPart &&
      next is AiReasoningPart &&
      next.text.startsWith(old.text)) {
    return next.text.substring(old.text.length);
  }
  return null;
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One line at a time: avoids allocating a full second copy of a multi-MB
/// transcript via `String.split` on cold open.
Iterable<String> _lines(String source) sync* {
  var start = 0;
  while (start < source.length) {
    final newline = source.indexOf('\n', start);
    final end = newline < 0 ? source.length : newline;
    final line = source.substring(start, end).trim();
    if (line.isNotEmpty) yield line;
    if (newline < 0) return;
    start = newline + 1;
  }
}

class _MessageBuilder {
  _MessageBuilder({
    required this.id,
    required this.role,
    this.createdAt,
    this.status = AiMessageStatus.complete,
    this.deliveryChannel,
  });

  _MessageBuilder.of(AiMessage message)
    : id = message.id,
      role = message.role,
      createdAt = message.createdAt,
      status = message.status,
      deliveryChannel = message.deliveryChannel {
    for (var i = 0; i < message.parts.length; i++) {
      setPart(i, message.parts[i]);
    }
  }

  final String id;
  AiRole role;
  DateTime? createdAt;
  AiMessageStatus status;
  String? deliveryChannel;
  final List<AiMessagePart?> parts = [];

  void setPart(int index, AiMessagePart? part) {
    while (parts.length <= index) {
      parts.add(null);
    }
    parts[index] = part;
  }

  AiMessage build() => AiMessage(
    id: id,
    role: role,
    parts: [for (final part in parts) if (part != null) part],
    createdAt: createdAt,
    status: status,
    deliveryChannel: deliveryChannel,
  );
}

// ----- v1 codec (read-only) -----

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
        if (part.result != null) 'result': _jsonSafeValue(part.result),
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
        result: _normalizeJson(entry['result']),
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

Object? _jsonSafeValue(Object? value) {
  try {
    return _normalizeJson(jsonDecode(jsonEncode(value)));
  } on Object {
    return '$value';
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

AiMessageStatus _messageStatus(Object? raw) {
  if (raw is! String) return AiMessageStatus.complete;
  for (final value in AiMessageStatus.values) {
    if (value.name == raw) return value;
  }
  return AiMessageStatus.complete;
}

AiRole _role(Object? raw) => switch (raw) {
  'user' => AiRole.user,
  'system' => AiRole.system,
  _ => AiRole.assistant,
};

String? _string(Object? raw) => raw is String ? raw : null;

DateTime? _at(Map<String, Object?> entry) {
  final at = entry['at'];
  if (at is! String || at.isEmpty) return null;
  return DateTime.tryParse(at);
}
