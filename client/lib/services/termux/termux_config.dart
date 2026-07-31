import 'package:flutter/foundation.dart';

@immutable
class TermuxConfig {
  const TermuxConfig({
    required this.username,
    this.host = '127.0.0.1',
    this.port = 8022,
    this.lastHome,
    this.lastAppDataRoot,
  });

  factory TermuxConfig.fromJson(Map<String, Object?> json) {
    return TermuxConfig(
      username: json['username'] as String? ?? '',
      host: json['host'] as String? ?? '127.0.0.1',
      port: (json['port'] as num?)?.toInt() ?? 8022,
      lastHome: json['lastHome'] as String?,
      lastAppDataRoot: json['lastAppDataRoot'] as String?,
    );
  }

  final String username;
  final String host;
  final int port;
  final String? lastHome;
  final String? lastAppDataRoot;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'username': username,
      'host': host,
      'port': port,
      if (lastHome != null) 'lastHome': lastHome,
      if (lastAppDataRoot != null) 'lastAppDataRoot': lastAppDataRoot,
    };
  }

  TermuxConfig copyWith({
    String? username,
    String? host,
    int? port,
    String? lastHome,
    String? lastAppDataRoot,
  }) {
    return TermuxConfig(
      username: username ?? this.username,
      host: host ?? this.host,
      port: port ?? this.port,
      lastHome: lastHome ?? this.lastHome,
      lastAppDataRoot: lastAppDataRoot ?? this.lastAppDataRoot,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TermuxConfig &&
            username == other.username &&
            host == other.host &&
            port == other.port &&
            lastHome == other.lastHome &&
            lastAppDataRoot == other.lastAppDataRoot;
  }

  @override
  int get hashCode =>
      Object.hash(username, host, port, lastHome, lastAppDataRoot);
}
