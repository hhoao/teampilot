import 'dart:io';

/// Built-in MCP templates (aligned with cc-switch [mcpPresets]).
class McpPreset {
  const McpPreset({
    required this.id,
    required this.name,
    required this.server,
    this.description = '',
    this.tags = const [],
    this.homepage = '',
    this.docs = '',
  });

  final String id;
  final String name;
  final Map<String, Object?> server;
  final String description;
  final List<String> tags;
  final String homepage;
  final String docs;
}

Map<String, Object?> _npxServer(String package, {List<String> extraArgs = const []}) {
  if (Platform.isWindows) {
    return {
      'type': 'stdio',
      'command': 'cmd',
      'args': ['/c', 'npx', ...extraArgs, package],
    };
  }
  return {
    'type': 'stdio',
    'command': 'npx',
    'args': [...extraArgs, package],
  };
}

List<McpPreset> mcpPresets({required String Function(String id) descriptionFor}) {
  return [
    McpPreset(
      id: 'fetch',
      name: 'mcp-server-fetch',
      description: descriptionFor('fetch'),
      tags: const ['stdio', 'http', 'web'],
      homepage: 'https://github.com/modelcontextprotocol/servers',
      docs: 'https://github.com/modelcontextprotocol/servers/tree/main/src/fetch',
      server: const {
        'type': 'stdio',
        'command': 'uvx',
        'args': ['mcp-server-fetch'],
      },
    ),
    McpPreset(
      id: 'time',
      name: '@modelcontextprotocol/server-time',
      description: descriptionFor('time'),
      tags: const ['stdio', 'time', 'utility'],
      homepage: 'https://github.com/modelcontextprotocol/servers',
      docs: 'https://github.com/modelcontextprotocol/servers/tree/main/src/time',
      server: _npxServer('@modelcontextprotocol/server-time', extraArgs: ['-y']),
    ),
    McpPreset(
      id: 'memory',
      name: '@modelcontextprotocol/server-memory',
      description: descriptionFor('memory'),
      tags: const ['stdio', 'memory', 'graph'],
      homepage: 'https://github.com/modelcontextprotocol/servers',
      docs: 'https://github.com/modelcontextprotocol/servers/tree/main/src/memory',
      server: _npxServer('@modelcontextprotocol/server-memory', extraArgs: ['-y']),
    ),
    McpPreset(
      id: 'sequential-thinking',
      name: '@modelcontextprotocol/server-sequential-thinking',
      description: descriptionFor('sequential-thinking'),
      tags: const ['stdio', 'thinking', 'reasoning'],
      homepage: 'https://github.com/modelcontextprotocol/servers',
      docs:
          'https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking',
      server: _npxServer(
        '@modelcontextprotocol/server-sequential-thinking',
        extraArgs: ['-y'],
      ),
    ),
    McpPreset(
      id: 'context7',
      name: '@upstash/context7-mcp',
      description: descriptionFor('context7'),
      tags: const ['stdio', 'docs', 'search'],
      homepage: 'https://context7.com',
      docs: 'https://github.com/upstash/context7/blob/master/README.md',
      server: _npxServer('@upstash/context7-mcp', extraArgs: ['-y']),
    ),
  ];
}
