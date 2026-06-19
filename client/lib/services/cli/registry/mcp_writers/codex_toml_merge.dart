import 'package:toml/toml.dart';

import '../../../../models/mcp_server_spec.dart';

/// Round-trip merge for Codex `config.toml` — only `[mcp_servers.*]` and
/// `[plugins.*]` tables are mutated; unrelated keys survive.
abstract final class CodexTomlMerge {
  CodexTomlMerge._();

  static String mergeMcpServers(
    String existingToml,
    Iterable<McpServerSpec> servers,
  ) =>
      _merge(
        existingToml,
        mutate: (root) => _applyMcpServers(root, servers),
      );

  /// Sets `bearer_token_env_var` on `[mcp_servers.*]` and strips inline bearer headers.
  static String applyBearerTokenEnvVars(
    String existingToml,
    Map<String, String> serverEnvVars,
  ) =>
      _merge(
        existingToml,
        mutate: (root) => _applyBearerTokenEnvVars(root, serverEnvVars),
      );

  static String mergePluginEnables(
    String existingToml,
    Iterable<CodexPluginEnableSpec> plugins,
  ) =>
      _merge(
        existingToml,
        mutate: (root) => _applyPluginEnables(root, plugins),
      );

  /// Registers the session-local marketplace Codex discovers via `[marketplaces.local]`.
  static String mergeLocalMarketplace(String existingToml, String configDir) =>
      _merge(
        existingToml,
        mutate: (root) => _applyLocalMarketplace(root, configDir),
      );

  /// Re-applies [plugins], [marketplaces], and [mcp_servers] from [existingToml]
  /// onto [composedToml].
  static String preserveManagedTables({
    required String existingToml,
    required String composedToml,
  }) {
    if (existingToml.trim().isEmpty) return composedToml;
    final existingRoot = Map<String, dynamic>.from(
      TomlDocument.parse(existingToml).toMap(),
    );
    var result = composedToml;
    final plugins = existingRoot['plugins'];
    if (plugins is Map && plugins.isNotEmpty) {
      result = _merge(
        result,
        mutate: (root) => root['plugins'] = Map<String, dynamic>.from(plugins),
      );
    }
    final marketplaces = existingRoot['marketplaces'];
    if (marketplaces is Map && marketplaces.isNotEmpty) {
      result = _merge(
        result,
        mutate: (root) =>
            root['marketplaces'] = Map<String, dynamic>.from(marketplaces),
      );
    }
    final mcpServers = existingRoot['mcp_servers'];
    if (mcpServers is Map && mcpServers.isNotEmpty) {
      result = _merge(
        result,
        mutate: (root) =>
            root['mcp_servers'] = Map<String, dynamic>.from(mcpServers),
      );
    }
    return result;
  }

  static String _merge(
    String existingToml, {
    required void Function(Map<String, dynamic> root) mutate,
  }) {
    final root = existingToml.trim().isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(TomlDocument.parse(existingToml).toMap());
    mutate(root);
    if (root.isEmpty) return '';
    return '${TomlDocument.fromMap(root)}\n';
  }

  static void _applyMcpServers(
    Map<String, dynamic> root,
    Iterable<McpServerSpec> servers,
  ) {
    final mcpServers =
        (root['mcp_servers'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    for (final server in servers) {
      if (!server.enabled) continue;
      mcpServers[server.name] = _mcpEntry(server);
    }

    if (mcpServers.isNotEmpty) {
      root['mcp_servers'] = mcpServers;
    }
  }

  static void _applyBearerTokenEnvVars(
    Map<String, dynamic> root,
    Map<String, String> serverEnvVars,
  ) {
    if (serverEnvVars.isEmpty) return;

    final mcpServers =
        (root['mcp_servers'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    for (final entry in serverEnvVars.entries) {
      final serverName = entry.key;
      final envVar = entry.value;
      final nested =
          (mcpServers[serverName] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      if (nested.isEmpty) continue;

      nested['bearer_token_env_var'] = envVar;
      final headers =
          (nested['http_headers'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      headers.remove('Authorization');
      headers.remove('authorization');
      if (headers.isEmpty) {
        nested.remove('http_headers');
      } else {
        nested['http_headers'] = headers;
      }
      mcpServers[serverName] = nested;
    }

    if (mcpServers.isNotEmpty) {
      root['mcp_servers'] = mcpServers;
    }
  }

  static void _applyLocalMarketplace(
    Map<String, dynamic> root,
    String configDir,
  ) {
    final marketplaces =
        (root['marketplaces'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    marketplaces['local'] = {
      'last_updated': DateTime.now().toUtc().toIso8601String(),
      'source_type': 'local',
      'source': configDir,
    };
    root['marketplaces'] = marketplaces;
  }

  static void _applyPluginEnables(
    Map<String, dynamic> root,
    Iterable<CodexPluginEnableSpec> plugins,
  ) {
    final pluginsRoot =
        (root['plugins'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    for (final plugin in plugins) {
      pluginsRoot['${plugin.name}@local'] = {'enabled': true};

      final nested =
          (pluginsRoot[plugin.name] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final bundledMcp =
          (nested['mcp_servers'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      for (final serverName in plugin.bundledMcpServerNames) {
        bundledMcp[serverName] = {
          'enabled': true,
          'default_tools_approval_mode': 'prompt',
        };
      }

      if (bundledMcp.isNotEmpty) {
        nested['mcp_servers'] = bundledMcp;
        pluginsRoot[plugin.name] = nested;
      }
    }

    if (pluginsRoot.isNotEmpty) {
      root['plugins'] = pluginsRoot;
    }
  }

  static Map<String, dynamic> _mcpEntry(McpServerSpec spec) => switch (spec) {
    StdioMcpServer s => {
      'enabled': true,
      'command': s.command,
      if (s.args.isNotEmpty) 'args': s.args,
      if (s.env.isNotEmpty) 'env': s.env,
      if (s.cwd != null && s.cwd!.isNotEmpty) 'cwd': s.cwd,
    },
    RemoteMcpServer r => {
      'enabled': true,
      'url': r.url,
      if (r.bearerTokenEnvVar != null && r.bearerTokenEnvVar!.isNotEmpty)
        'bearer_token_env_var': r.bearerTokenEnvVar,
      if (r.headers.isNotEmpty) 'http_headers': r.headers,
    },
  };
}

/// One enabled Codex plugin plus bundled MCP server names from its `.mcp.json`.
final class CodexPluginEnableSpec {
  const CodexPluginEnableSpec({
    required this.name,
    this.bundledMcpServerNames = const [],
  });

  final String name;
  final List<String> bundledMcpServerNames;
}
