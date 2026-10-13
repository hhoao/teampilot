import '../../utils/logging/logger.dart';

/// Auto-allows ACP `session/request_permission` (fullAccess).
///
/// PTY already maps `LaunchSecurityPolicy.fullAccess` to skip-permission
/// flags (`--force`, `--dangerously-skip-permissions`, …). ACP has no TUI
/// flag path: the agent asks the client, and mixed teams cannot click a card
/// per member. Prefer allow-always so the agent remembers the grant.
///
/// Reads options from the raw JSON-RPC map. Cursor sends hyphenated kinds
/// (`allow-once`) that acpd's `PermissionOptionKind` rejects, so a typed
/// parse would skip every allow option and fall through to a card / cancel.
String? autoAllowAcpPermissionOptionId(Object? params) {
  if (params is! Map) return null;
  final optionId = firstAllowPermissionOptionIdFromRaw(params);
  if (optionId == null) return null;
  AppLogger.instance.i(
    '[acp] auto-allow ${_toolCallTitle(params) ?? optionId}',
  );
  return optionId;
}

/// Prefer allow-always so the agent remembers the grant for the session.
///
/// Accepts hyphen or underscore kinds (`allow-always` / `allow_always`) and
/// `optionId` / `option_id` / `id` keys so a Cursor or schema-skew payload
/// still auto-allows.
String? firstAllowPermissionOptionIdFromRaw(Object? params) {
  if (params is! Map) return null;
  final options = params['options'];
  if (options is! List) return null;
  String? allowOnce;
  String? anyAllow;
  for (final item in options) {
    if (item is! Map) continue;
    final map = Map<Object?, Object?>.from(item);
    final id = _nonEmptyString(map['optionId'] ?? map['option_id'] ?? map['id']);
    if (id == null) continue;
    final kind = _normalize(_nonEmptyString(map['kind']) ?? '');
    final normalizedId = _normalize(id);
    if (kind.contains('reject') || normalizedId.startsWith('reject')) {
      continue;
    }
    if (kind.contains('allow_always') || normalizedId == 'allow_always') {
      return id;
    }
    if (kind.contains('allow_once') || normalizedId == 'allow_once') {
      allowOnce ??= id;
      continue;
    }
    if (kind.startsWith('allow') || normalizedId.startsWith('allow')) {
      anyAllow ??= id;
    }
  }
  return allowOnce ?? anyAllow;
}

String _normalize(String value) => value.toLowerCase().replaceAll('-', '_');

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _toolCallTitle(Map<dynamic, dynamic> params) {
  final toolCall = params['toolCall'] ?? params['tool_call'];
  if (toolCall is! Map) return null;
  return _nonEmptyString(toolCall['title']);
}
