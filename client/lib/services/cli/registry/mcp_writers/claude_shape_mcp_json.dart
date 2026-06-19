import '../../../../models/mcp_server_spec.dart';

/// Shared Claude/Cursor JSON `mcpServers` map shape.
abstract final class ClaudeShapeMcpJson {
  ClaudeShapeMcpJson._();

  static Map<String, Object?> entry(McpServerSpec spec) => switch (spec) {
    StdioMcpServer s => {
      'type': 'stdio',
      'command': s.command,
      if (s.args.isNotEmpty) 'args': s.args,
      if (s.env.isNotEmpty) 'env': s.env,
      if (s.cwd != null && s.cwd!.isNotEmpty) 'cwd': s.cwd,
    },
    RemoteMcpServer r => {
      'type': 'http',
      'url': r.url,
      if (r.headers.isNotEmpty) 'headers': r.headers,
    },
  };

  static Map<String, Object?> mcpServersMap(Iterable<McpServerSpec> servers) {
    return {
      for (final server in servers)
        if (server.enabled) server.name: entry(server),
    };
  }
}
