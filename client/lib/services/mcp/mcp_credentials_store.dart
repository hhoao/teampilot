import 'dart:convert';

import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'mcp_oauth_server_key.dart';

/// Claude Code secure storage file (`CLAUDE_CONFIG_DIR/.credentials.json`).
class McpCredentialsStore {
  McpCredentialsStore({Filesystem? fs}) : _fs = fs ?? LocalFilesystem();

  final Filesystem _fs;

  static const credentialsFileName = '.credentials.json';

  /// Session-local env vars for MCP OAuth bearer tokens (codex `bearer_token_env_var`).
  static const oauthEnvFileName = '.mcp-oauth.env.json';

  String credentialsPath(String configDir) =>
      _fs.pathContext.join(configDir, credentialsFileName);

  String oauthEnvPath(String configDir) =>
      _fs.pathContext.join(configDir, oauthEnvFileName);

  /// Env-var name codex reads via `bearer_token_env_var`.
  static String bearerTokenEnvVarName(String serverName) {
    final sanitized = serverName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .toUpperCase();
    final suffix = sanitized.isEmpty ? 'SERVER' : sanitized;
    return 'TEAMPILOT_MCP_BEARER_$suffix';
  }

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
    String? fallbackFromConfigDir,
  }) async {
    final fromOAuth = await _readOAuthEntries(
      fromConfigDir,
      fallbackConfigDir: fallbackFromConfigDir,
    );
    if (fromOAuth.isEmpty) return;

    final to = await read(toConfigDir);
    final toOAuth =
        ((to['mcpOAuth'] as Map?)?.cast<String, Object?>() ??
            <String, Object?>{});
    toOAuth.addAll(fromOAuth);
    to['mcpOAuth'] = toOAuth;
    await write(toConfigDir, to);
  }

  /// Copies OAuth access tokens into [oauthEnvFileName] for env-var indirection.
  ///
  /// Returns server name → env var name for callers that update native MCP config.
  Future<Map<String, String>> mergeOAuthEnvInto({
    required String fromConfigDir,
    required String toConfigDir,
    String? fallbackFromConfigDir,
  }) async {
    final fromOAuth = await _readOAuthEntries(
      fromConfigDir,
      fallbackConfigDir: fallbackFromConfigDir,
    );
    if (fromOAuth.isEmpty) return const {};

    final existing = await readOAuthEnv(toConfigDir);
    final merged = <String, String>{...existing};
    final serverEnvVars = <String, String>{};

    for (final entry in fromOAuth.values) {
      if (entry is! Map) continue;
      final oauth = entry.cast<String, Object?>();
      final serverName = oauth['serverName']?.toString().trim() ?? '';
      final accessToken = oauth['accessToken']?.toString().trim() ?? '';
      if (serverName.isEmpty || accessToken.isEmpty) continue;

      final envVar = bearerTokenEnvVarName(serverName);
      merged[envVar] = accessToken;
      serverEnvVars[serverName] = envVar;
    }

    if (serverEnvVars.isEmpty) return const {};

    final path = oauthEnvPath(toConfigDir);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
    return serverEnvVars;
  }

  Future<Map<String, String>> readOAuthEnv(String configDir) async {
    final path = oauthEnvPath(configDir);
    final stat = await _fs.stat(path);
    if (!stat.isFile) return const {};
    final text = await _fs.readString(path);
    if (text == null || text.trim().isEmpty) return const {};
    final decoded = (jsonDecode(text) as Map).cast<String, Object?>();
    return {
      for (final entry in decoded.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }

  Future<Map<String, Object?>> _readOAuthEntries(
    String primaryConfigDir, {
    String? fallbackConfigDir,
  }) async {
    final primaryData = await read(primaryConfigDir);
    final primary =
        (primaryData['mcpOAuth'] as Map?)?.cast<String, Object?>();
    if (primary != null && primary.isNotEmpty) return primary;

    final fallbackDir = fallbackConfigDir?.trim() ?? '';
    if (fallbackDir.isEmpty || fallbackDir == primaryConfigDir.trim()) {
      return const {};
    }
    final fallbackData = await read(fallbackDir);
    return (fallbackData['mcpOAuth'] as Map?)?.cast<String, Object?>() ??
        const {};
  }
}
