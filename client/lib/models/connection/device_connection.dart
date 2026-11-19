import 'package:flutter/foundation.dart';

import '../ssh_reachability.dart';
import 'machine_id.dart';
import 'ssh_plan.dart';

/// Where the home plane's data lives on a machine, remembered from the last
/// successful resolve so a cold start with sshd down can still paint.
@immutable
final class HomePathCache {
  const HomePathCache({required this.home, required this.appDataRoot});

  final String home;
  final String appDataRoot;

  Map<String, Object?> toJson() => {'home': home, 'appDataRoot': appDataRoot};

  @override
  bool operator ==(Object other) =>
      other is HomePathCache &&
      home == other.home &&
      appDataRoot == other.appDataRoot;

  @override
  int get hashCode => Object.hash(home, appDataRoot);
}

/// A device-owned connection record: the only thing in the system that may be
/// dialed.
///
/// [preferredKind] is the last endpoint kind that worked. It is a preference
/// (dial order), not part of the plan, so changing it never invalidates a live
/// lease.
@immutable
final class DeviceConnection {
  const DeviceConnection({
    required this.machineId,
    required this.displayName,
    required this.plan,
    this.preferredKind,
    this.paths,
    this.pairedDesktopId,
    this.updatedAt = 0,
  });

  factory DeviceConnection.fromJson(Map<String, Object?> json) {
    final plan = SshPlan.fromJson(
      (json['plan'] as Map? ?? const {}).cast<String, Object?>(),
    );
    final paths = json['paths'];
    return DeviceConnection(
      machineId: MachineId(json['machineId'] as String? ?? ''),
      displayName: json['displayName'] as String? ?? '',
      plan: plan,
      preferredKind: SshEndpointKind.values
          .where((value) => value.name == json['preferredKind'])
          .firstOrNull,
      paths: paths is Map
          ? HomePathCache(
              home: paths['home'] as String? ?? '',
              appDataRoot: paths['appDataRoot'] as String? ?? '',
            )
          : null,
      pairedDesktopId: json['pairedDesktopId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final MachineId machineId;
  final String displayName;
  final SshPlan plan;

  /// Last winning endpoint kind; drives dial order only.
  final SshEndpointKind? preferredKind;

  /// Persisted remote home/app-data paths (see [HomePathCache]).
  final HomePathCache? paths;

  final String? pairedDesktopId;
  final int updatedAt;

  int get generation => plan.generation;

  /// The endpoint the rest of the app still speaks in terms of (`host`/`port`).
  ///
  /// Falls back to the first endpoint, which is why a plan must never be empty:
  /// there is always a concrete address to show and to hand to a dialer.
  SshReachabilityEndpoint get primaryEndpoint {
    final preferred = preferredKind;
    if (preferred != null) {
      for (final endpoint in plan.endpoints) {
        if (endpoint.kind == preferred) return endpoint;
      }
    }
    return plan.endpoints.first;
  }

  DeviceConnection copyWith({
    String? displayName,
    SshPlan? plan,
    SshEndpointKind? preferredKind,
    HomePathCache? paths,
    String? pairedDesktopId,
    int? updatedAt,
  }) => DeviceConnection(
    machineId: machineId,
    displayName: displayName ?? this.displayName,
    plan: plan ?? this.plan,
    preferredKind: preferredKind ?? this.preferredKind,
    paths: paths ?? this.paths,
    pairedDesktopId: pairedDesktopId ?? this.pairedDesktopId,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'machineId': machineId.value,
    'displayName': displayName,
    'plan': plan.toJson(),
    if (preferredKind != null) 'preferredKind': preferredKind!.name,
    if (paths != null) 'paths': paths!.toJson(),
    if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
    'updatedAt': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceConnection &&
          machineId == other.machineId &&
          displayName == other.displayName &&
          plan == other.plan &&
          preferredKind == other.preferredKind &&
          paths == other.paths &&
          pairedDesktopId == other.pairedDesktopId &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    machineId,
    displayName,
    plan,
    preferredKind,
    paths,
    pairedDesktopId,
    updatedAt,
  );
}
