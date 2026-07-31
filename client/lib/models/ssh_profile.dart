import 'package:flutter/foundation.dart';

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
    };
  }

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
            lastAppDataRoot == other.lastAppDataRoot;
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
  );
}
