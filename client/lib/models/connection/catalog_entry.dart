import 'package:flutter/foundation.dart';

import 'machine_id.dart';

/// What the home plane knows about a machine.
///
/// Deliberately carries **no reachability**: no host, port, account, credential
/// or trust anchor. Those belong to the device-owned connection. A catalog
/// entry therefore cannot be dialed, which is what keeps "the plane says this
/// machine exists" from being mistaken for "this device can reach it".
@immutable
final class CatalogEntry {
  const CatalogEntry({
    required this.machineId,
    required this.displayName,
    this.updatedAt = 0,
  });

  factory CatalogEntry.fromJson(Map<String, Object?> json) => CatalogEntry(
    machineId: MachineId(json['machineId'] as String? ?? ''),
    displayName: json['displayName'] as String? ?? '',
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );

  final MachineId machineId;
  final String displayName;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'machineId': machineId.value,
    'displayName': displayName,
    'updatedAt': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogEntry &&
          machineId == other.machineId &&
          displayName == other.displayName &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(machineId, displayName, updatedAt);
}
