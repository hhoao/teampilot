import 'hlc.dart';

/// One device's own ordered lane (open tabs, recents, ...).
///
/// Lanes are written only by their owner device, so a same-device conflict is
/// resolved by the later stamp. Different devices never overwrite each other.
final class DeviceLane<T> {
  const DeviceLane({this.items = const [], this.active, required this.stamp});

  final List<T> items;
  final String? active;
  final Hlc stamp;

  DeviceLane<T> replace({
    required List<T> nextItems,
    String? nextActive,
    required Hlc nextStamp,
  }) => DeviceLane<T>(
    items: List<T>.unmodifiable(nextItems),
    active: nextActive,
    stamp: nextStamp,
  );

  DeviceLane<T> merge(DeviceLane<T> other) =>
      other.stamp.compareTo(stamp) > 0 ? other : this;

  Map<String, Object?> toJson(Object? Function(T item) encode) => {
    'items': items.map(encode).toList(),
    'active': active,
    't': stamp.toJson(),
  };

  static DeviceLane<T>? fromJson<T>(
    Object? json, {
    required T Function(Object? value) decode,
  }) {
    if (json is! Map) return null;
    final stamp = Hlc.fromJson(json['t']);
    if (stamp == null) return null;
    final raw = json['items'];
    final items = <T>[];
    if (raw is List) {
      for (final item in raw) {
        try {
          items.add(decode(item));
        } on Object {
          // Skip a single unreadable entry, keep the rest of the lane.
        }
      }
    }
    final active = json['active'];
    return DeviceLane<T>(
      items: List<T>.unmodifiable(items),
      active: active is String && active.trim().isNotEmpty
          ? active.trim()
          : null,
      stamp: stamp,
    );
  }
}

/// Per-device lanes merged independently.
///
/// [unionItems] is the view most callers want for "what is open anywhere":
/// every device's lane, de-duplicated, in deterministic device-id order.
final class DeviceLanes<T> {
  const DeviceLanes({this.byDevice = const {}});

  final Map<String, DeviceLane<T>> byDevice;

  DeviceLanes<T> put(String deviceId, DeviceLane<T> lane) {
    final key = deviceId.trim();
    if (key.isEmpty) return this;
    return DeviceLanes<T>(byDevice: {...byDevice, key: lane});
  }

  DeviceLanes<T> merge(DeviceLanes<T> other) {
    final merged = <String, DeviceLane<T>>{...byDevice};
    for (final entry in other.byDevice.entries) {
      final local = merged[entry.key];
      merged[entry.key] = local == null
          ? entry.value
          : local.merge(entry.value);
    }
    return DeviceLanes<T>(byDevice: merged);
  }

  List<T> itemsFor(String deviceId) =>
      byDevice[deviceId.trim()]?.items ?? const [];

  String? activeFor(String deviceId) => byDevice[deviceId.trim()]?.active;

  List<T> get unionItems {
    final seen = <T>{};
    final out = <T>[];
    final deviceIds = byDevice.keys.toList()..sort();
    for (final deviceId in deviceIds) {
      for (final item in byDevice[deviceId]!.items) {
        if (seen.add(item)) out.add(item);
      }
    }
    return out;
  }

  Map<String, Object?> toJson(Object? Function(T item) encode) {
    final deviceIds = byDevice.keys.toList()..sort();
    return {
      'devices': {
        for (final deviceId in deviceIds)
          deviceId: byDevice[deviceId]!.toJson(encode),
      },
    };
  }

  static DeviceLanes<T> fromJson<T>(
    Object? json, {
    required T Function(Object? value) decode,
  }) {
    if (json is! Map) return DeviceLanes<T>();
    final raw = json['devices'];
    if (raw is! Map) return DeviceLanes<T>();
    final byDevice = <String, DeviceLane<T>>{};
    for (final entry in raw.entries) {
      final deviceId = entry.key.toString().trim();
      if (deviceId.isEmpty) continue;
      final lane = DeviceLane.fromJson<T>(entry.value, decode: decode);
      if (lane != null) byDevice[deviceId] = lane;
    }
    return DeviceLanes<T>(byDevice: byDevice);
  }
}
