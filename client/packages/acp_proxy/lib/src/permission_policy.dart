import 'launch_meta.dart';

/// How long a disconnected permission or human question stays open.
const acpProxyPermissionTimeout = Duration(hours: 24);

/// What to do with `session/request_permission` while the phone is gone.
enum DisconnectedPermissionAction { autoAllow, hold }

/// `fullAccess` auto-allows. `ask` holds for [acpProxyPermissionTimeout].
DisconnectedPermissionAction permissionActionWhenDisconnected(
  AcpProxyPermissionPolicy policy,
) {
  return switch (policy) {
    AcpProxyPermissionPolicy.fullAccess =>
      DisconnectedPermissionAction.autoAllow,
    AcpProxyPermissionPolicy.ask => DisconnectedPermissionAction.hold,
  };
}

/// Allow option id for a disconnected `fullAccess` permission request.
///
/// Kinds and ids are lowercased and hyphens become underscores. Reject
/// options are skipped. Prefer allow-always, then allow-once, then any id
/// whose kind or id starts with `allow`. Returns null when nothing can be
/// granted. Does not log and does not take a non-allow last resort.
String? preferredAllowOptionId(Object? options) {
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

bool _isAllowAlwaysKind(String kind) =>
    kind.contains('allow_always') || kind == 'allow-always';

bool _isAllowOnceKind(String kind) =>
    kind.contains('allow_once') || kind == 'allow-once';

bool _isRejectKind(String kind) => kind.contains('reject');
