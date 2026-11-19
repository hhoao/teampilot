import 'package:flutter/foundation.dart';

import '../ssh_auth_type.dart';
import '../ssh_reachability.dart';
import 'machine_id.dart';

/// How this device reaches one machine over SSH.
///
/// A plan is device-private and always describes a live transport: it carries
/// the address set, the account, the credential reference and the trust policy.
/// It never leaves the device and never travels on the home plane.
///
/// [generation] is derived from the plan's address/account/trust fields, so
/// writing anything outside those (display name, path cache, last-good
/// preference) cannot invalidate a live lease, while an address or account
/// change does.
@immutable
final class SshPlan {
  SshPlan({
    required this.machineId,
    required this.username,
    this.authType = SshAuthType.password,
    required List<SshReachabilityEndpoint> endpoints,
    this.relayUrl,
    this.hostKeyFingerprints = const [],
    this.embeddedTarget = false,
    this.credentialRef,
  }) : assert(endpoints.isNotEmpty, 'an SSH plan needs at least one endpoint'),
       endpoints = List.unmodifiable(endpoints),
       generation = _generationOf(
         username: username,
         authType: authType,
         endpoints: endpoints,
         relayUrl: relayUrl,
         hostKeyFingerprints: hostKeyFingerprints,
         embeddedTarget: embeddedTarget,
       );

  factory SshPlan.fromJson(Map<String, Object?> json) {
    final endpoints = (json['endpoints'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              SshReachabilityEndpoint.tryParse(value.cast<String, Object?>()),
        )
        .whereType<SshReachabilityEndpoint>()
        .toList(growable: false);
    if (endpoints.isEmpty) {
      throw FormatException('SSH plan has no endpoints', json);
    }
    return SshPlan(
      machineId: MachineId(json['machineId'] as String? ?? ''),
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (value) => value.name == json['authType'],
        orElse: () => SshAuthType.password,
      ),
      endpoints: endpoints,
      relayUrl: json['relayUrl'] as String?,
      hostKeyFingerprints:
          (json['hostKeyFingerprints'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      embeddedTarget: json['embeddedTarget'] is bool
          ? json['embeddedTarget'] as bool
          : false,
      credentialRef: json['credentialRef'] as String?,
    );
  }

  final MachineId machineId;
  final String username;
  final SshAuthType authType;
  final List<SshReachabilityEndpoint> endpoints;
  final String? relayUrl;
  final List<String> hostKeyFingerprints;
  final bool embeddedTarget;

  /// Vault entry that holds this machine's secret. Deliberately excluded from
  /// [generation]: rotating a secret must not drain live sessions.
  final String? credentialRef;

  /// Content hash of the plan. Persisted, therefore stable across runs.
  final int generation;

  Map<String, Object?> toJson() => {
    'machineId': machineId.value,
    'username': username,
    'authType': authType.name,
    'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
    if (relayUrl != null) 'relayUrl': relayUrl,
    if (hostKeyFingerprints.isNotEmpty)
      'hostKeyFingerprints': hostKeyFingerprints,
    if (credentialRef != null) 'credentialRef': credentialRef,
    if (embeddedTarget) 'embeddedTarget': embeddedTarget,
    'generation': generation,
  };

  SshPlan withCredentialRef(String? credentialRef) => SshPlan(
    machineId: machineId,
    username: username,
    authType: authType,
    endpoints: endpoints,
    relayUrl: relayUrl,
    hostKeyFingerprints: hostKeyFingerprints,
    embeddedTarget: embeddedTarget,
    credentialRef: credentialRef,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshPlan &&
          machineId == other.machineId &&
          generation == other.generation &&
          credentialRef == other.credentialRef;

  @override
  int get hashCode => Object.hash(machineId, generation, credentialRef);
}

/// FNV-1a over a canonical, order-insensitive rendering of the plan.
///
/// Endpoints are sorted because dial order is a preference (last-good), not
/// part of the plan: reordering the same address set must not invalidate a
/// lease mid-session.
int _generationOf({
  required String username,
  required SshAuthType authType,
  required List<SshReachabilityEndpoint> endpoints,
  required String? relayUrl,
  required List<String> hostKeyFingerprints,
  required bool embeddedTarget,
}) {
  final addresses =
      endpoints
          .map(
            (endpoint) =>
                '${endpoint.kind.name}@${endpoint.host}:${endpoint.port}',
          )
          .toList()
        ..sort();
  final pins = [...hostKeyFingerprints]..sort();
  final canonical = [
    username,
    authType.name,
    embeddedTarget ? 'embedded' : 'sshd',
    relayUrl ?? '',
    addresses.join(','),
    pins.join(','),
  ].join('|');
  var hash = 0x811c9dc5;
  for (final unit in canonical.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash == 0 ? 1 : hash;
}
