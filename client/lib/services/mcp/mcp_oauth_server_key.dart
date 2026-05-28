import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Matches Claude Code [`getServerKey`](https://github.com/anthropics/claude-code).
String mcpOAuthServerKey(
  String serverName,
  Map<String, Object?> serverConfig,
) {
  final configJson = jsonEncode(_configJsonForHash(serverConfig));
  final hash = sha256
      .convert(utf8.encode(configJson))
      .toString()
      .substring(0, 16);
  return '$serverName|$hash';
}

/// Same field order as Claude Code: `type`, `url`, `headers` (default `{}`).
Map<String, Object?> _configJsonForHash(Map<String, Object?> serverConfig) {
  final rawHeaders = serverConfig['headers'];
  final headers = <String, Object?>{};
  if (rawHeaders is Map) {
    for (final entry in rawHeaders.entries) {
      headers[entry.key.toString()] = entry.value;
    }
  }
  return {
    'type': serverConfig['type'],
    'url': serverConfig['url'],
    'headers': headers,
  };
}

bool mcpServerNeedsOAuthConnect(Map<String, Object?> server) {
  final type = server['type']?.toString().trim().toLowerCase() ?? '';
  return type == 'http' || type == 'sse' || type == 'streamable-http';
}
