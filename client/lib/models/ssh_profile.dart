import 'package:flutter/foundation.dart';

import 'ssh_reachability.dart';

enum SshAuthType { password, privateKey }

@immutable
class SshProfile {
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastHome,
    this.lastAppDataRoot,
    this.endpoints = const [],
    this.hostKeyFingerprints = const [],
    this.pairedDesktopId,
    this.relayUrl,
    this.lastGoodKind,
  });

  factory SshProfile.fromJson(Map<String, Object?> json) {
    final authRaw = json['authType'] as String? ?? 'password';
    final auth = SshAuthType.values.firstWhere(
      (e) => e.name == authRaw,
      orElse: () => SshAuthType.password,
    );
    return SshProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      authType: auth,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      lastHome: json['lastHome'] as String?,
      lastAppDataRoot: json['lastAppDataRoot'] as String?,
      endpoints:
          (json['endpoints'] as List?)
              ?.whereType<Map>()
              .map(
                (value) => SshReachabilityEndpoint.tryParse(
                  value.cast<String, Object?>(),
                ),
              )
              .whereType<SshReachabilityEndpoint>()
              .toList(growable: false) ??
          const [],
      hostKeyFingerprints:
          (json['hostKeyFingerprints'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      pairedDesktopId: json['pairedDesktopId'] as String?,
      relayUrl: json['relayUrl'] as String?,
      lastGoodKind: SshEndpointKind.values
          .where((value) => value.name == json['lastGoodKind'])
          .firstOrNull,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final int createdAt;
  final int updatedAt;
  final String? lastHome;
  final String? lastAppDataRoot;
  final List<SshReachabilityEndpoint> endpoints;
  final List<String> hostKeyFingerprints;
  final String? pairedDesktopId;
  final String? relayUrl;
  final SshEndpointKind? lastGoodKind;

  String get hostIdentifier => '$username@$host:$port';

  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    int? createdAt,
    int? updatedAt,
    String? lastHome,
    String? lastAppDataRoot,
    List<SshReachabilityEndpoint>? endpoints,
    List<String>? hostKeyFingerprints,
    String? pairedDesktopId,
    String? relayUrl,
    SshEndpointKind? lastGoodKind,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastHome: lastHome ?? this.lastHome,
      lastAppDataRoot: lastAppDataRoot ?? this.lastAppDataRoot,
      endpoints: endpoints ?? this.endpoints,
      hostKeyFingerprints: hostKeyFingerprints ?? this.hostKeyFingerprints,
      pairedDesktopId: pairedDesktopId ?? this.pairedDesktopId,
      relayUrl: relayUrl ?? this.relayUrl,
      lastGoodKind: lastGoodKind ?? this.lastGoodKind,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (lastHome != null) 'lastHome': lastHome,
      if (lastAppDataRoot != null) 'lastAppDataRoot': lastAppDataRoot,
      if (endpoints.isNotEmpty)
        'endpoints': endpoints.map((endpoint) => endpoint.toJson()).toList(),
      if (hostKeyFingerprints.isNotEmpty)
        'hostKeyFingerprints': hostKeyFingerprints,
      if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
      if (relayUrl != null) 'relayUrl': relayUrl,
      if (lastGoodKind != null) 'lastGoodKind': lastGoodKind!.name,
    };
  }

  /// Includes [lastHome]/[lastAppDataRoot] so Bloc/Equatable emits after path
  /// cache updates. Home storage invalidation uses
  /// [sshHomeConnectionFingerprint], not `==`.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SshProfile &&
            id == other.id &&
            name == other.name &&
            host == other.host &&
            port == other.port &&
            username == other.username &&
            authType == other.authType &&
            lastHome == other.lastHome &&
            lastAppDataRoot == other.lastAppDataRoot &&
            listEquals(endpoints, other.endpoints) &&
            listEquals(hostKeyFingerprints, other.hostKeyFingerprints) &&
            pairedDesktopId == other.pairedDesktopId &&
            relayUrl == other.relayUrl &&
            lastGoodKind == other.lastGoodKind;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    host,
    port,
    username,
    authType,
    lastHome,
    lastAppDataRoot,
    Object.hashAll(endpoints),
    Object.hashAll(hostKeyFingerprints),
    pairedDesktopId,
    relayUrl,
    lastGoodKind,
  );
}
