import 'package:toml/toml.dart';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../registry/capabilities/mcp_capability.dart';
import '../grok_constants.dart';

/// Grok MCP config: `$GROK_HOME/config.toml` `[mcp_servers.<name>]` tables.
///
/// The session config dir is the ACP `GROK_HOME`, so only this file is
/// touched. Existing keys/tables are preserved; our servers overwrite entries
/// with the same name.
final class GrokMcpCapability implements McpCapability {
  const GrokMcpCapability();

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {
    final configPath = fs.pathContext.join(
      configDir,
      outputBasename ?? GrokConstants.configFileName,
    );
    final existing = await _readTomlMap(fs, configPath);
    final table = <String, Object?>{};
    final existingMcp = existing['mcp_servers'];
    if (existingMcp is Map) {
      for (final entry in existingMcp.entries) {
        table[entry.key.toString()] = entry.value;
      }
    }
    for (final server in servers) {
      table[server.name] = _serverToToml(server);
    }
    existing['mcp_servers'] = table;
    await fs.ensureDir(fs.pathContext.dirname(configPath));
    await fs.atomicWrite(configPath, _encodeToml(existing));
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {}

  @override
  Future<void> maybeRemoveStaleProjectTeammateBus({
    required Filesystem fs,
    Map<String, Map<String, Object?>>? extraServers,
    required String workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) async {
    // Grok session MCP is written to the isolated GROK_HOME config.toml, never
    // to a project-scoped file, so there is nothing stale to remove.
  }

  Map<String, Object?> _serverToToml(McpServerSpec server) => switch (server) {
    StdioMcpServer s => {
      'command': s.command,
      if (s.args.isNotEmpty) 'args': s.args,
      if (s.env.isNotEmpty) 'env': s.env,
      if (!s.enabled) 'enabled': false,
    },
    RemoteMcpServer r => {
      'url': r.url,
      if (_headersFor(r).isNotEmpty) 'headers': _headersFor(r),
      if (!r.enabled) 'enabled': false,
    },
  };

  Map<String, String> _headersFor(RemoteMcpServer server) {
    final headers = Map<String, String>.of(server.headers);
    final envVar = server.bearerTokenEnvVar?.trim() ?? '';
    // Grok has no `bearer_token_env_var`; it expands `${VAR}` in headers.
    if (envVar.isNotEmpty &&
        !headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      headers['Authorization'] = 'Bearer \${$envVar}';
    }
    return headers;
  }

  Future<Map<String, Object?>> _readTomlMap(Filesystem fs, String path) async {
    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    try {
      return Map<String, Object?>.from(TomlDocument.parse(raw).toMap());
    } on Object {
      // A malformed user config should not abort the launch; start from the
      // fragment we own rather than failing the whole provisioning step.
      return <String, Object?>{};
    }
  }

  String _encodeToml(Map<String, Object?> map) =>
      TomlDocument.fromMap(map).toString();
}
