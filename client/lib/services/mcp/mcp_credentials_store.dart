import 'dart:convert';

import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'mcp_oauth_server_key.dart';

/// Claude Code secure storage file (`CLAUDE_CONFIG_DIR/.credentials.json`).
class McpCredentialsStore {
  McpCredentialsStore({Filesystem? fs}) : _fs = fs ?? LocalFilesystem();

  final Filesystem _fs;

  static const credentialsFileName = '.credentials.json';

  String credentialsPath(String configDir) =>
      _fs.pathContext.join(configDir, credentialsFileName);

  Future<Map<String, Object?>> read(String configDir) async {
    final path = credentialsPath(configDir);
    final stat = await _fs.stat(path);
    if (!stat.isFile) return {};
    final text = await _fs.readString(path);
    if (text == null || text.trim().isEmpty) return {};
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  Future<void> write(String configDir, Map<String, Object?> data) async {
    final path = credentialsPath(configDir);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  Map<String, Object?>? oauthEntry(
    Map<String, Object?> data,
    String serverKey,
  ) {
    final mcpOAuth = (data['mcpOAuth'] as Map?)?.cast<String, Object?>();
    if (mcpOAuth == null) return null;
    final entry = mcpOAuth[serverKey];
    return entry is Map ? entry.cast<String, Object?>() : null;
  }

  bool hasAccessToken(
    Map<String, Object?> data,
    String serverName,
    Map<String, Object?> serverConfig,
  ) {
    final key = mcpOAuthServerKey(serverName, serverConfig);
    final entry = oauthEntry(data, key);
    final token = entry?['accessToken']?.toString().trim() ?? '';
    return token.isNotEmpty;
  }

  Future<void> clearServerTokens({
    required String configDir,
    required String serverName,
    required Map<String, Object?> serverConfig,
  }) async {
    final data = await read(configDir);
    final mcpOAuth = (data['mcpOAuth'] as Map?)?.cast<String, Object?>();
    if (mcpOAuth == null) return;
    final key = mcpOAuthServerKey(serverName, serverConfig);
    if (!mcpOAuth.containsKey(key)) return;
    mcpOAuth.remove(key);
    data['mcpOAuth'] = mcpOAuth;
    await write(configDir, data);
  }

  Future<void> saveOAuthTokens({
    required String configDir,
    required String serverName,
    required Map<String, Object?> serverConfig,
    required String accessToken,
    String? refreshToken,
    required int expiresAtMs,
    String? scope,
    String? clientId,
    String? clientSecret,
    Map<String, Object?>? discoveryState,
  }) async {
    final data = await read(configDir);
    final mcpOAuth =
        ((data['mcpOAuth'] as Map?)?.cast<String, Object?>() ??
            <String, Object?>{});
    final key = mcpOAuthServerKey(serverName, serverConfig);
    final prev = (mcpOAuth[key] as Map?)?.cast<String, Object?>() ?? {};
    mcpOAuth[key] = {
      ...prev,
      'serverName': serverName,
      'serverUrl': serverConfig['url']?.toString() ?? '',
      'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      'expiresAt': expiresAtMs,
      if (scope != null) 'scope': scope,
      if (clientId != null) 'clientId': clientId,
      if (clientSecret != null) 'clientSecret': clientSecret,
      if (discoveryState != null) 'discoveryState': discoveryState,
    };
    data['mcpOAuth'] = mcpOAuth;
    await write(configDir, data);
  }

  Future<void> saveClientInformation({
    required String configDir,
    required String serverName,
    required Map<String, Object?> serverConfig,
    required String clientId,
    String? clientSecret,
  }) async {
    final data = await read(configDir);
    final mcpOAuth =
        ((data['mcpOAuth'] as Map?)?.cast<String, Object?>() ??
            <String, Object?>{});
    final key = mcpOAuthServerKey(serverName, serverConfig);
    final prev = (mcpOAuth[key] as Map?)?.cast<String, Object?>() ?? {};
    mcpOAuth[key] = {
      ...prev,
      'serverName': serverName,
      'serverUrl': serverConfig['url']?.toString() ?? '',
      'clientId': clientId,
      if (clientSecret != null) 'clientSecret': clientSecret,
      'accessToken': prev['accessToken']?.toString() ?? '',
      'expiresAt': prev['expiresAt'] ?? 0,
    };
    data['mcpOAuth'] = mcpOAuth;
    await write(configDir, data);
  }

  /// Merges app-level OAuth entries into a member [CLAUDE_CONFIG_DIR].
  Future<void> mergeInto({
    required String fromConfigDir,
    required String toConfigDir,
  }) async {
    final from = await read(fromConfigDir);
    final fromOAuth = (from['mcpOAuth'] as Map?)?.cast<String, Object?>();
    if (fromOAuth == null || fromOAuth.isEmpty) return;

    final to = await read(toConfigDir);
    final toOAuth =
        ((to['mcpOAuth'] as Map?)?.cast<String, Object?>() ??
            <String, Object?>{});
    toOAuth.addAll(fromOAuth);
    to['mcpOAuth'] = toOAuth;
    await write(toConfigDir, to);
  }
}
