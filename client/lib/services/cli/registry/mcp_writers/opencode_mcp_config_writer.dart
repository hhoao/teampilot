import 'dart:convert';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../capabilities/mcp_config_writer_capability.dart';
import '../config_profile/opencode_config_profile_capability.dart';

/// Merges MCP servers into `<configDir>/opencode.json` `mcp` map.
final class OpencodeMcpConfigWriter implements McpConfigWriterCapability {
  const OpencodeMcpConfigWriter();

  static const configFileName =
      OpencodeConfigProfileCapability.opencodeConfigFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
  }) async {
    final configPath = fs.pathContext.join(configDir, configFileName);
    final stat = await fs.stat(configPath);
    Map<String, Object?> existing;
    if (stat.isFile) {
      final text = await fs.readString(configPath);
      existing = text == null || text.trim().isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }

    final mergedMcp = <String, Object?>{
      ...((existing['mcp'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
      ..._opencodeMcpMap(servers),
    };
    existing['mcp'] = mergedMcp;

    await fs.ensureDir(fs.pathContext.dirname(configPath));
    await fs.atomicWrite(
      configPath,
      const JsonEncoder.withIndent('  ').convert(existing),
    );
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {
    final store = McpCredentialsStore(fs: fs);
    final oauthEntries = await _readOAuthEntries(
      store,
      appConfigDir,
      fallbackAppConfigDir: fallbackAppConfigDir,
    );
    if (oauthEntries.isEmpty) return;

    final configPath = fs.pathContext.join(sessionConfigDir, configFileName);
    final stat = await fs.stat(configPath);
    if (!stat.isFile) return;

    final text = await fs.readString(configPath);
    if (text == null || text.trim().isEmpty) return;

    final existing = (jsonDecode(text) as Map).cast<String, Object?>();
    final mcp =
        ((existing['mcp'] as Map?)?.cast<String, Object?>() ??
            <String, Object?>{});
    var changed = false;

    for (final entry in oauthEntries.values) {
      if (entry is! Map) continue;
      final oauth = entry.cast<String, Object?>();
      final serverName = oauth['serverName']?.toString().trim() ?? '';
      final accessToken = oauth['accessToken']?.toString().trim() ?? '';
      if (serverName.isEmpty || accessToken.isEmpty) continue;

      final serverEntry = mcp[serverName];
      if (serverEntry is! Map) continue;
      final remote = serverEntry.cast<String, Object?>();
      final type = remote['type']?.toString().trim().toLowerCase() ?? '';
      if (type != 'remote') continue;

      final headers = <String, String>{
        ...((remote['headers'] as Map?)?.cast<String, String>() ??
            const <String, String>{}),
      };
      headers['Authorization'] = 'Bearer $accessToken';
      remote['headers'] = headers;
      mcp[serverName] = remote;
      changed = true;
    }

    if (!changed) return;

    existing['mcp'] = mcp;
    await fs.atomicWrite(
      configPath,
      const JsonEncoder.withIndent('  ').convert(existing),
    );
  }
}

Future<Map<String, Object?>> _readOAuthEntries(
  McpCredentialsStore store,
  String appConfigDir, {
  String? fallbackAppConfigDir,
}) async {
  final primary = await store.read(appConfigDir);
  final primaryOAuth =
      (primary['mcpOAuth'] as Map?)?.cast<String, Object?>() ?? const {};
  if (primaryOAuth.isNotEmpty) return primaryOAuth;

  final fallbackDir = fallbackAppConfigDir?.trim() ?? '';
  if (fallbackDir.isEmpty || fallbackDir == appConfigDir.trim()) {
    return const {};
  }
  final fallback = await store.read(fallbackDir);
  return (fallback['mcpOAuth'] as Map?)?.cast<String, Object?>() ?? const {};
}

Map<String, Object?> _opencodeMcpMap(Iterable<McpServerSpec> servers) {
  return {
    for (final server in servers)
      if (server.enabled) server.name: _opencodeEntry(server),
  };
}

Map<String, Object?> _opencodeEntry(McpServerSpec spec) => switch (spec) {
  StdioMcpServer s => {
    'type': 'local',
    'command': <String>[s.command, ...s.args],
    if (s.env.isNotEmpty) 'environment': s.env,
    'enabled': true,
  },
  RemoteMcpServer r => {
    'type': 'remote',
    'url': r.url,
    if (r.headers.isNotEmpty) 'headers': r.headers,
    'enabled': true,
  },
};
