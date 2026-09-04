/// One "always allow" option on a permission card.
///
/// [label] is the raw rule text shown to the user (e.g.
/// `Bash(rm -rf node_modules)`); [payload] is opaque channel data — the
/// OpenCode SDK prefix string (unused on reply) or the raw Claude
/// `permission_suggestions` entry echoed back as `updatedPermissions`.
class AgentPermissionAlwaysOption {
  const AgentPermissionAlwaysOption({required this.label, this.payload});

  final String label;
  final Object? payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPermissionAlwaysOption && label == other.label;

  @override
  int get hashCode => label.hashCode;
}

/// User's card reply, shared by both answer channels.
enum AgentPermissionReplyKind { allowOnce, always, reject }

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

  /// "Always allow" options offered on the card (may be empty).
  final List<AgentPermissionAlwaysOption> always;

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
          _sameAlways(always, other.always) &&
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
  final description = _readString(body, const [
    'permission',
    'description',
    'title',
  ]);
  if (description == null || description.isEmpty) return null;

  final patternsRaw = body['patterns'];
  final patterns = patternsRaw == null
      ? _readSingleOrList(body['pattern'])
      : _readStringList(patternsRaw);
  final always = _readStringList(
    body['always'],
  ).map((prefix) => AgentPermissionAlwaysOption(label: prefix)).toList();

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

bool _sameAlways(
  List<AgentPermissionAlwaysOption> a,
  List<AgentPermissionAlwaysOption> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Parses a Claude-family `PermissionRequest` hook payload into an
/// [AgentPermissionRequest]. The hook-hold channel correlates replies by the
/// gate's seat key, so the request carries no reply id (`id` is empty).
///
/// Only `addRules` suggestions become always options (v1): `setMode`-style
/// suggestions are skipped. The raw suggestion entry is kept as the option
/// [AgentPermissionAlwaysOption.payload] for the `updatedPermissions` echo.
AgentPermissionRequest? parseClaudePermissionRequest(
  Map<String, Object?> body, {
  required String toolName,
  required String? toolInputPreview,
}) {
  if (toolName.trim().isEmpty) return null;
  final preview = toolInputPreview?.trim() ?? '';
  final description = preview.isEmpty ? toolName : '$toolName $preview';

  final always = <AgentPermissionAlwaysOption>[];
  final suggestions = body['permission_suggestions'];
  if (suggestions is List) {
    for (final suggestion in suggestions) {
      if (suggestion is! Map || suggestion['type'] != 'addRules') continue;
      final label = _claudeAddRulesLabel(Map<String, Object?>.from(suggestion));
      if (label.isEmpty) continue;
      always.add(
        AgentPermissionAlwaysOption(
          label: label,
          payload: Map<String, Object?>.from(suggestion),
        ),
      );
    }
  }

  return AgentPermissionRequest(
    id: '',
    description: description,
    patterns: const [],
    always: always,
  );
}

String _claudeAddRulesLabel(Map<String, Object?> suggestion) {
  final rules = suggestion['rules'];
  if (rules is! List || rules.isEmpty || rules.first is! Map) return '';
  final first = Map<String, Object?>.from(rules.first as Map);
  final tool = first['toolName']?.toString().trim() ?? '';
  if (tool.isEmpty) return '';
  final ruleContent = first['ruleContent']?.toString().trim() ?? '';
  return ruleContent.isEmpty ? tool : '$tool($ruleContent)';
}
