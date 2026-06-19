import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/services/cli/registry/mcp_writers/claude_mcp_config_writer.dart';
import 'package:teampilot/services/cli/registry/mcp_writers/codex_mcp_config_writer.dart';
import 'package:teampilot/services/cli/registry/mcp_writers/codex_toml_merge.dart';
import 'package:teampilot/services/cli/registry/mcp_writers/cursor_mcp_config_writer.dart';
import 'package:teampilot/services/cli/registry/mcp_writers/opencode_mcp_config_writer.dart';
import 'package:toml/toml.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('ClaudeMcpConfigWriter', () {
    test('writes stdio and remote into metadata preserving other keys', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      await fs.writeString(
        '$configDir/.claude.json',
        jsonEncode({'hasCompletedOnboarding': true}),
      );

      await const ClaudeMcpConfigWriter().write(
        fs: fs,
        configDir: configDir,
        servers: const [
          StdioMcpServer(name: 'fetch', command: 'npx', args: ['-y', 'fetch']),
          RemoteMcpServer(
            name: 'remote',
            url: 'https://example.com/mcp',
            headers: {'Authorization': 'Bearer x'},
          ),
        ],
      );

      final raw = await fs.readString('$configDir/.claude.json');
      final meta = jsonDecode(raw!) as Map;
      expect(meta['hasCompletedOnboarding'], isTrue);
      final servers = meta['mcpServers'] as Map;
      expect((servers['fetch'] as Map)['command'], 'npx');
      expect((servers['remote'] as Map)['url'], 'https://example.com/mcp');
    });
  });

  group('CursorMcpConfigWriter', () {
    test('writes Claude-shaped mcp.json at cursor config root', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';

      await const CursorMcpConfigWriter().write(
        fs: fs,
        configDir: configDir,
        servers: const [
          RemoteMcpServer(name: 'bus', url: 'http://127.0.0.1:1/mcp'),
        ],
      );

      final raw = await fs.readString('$configDir/mcp.json');
      final decoded = jsonDecode(raw!) as Map;
      final bus = (decoded['mcpServers'] as Map)['bus'] as Map;
      expect(bus['type'], 'http');
      expect(bus['url'], 'http://127.0.0.1:1/mcp');
    });
  });

  group('CodexTomlMerge', () {
    test('mergeMcpServers preserves unrelated tables', () {
      const existing = '''
model = "gpt-4"

[features]
web_search = true
''';
      final merged = CodexTomlMerge.mergeMcpServers(existing, const [
        StdioMcpServer(name: 'fetch', command: 'npx'),
        RemoteMcpServer(
          name: 'remote',
          url: 'https://example.com/mcp',
          headers: {'Authorization': 'Bearer tok'},
        ),
      ]);

      final doc = TomlDocument.parse(merged).toMap();
      expect(doc['model'], 'gpt-4');
      expect((doc['features'] as Map)['web_search'], isTrue);
      final servers = (doc['mcp_servers'] as Map).cast<String, dynamic>();
      expect((servers['fetch'] as Map)['command'], 'npx');
      expect((servers['remote'] as Map)['url'], 'https://example.com/mcp');
    });

    test('mergePluginEnables preserves unrelated tables', () {
      const existing = '''
model = "gpt-4"

[features]
web_search = true
''';
      final merged = CodexTomlMerge.mergePluginEnables(existing, const [
        CodexPluginEnableSpec(
          name: 'demo',
          bundledMcpServerNames: ['bundled'],
        ),
      ]);

      final doc = TomlDocument.parse(merged).toMap();
      expect(doc['model'], 'gpt-4');
      expect((doc['features'] as Map)['web_search'], isTrue);
      final plugins = (doc['plugins'] as Map).cast<String, dynamic>();
      expect((plugins['demo@local'] as Map)['enabled'], isTrue);
      final nested = (plugins['demo'] as Map).cast<String, dynamic>();
      final bundled =
          (nested['mcp_servers'] as Map).cast<String, dynamic>()['bundled']
              as Map;
      expect(bundled['enabled'], isTrue);
      expect(bundled['default_tools_approval_mode'], 'prompt');
    });

    test('mergeLocalMarketplace writes marketplaces.local block', () {
      final merged = CodexTomlMerge.mergeLocalMarketplace('', '/tmp/codex-home');

      final doc = TomlDocument.parse(merged).toMap();
      final marketplaces = (doc['marketplaces'] as Map).cast<String, dynamic>();
      expect((marketplaces['local'] as Map)['source_type'], 'local');
      expect((marketplaces['local'] as Map)['source'], '/tmp/codex-home');
    });

    test('preserveManagedTables keeps marketplaces on provider rewrite', () {
      const existing = '''
[marketplaces.local]
source_type = "local"
source = "/tmp/codex-home"
''';

      const composed = '''
model = "deepseek"
''';

      final merged = CodexTomlMerge.preserveManagedTables(
        existingToml: existing,
        composedToml: composed,
      );

      expect(merged, contains('[marketplaces.local]'));
      expect(merged, contains("source = '/tmp/codex-home'"));
    });

    test('preserveManagedTables keeps plugins and mcp on provider rewrite', () {
      const existing = '''
[plugins."demo@local"]
enabled = true

[mcp_servers.time]
command = "npx"
''';

      const composed = '''
model = "deepseek"
''';

      final merged = CodexTomlMerge.preserveManagedTables(
        existingToml: existing,
        composedToml: composed,
      );

      expect(merged, contains("[plugins.'demo@local']"));
      expect(merged, contains('[mcp_servers.time]'));
    });
    test('applyBearerTokenEnvVars sets bearer_token_env_var and strips auth header', () {
      const existing = '''
[mcp_servers.remote]
url = "https://example.com/mcp"
http_headers = { Authorization = "Bearer inline" }
''';
      final merged = CodexTomlMerge.applyBearerTokenEnvVars(existing, const {
        'remote': 'TEAMPILOT_MCP_BEARER_REMOTE',
      });

      final doc = TomlDocument.parse(merged).toMap();
      final remote = (doc['mcp_servers'] as Map)['remote'] as Map;
      expect(remote['bearer_token_env_var'], 'TEAMPILOT_MCP_BEARER_REMOTE');
      expect(remote.containsKey('http_headers'), isFalse);
    });
  });

  group('CodexMcpConfigWriter', () {
    test('writes merged config.toml', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/codex';
      await fs.writeString('$configDir/config.toml', 'model = "gpt"\n');

      await const CodexMcpConfigWriter().write(
        fs: fs,
        configDir: configDir,
        servers: const [
          StdioMcpServer(name: 'fetch', command: 'npx'),
        ],
      );

      final raw = await fs.readString('$configDir/config.toml');
      final doc = TomlDocument.parse(raw!).toMap();
      expect(doc['model'], 'gpt');
      expect((doc['mcp_servers'] as Map)['fetch'], isNotNull);
    });

    test('mergeAppCredentials writes env file and bearer_token_env_var', () async {
      final fs = InMemoryFilesystem();
      const appDir = '/app';
      const sessionDir = '/codex';
      await fs.writeString(
        '$appDir/.credentials.json',
        jsonEncode({
          'mcpOAuth': {
            'remote|abc': {
              'serverName': 'remote',
              'serverUrl': 'https://example.com/mcp',
              'accessToken': 'oauth-tok',
            },
          },
        }),
      );
      await fs.writeString(
        '$sessionDir/config.toml',
        '''
[mcp_servers.remote]
url = "https://example.com/mcp"
''',
      );

      await const CodexMcpConfigWriter().mergeAppCredentials(
        fs: fs,
        appConfigDir: appDir,
        sessionConfigDir: sessionDir,
      );

      final envRaw = await fs.readString('$sessionDir/.mcp-oauth.env.json');
      final env = jsonDecode(envRaw!) as Map;
      expect(env['TEAMPILOT_MCP_BEARER_REMOTE'], 'oauth-tok');

      final toml = TomlDocument.parse(
        await fs.readString('$sessionDir/config.toml') ?? '',
      ).toMap();
      final remote = (toml['mcp_servers'] as Map)['remote'] as Map;
      expect(remote['bearer_token_env_var'], 'TEAMPILOT_MCP_BEARER_REMOTE');
    });
  });

  group('OpencodeMcpConfigWriter', () {
    test('writes local and remote entries into opencode.json mcp map', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/oc';
      await fs.writeString('$configDir/opencode.json', '{"plugin":[]}');

      await const OpencodeMcpConfigWriter().write(
        fs: fs,
        configDir: configDir,
        servers: const [
          StdioMcpServer(name: 'local', command: 'node', args: ['srv.js']),
          RemoteMcpServer(name: 'remote', url: 'https://example.com/mcp'),
        ],
      );

      final raw = await fs.readString('$configDir/opencode.json');
      final decoded = jsonDecode(raw!) as Map;
      expect(decoded['plugin'], isNotNull);
      final mcp = decoded['mcp'] as Map;
      expect((mcp['local'] as Map)['type'], 'local');
      expect((mcp['local'] as Map)['command'], ['node', 'srv.js']);
      expect((mcp['remote'] as Map)['type'], 'remote');
    });

    test('mergeAppCredentials injects Authorization header for remote OAuth', () async {
      final fs = InMemoryFilesystem();
      const appDir = '/app';
      const sessionDir = '/oc';
      await fs.writeString(
        '$appDir/.credentials.json',
        jsonEncode({
          'mcpOAuth': {
            'remote|abc': {
              'serverName': 'remote',
              'serverUrl': 'https://example.com/mcp',
              'accessToken': 'oauth-tok',
            },
          },
        }),
      );
      await fs.writeString(
        '$sessionDir/opencode.json',
        jsonEncode({
          'mcp': {
            'remote': {
              'type': 'remote',
              'url': 'https://example.com/mcp',
              'enabled': true,
            },
          },
        }),
      );

      await const OpencodeMcpConfigWriter().mergeAppCredentials(
        fs: fs,
        appConfigDir: appDir,
        sessionConfigDir: sessionDir,
      );

      final raw = await fs.readString('$sessionDir/opencode.json');
      final decoded = jsonDecode(raw!) as Map;
      final headers =
          ((decoded['mcp'] as Map)['remote'] as Map)['headers'] as Map;
      expect(headers['Authorization'], 'Bearer oauth-tok');
    });
  });
}
