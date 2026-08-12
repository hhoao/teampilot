/// Structured OpenCode permission request (`permission.asked` event payload)
/// for chat rendering / answering.
class AgentPermissionRequest {
  const AgentPermissionRequest({
    required this.id,
    required this.description,
    this.patterns = const [],
    this.always = const [],
    this.sessionID,
    this.toolMessageID,
    this.toolCallID,
  });

  /// Permission request id — reply correlation key (`request_id` / `id`).
  final String id;

  /// Human-readable permission text (e.g. `Run \`npm install\``).
  final String description;

  /// Command patterns the permission covers.
  final List<String> patterns;

  /// Tool prefixes offered for "always allow" (may be empty).
  final List<String> always;

  final String? sessionID;
  final String? toolMessageID;
  final String? toolCallID;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPermissionRequest &&
          id == other.id &&
          description == other.description &&
          _sameStrings(patterns, other.patterns) &&
          _sameStrings(always, other.always) &&
          sessionID == other.sessionID &&
          toolMessageID == other.toolMessageID &&
          toolCallID == other.toolCallID;

  @override
  int get hashCode => Object.hash(
    id,
    description,
    Object.hashAll(patterns),
    Object.hashAll(always),
    sessionID,
    toolMessageID,
    toolCallID,
  );
}

/// Parses the forwarded `permission.asked` payload (see
/// `agent_status_plugin.dart`). Returns null when no id is present.
AgentPermissionRequest? parsePermissionRequest(Map<String, Object?> body) {
  final id = _readString(body, const ['request_id', 'id', 'permission_id']);
  if (id == null || id.isEmpty) return null;
  final description = _readString(
    body,
    const ['permission', 'description', 'title'],
  );
  if (description == null || description.isEmpty) return null;

  final patternsRaw = body['patterns'];
  final patterns = patternsRaw == null
      ? _readSingleOrList(body['pattern'])
      : _readStringList(patternsRaw);
  final always = _readStringList(body['always']);

  final tool = body['tool'];
  final toolMap = tool is Map ? Map<String, Object?>.from(tool) : null;

  return AgentPermissionRequest(
    id: id,
    description: description,
    patterns: patterns,
    always: always,
    sessionID: _readString(body, const ['session_id', 'sessionID']),
    toolMessageID: toolMap == null
        ? null
        : _readString(toolMap, const ['messageID', 'message_id']),
    toolCallID: toolMap == null
        ? null
        : _readString(toolMap, const ['callID', 'call_id']),
  );
}

String? _readString(Map<String, Object?> body, List<String> keys) {
  for (final key in keys) {
    final value = body[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const [];
  final out = <String>[];
  for (final item in value) {
    if (item is String && item.trim().isNotEmpty) {
      out.add(item.trim());
    }
  }
  return out;
}

List<String> _readSingleOrList(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return _readStringList(value);
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
