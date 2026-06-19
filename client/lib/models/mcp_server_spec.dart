import 'package:flutter/foundation.dart';

/// Tool-agnostic MCP server definition for per-CLI config writers.
sealed class McpServerSpec {
  const McpServerSpec({required this.name, this.enabled = true});

  final String name;
  final bool enabled;

  /// Parses a catalog snapshot / plugin `mcpServers` entry.
  static McpServerSpec? fromCatalogJson(
    String name,
    Map<String, Object?> spec,
  ) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;

    final enabled = spec['enabled'] as bool? ?? true;
    final type = spec['type']?.toString().trim().toLowerCase() ?? '';

    if (_isRemoteType(type) ||
        (type.isEmpty && _hasRemoteUrl(spec))) {
      final url = spec['url']?.toString().trim() ?? '';
      if (url.isEmpty) return null;
      return RemoteMcpServer(
        name: trimmedName,
        enabled: enabled,
        url: url,
        headers: _stringMap(spec['headers']),
        bearerTokenEnvVar: spec['bearer_token_env_var']?.toString().trim(),
      );
    }

    final command = spec['command']?.toString().trim() ?? '';
    if (command.isEmpty) return null;
    return StdioMcpServer(
      name: trimmedName,
      enabled: enabled,
      command: command,
      args: _stringList(spec['args']),
      env: _stringMap(spec['env'] ?? spec['environment']),
      cwd: spec['cwd']?.toString().trim(),
    );
  }

  /// Serializes back to catalog snapshot shape (stdio / http).
  Map<String, Object?> toCatalogJson() => switch (this) {
    StdioMcpServer s => {
      'type': 'stdio',
      'command': s.command,
      if (s.args.isNotEmpty) 'args': s.args,
      if (s.env.isNotEmpty) 'env': s.env,
      if (s.cwd != null && s.cwd!.isNotEmpty) 'cwd': s.cwd,
      if (!s.enabled) 'enabled': false,
    },
    RemoteMcpServer r => {
      'type': 'http',
      'url': r.url,
      if (r.headers.isNotEmpty) 'headers': r.headers,
      if (r.bearerTokenEnvVar != null && r.bearerTokenEnvVar!.isNotEmpty)
        'bearer_token_env_var': r.bearerTokenEnvVar,
      if (!r.enabled) 'enabled': false,
    },
  };

  static bool _isRemoteType(String type) =>
      type == 'http' || type == 'sse' || type == 'streamable-http';

  static bool _hasRemoteUrl(Map<String, Object?> spec) {
    final url = spec['url']?.toString().trim() ?? '';
    return url.isNotEmpty;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpServerSpec &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          enabled == other.enabled &&
          _payloadEquals(other);

  bool _payloadEquals(McpServerSpec other) => switch ((this, other)) {
    (StdioMcpServer a, StdioMcpServer b) =>
      a.command == b.command &&
          listEquals(a.args, b.args) &&
          mapEquals(a.env, b.env) &&
          a.cwd == b.cwd,
    (RemoteMcpServer a, RemoteMcpServer b) =>
      a.url == b.url &&
          mapEquals(a.headers, b.headers) &&
          a.bearerTokenEnvVar == b.bearerTokenEnvVar,
    _ => false,
  };

  @override
  int get hashCode => Object.hash(name, enabled, _payloadHash);

  Object? get _payloadHash => switch (this) {
    StdioMcpServer s =>
      Object.hash(s.command, Object.hashAll(s.args), Object.hashAll(s.env.entries), s.cwd),
    RemoteMcpServer r =>
      Object.hash(r.url, Object.hashAll(r.headers.entries), r.bearerTokenEnvVar),
  };
}

final class StdioMcpServer extends McpServerSpec {
  const StdioMcpServer({
    required super.name,
    super.enabled = true,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.cwd,
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;
}

final class RemoteMcpServer extends McpServerSpec {
  const RemoteMcpServer({
    required super.name,
    super.enabled = true,
    required this.url,
    this.headers = const {},
    this.bearerTokenEnvVar,
  });

  final String url;
  final Map<String, String> headers;
  final String? bearerTokenEnvVar;
}
