import 'package:flutter/foundation.dart';

import 'ssh_auth_type.dart';

/// The remote half of an SSH connection: the full configuration for a server,
/// stored on the current home plane so every paired device sees the same set.
///
/// Credentials are deliberately absent — the profile names a vault entry (see
/// `RemoteTarget`) and never carries a password or private key, because this
/// record is written to, and read from, a machine the user may not control.
@immutable
class SshServerProfile {
  const SshServerProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.embeddedTarget = false,
    this.relayUrl,
    this.pairedDesktopId,
    this.updatedAt = 0,
  });

  factory SshServerProfile.fromJson(Map<String, Object?> json) {
    final authRaw = json['authType'] as String? ?? 'password';
    return SshServerProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (e) => e.name == authRaw,
        orElse: () => SshAuthType.password,
      ),
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
  final bool embeddedTarget;
  final String? relayUrl;
  final String? pairedDesktopId;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'authType': authType.name,
    if (embeddedTarget) 'embeddedTarget': embeddedTarget,
    if (relayUrl != null) 'relayUrl': relayUrl,
    if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
    'updatedAt': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshServerProfile &&
          id == other.id &&
          name == other.name &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authType == other.authType &&
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
    embeddedTarget,
    relayUrl,
    pairedDesktopId,
    updatedAt,
  );
}
