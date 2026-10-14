import '../../utils/logging/logger_utils.dart';
import '../chat/team_bus/teammate_bus_permission.dart';

/// Picks an ACP permission option the host can grant without a card.
///
/// Parses options from raw JSON so Cursor hyphen kinds (`allow-always`)
/// work even when typed `RequestPermissionRequest.fromJson` would fail.
///
/// When [allowNonHost] is false, only teammate-bus tool calls are eligible.
/// Prefers allow-always over allow-once. Reject-only options yield null.
/// Host MCP with no parseable allow-* kind still takes the first non-reject
/// option so `session/new` does not remember "User rejected MCP".
String? autoAllowAcpPermissionOptionId(
  Object? params, {
  bool allowNonHost = true,
}) {
  if (params is! Map) return null;
  final map = Map<String, Object?>.from(params);
  final toolCall = _asStringKeyedMap(map['toolCall'] ?? map['tool_call']);
  if (!allowNonHost && !_isTeammateBusToolCall(toolCall)) return null;
  var optionId = _preferredAllowOptionId(map['options']);
  optionId ??= _hostMcpLastResortOptionId(map);
  if (optionId == null) return null;
  final title = toolCall?['title'];
  AppLogger.instance.i(
    'ACP: auto-allow permission option=$optionId title=$title',
  );
  return optionId;
}

bool _isTeammateBusToolCall(Map<String, Object?>? toolCall) {
  if (toolCall == null) return false;
  final title = toolCall['title'];
  return isTeammateBusToolCall(
    title: title is String ? title : null,
    rawInput: toolCall['rawInput'] ?? toolCall['raw_input'],
    meta: toolCall['_meta'] ?? toolCall['meta'],
  );
}

String? _preferredAllowOptionId(Object? options) {
  if (options is! List) return null;
  String? allowOnce;
  String? anyAllow;
  for (final item in options) {
    if (item is! Map) continue;
    final option = Map<String, Object?>.from(item);
    final rawKind = option['kind'];
    final kind = rawKind is String
        ? rawKind.toLowerCase().replaceAll('-', '_')
        : '';
    final id = option['optionId'] ?? option['option_id'] ?? option['id'];
    if (id is! String || id.isEmpty) continue;
    final normalizedId = id.toLowerCase().replaceAll('-', '_');
    if (_isRejectKind(kind) || normalizedId.startsWith('reject')) continue;
    if (_isAllowAlwaysKind(kind) || normalizedId == 'allow_always') return id;
    if (_isAllowOnceKind(kind) || normalizedId == 'allow_once') {
      allowOnce ??= id;
      continue;
    }
    if (kind.startsWith('allow') || normalizedId.startsWith('allow')) {
      anyAllow ??= id;
    }
  }
  return allowOnce ?? anyAllow;
}

/// Host teammate-bus MCP: if the agent sent no parseable allow-* kind,
/// still pick the first non-reject option so `session/new` does not
/// remember "User rejected MCP".
String? _hostMcpLastResortOptionId(Map<String, Object?> params) {
  final toolCall = _asStringKeyedMap(params['toolCall'] ?? params['tool_call']);
  if (!_isTeammateBusToolCall(toolCall)) return null;
  return _firstNonRejectOptionId(params['options']);
}

String? _firstNonRejectOptionId(Object? options) {
  if (options is! List) return null;
  for (final item in options) {
    if (item is! Map) continue;
    final option = Map<String, Object?>.from(item);
    final rawKind = option['kind'];
    final kind = rawKind is String ? rawKind.toLowerCase() : '';
    final id = option['optionId'] ?? option['option_id'] ?? option['id'];
    if (id is! String || id.isEmpty) continue;
    if (_isRejectKind(kind) || id.toLowerCase().startsWith('reject')) {
      continue;
    }
    return id;
  }
  return null;
}

bool _isAllowAlwaysKind(String kind) =>
    kind.contains('allow_always') || kind == 'allow-always';

bool _isAllowOnceKind(String kind) =>
    kind.contains('allow_once') || kind == 'allow-once';

bool _isRejectKind(String kind) =>
    kind.contains('reject');

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(value);
}

/// Copies [params] with option `kind` hyphens rewritten to underscores.
///
/// Cursor sends `allow-always` / `allow-once`; acpd's typed
/// `RequestPermissionRequest.fromJson` only accepts `allow_always`.
Map<String, Object?> normalizeAcpPermissionOptionKinds(
  Map<String, Object?> params,
) {
  final options = params['options'];
  if (options is! List) return Map<String, Object?>.from(params);
  return {
    ...params,
    'options': [
      for (final item in options) _normalizePermissionOptionKind(item),
    ],
  };
}

Object? _normalizePermissionOptionKind(Object? item) {
  if (item is! Map) return item;
  final option = Map<String, Object?>.from(item);
  final kind = option['kind'];
  if (kind is String) {
    option['kind'] = kind.replaceAll('-', '_');
  }
  return option;
}
