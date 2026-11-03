import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/mcp.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('writes mcp_config.json with mcpServers', () async {
    final fs = InMemoryFilesystem();
    const cap = AntigravityMcpCapability();

    await cap.write(
      fs: fs,
      configDir: '/cfg',
      servers: const [
        StdioMcpServer(name: 'bus', command: 'node', args: ['bus.js']),
        RemoteMcpServer(name: 'remote', url: 'https://example.test/mcp'),
      ],
    );

    final text = await fs.readString('/cfg/mcp_config.json');
    expect(text, contains('"mcpServers"'));
    expect(text, contains('"bus"'));
    expect(text, contains('"remote"'));

    final decoded = jsonDecode(text!) as Map<String, Object?>;
    final servers = decoded['mcpServers'] as Map<String, Object?>;
    expect(servers.keys, containsAll(['bus', 'remote']));

    final bus = servers['bus'] as Map<String, Object?>;
    expect(bus['type'], 'stdio');
    expect(bus['command'], 'node');
    expect(bus['args'], ['bus.js']);

    final remote = servers['remote'] as Map<String, Object?>;
    expect(remote['type'], 'http');
    expect(remote['url'], 'https://example.test/mcp');
  });

  test('merges into existing mcp_config.json without dropping keys', () async {
    final fs = InMemoryFilesystem();
    await fs.atomicWrite(
      '/cfg/mcp_config.json',
      jsonEncode({
        'theme': 'dark',
        'mcpServers': {
          'existing': {'type': 'stdio', 'command': 'old'},
        },
      }),
    );
    const cap = AntigravityMcpCapability();

    await cap.write(
      fs: fs,
      configDir: '/cfg',
      servers: const [StdioMcpServer(name: 'bus', command: 'node')],
    );

    final decoded =
        jsonDecode((await fs.readString('/cfg/mcp_config.json'))!)
            as Map<String, Object?>;
    expect(decoded['theme'], 'dark');
    expect(
      (decoded['mcpServers'] as Map<String, Object?>).keys,
      containsAll(['existing', 'bus']),
    );
  });

  test('antigravity registers MCP and the default skills capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    final mcp = registry.capability<McpCapability>(CliTool.antigravity);
    expect(mcp, isA<AntigravityMcpCapability>());

    final skill = registry.capability<SkillCapability>(CliTool.antigravity);
    expect(skill?.skillsSubdir, 'skills');
  });
}
