import 'package:flutter/foundation.dart';

import 'ssh_auth_type.dart';
import 'ssh_reachability.dart';

@immutable
class RemoteTarget {
  const RemoteTarget({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.vaultEntryId,
    this.endpoints = const [],
    this.hostKeyFingerprints = const [],
    this.lastGoodKind,
    this.lastHome,
    this.lastAppDataRoot,
    this.embeddedTarget = false,
    this.relayUrl,
    this.pairedDesktopId,
    this.updatedAt = 0,
  });

  factory RemoteTarget.fromJson(Map<String, Object?> json) {
    final authRaw = json['authType'] as String? ?? 'password';
    return RemoteTarget(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (e) => e.name == authRaw,
        orElse: () => SshAuthType.password,
      ),
      vaultEntryId: json['vaultEntryId']?.toString(),
      endpoints:
          (json['endpoints'] as List?)
              ?.whereType<Map>()
              .map(
                (v) =>
                    SshReachabilityEndpoint.tryParse(v.cast<String, Object?>()),
              )
              .whereType<SshReachabilityEndpoint>()
              .toList(growable: false) ??
          const [],
      hostKeyFingerprints:
          (json['hostKeyFingerprints'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      lastGoodKind: SshEndpointKind.values
          .where((v) => v.name == json['lastGoodKind'])
          .firstOrNull,
      lastHome: json['lastHome'] as String?,
      lastAppDataRoot: json['lastAppDataRoot'] as String?,
      embeddedTarget: json['embeddedTarget'] is bool
          ? json['embeddedTarget'] as bool
          : false,
      relayUrl: json['relayUrl'] as String?,
      pairedDesktopId: json['pairedDesktopId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final String? vaultEntryId;
  final List<SshReachabilityEndpoint> endpoints;
  final List<String> hostKeyFingerprints;
  final SshEndpointKind? lastGoodKind;
  final String? lastHome;
  final String? lastAppDataRoot;
  final bool embeddedTarget;
  final String? relayUrl;
  final String? pairedDesktopId;
  final int updatedAt;

  String get hostIdentifier => '$username@$host:$port';

  RemoteTarget copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? vaultEntryId,
    List<SshReachabilityEndpoint>? endpoints,
    List<String>? hostKeyFingerprints,
    SshEndpointKind? lastGoodKind,
    String? lastHome,
    String? lastAppDataRoot,
    bool? embeddedTarget,
    String? relayUrl,
    String? pairedDesktopId,
    int? updatedAt,
  }) {
    return RemoteTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      vaultEntryId: vaultEntryId ?? this.vaultEntryId,
      endpoints: endpoints ?? this.endpoints,
      hostKeyFingerprints: hostKeyFingerprints ?? this.hostKeyFingerprints,
      lastGoodKind: lastGoodKind ?? this.lastGoodKind,
      lastHome: lastHome ?? this.lastHome,
      lastAppDataRoot: lastAppDataRoot ?? this.lastAppDataRoot,
      embeddedTarget: embeddedTarget ?? this.embeddedTarget,
      relayUrl: relayUrl ?? this.relayUrl,
      pairedDesktopId: pairedDesktopId ?? this.pairedDesktopId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'authType': authType.name,
    if (vaultEntryId != null) 'vaultEntryId': vaultEntryId,
    if (endpoints.isNotEmpty)
      'endpoints': endpoints.map((e) => e.toJson()).toList(),
    if (hostKeyFingerprints.isNotEmpty)
      'hostKeyFingerprints': hostKeyFingerprints,
    if (lastGoodKind != null) 'lastGoodKind': lastGoodKind!.name,
    if (lastHome != null) 'lastHome': lastHome,
    if (lastAppDataRoot != null) 'lastAppDataRoot': lastAppDataRoot,
    if (embeddedTarget) 'embeddedTarget': embeddedTarget,
    if (relayUrl != null) 'relayUrl': relayUrl,
    if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
    'updatedAt': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteTarget &&
          id == other.id &&
          name == other.name &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authType == other.authType &&
          vaultEntryId == other.vaultEntryId &&
          listEquals(endpoints, other.endpoints) &&
          listEquals(hostKeyFingerprints, other.hostKeyFingerprints) &&
          lastGoodKind == other.lastGoodKind &&
          lastHome == other.lastHome &&
          lastAppDataRoot == other.lastAppDataRoot &&
          embeddedTarget == other.embeddedTarget &&
          relayUrl == other.relayUrl &&
          pairedDesktopId == other.pairedDesktopId &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    host,
    port,
    username,
    authType,
    vaultEntryId,
    Object.hashAll(endpoints),
    Object.hashAll(hostKeyFingerprints),
    lastGoodKind,
    lastHome,
    lastAppDataRoot,
    embeddedTarget,
    relayUrl,
    pairedDesktopId,
    updatedAt,
  );
}
