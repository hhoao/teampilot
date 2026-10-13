import '../../utils/logging/logger_utils.dart';
import '../chat/team_bus/teammate_bus_permission.dart';

/// Picks an ACP permission option the host can grant without a card.
///
/// Parses options from raw JSON so Cursor hyphen kinds (`allow-always`)
/// work even when typed `RequestPermissionRequest.fromJson` would fail.
///
/// When [allowNonHost] is false, only teammate-bus tool calls are eligible.
/// Prefers allow-always over allow-once. Reject-only options yield null.
String? autoAllowAcpPermissionOptionId(
  Object? params, {
  bool allowNonHost = true,
}) {
  if (params is! Map) return null;
  final map = Map<String, Object?>.from(params);
  final toolCall = _asStringKeyedMap(map['toolCall'] ?? map['tool_call']);
  if (!allowNonHost && !_isTeammateBusToolCall(toolCall)) return null;
  final optionId = _preferredAllowOptionId(map['options']);
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
  for (final item in options) {
    if (item is! Map) continue;
    final option = Map<String, Object?>.from(item);
    final kind = (option['kind'] as String?)?.toLowerCase();
    if (kind == null || _isRejectKind(kind)) continue;
    final id = option['optionId'] ?? option['option_id'] ?? option['id'];
    if (id is! String || id.isEmpty) continue;
    if (_isAllowAlwaysKind(kind)) return id;
    if (allowOnce == null && _isAllowOnceKind(kind)) allowOnce = id;
  }
  return allowOnce;
}

bool _isAllowAlwaysKind(String kind) =>
    kind == 'allow-always' || kind == 'allow_always';

bool _isAllowOnceKind(String kind) =>
    kind == 'allow-once' || kind == 'allow_once';

bool _isRejectKind(String kind) =>
    kind == 'reject-once' ||
    kind == 'reject_once' ||
    kind == 'reject-always' ||
    kind == 'reject_always';

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(value);
}
