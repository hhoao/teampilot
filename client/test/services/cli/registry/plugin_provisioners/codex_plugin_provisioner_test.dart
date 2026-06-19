import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/cli/registry/plugin_provisioners/codex_plugin_provisioner.dart';
import 'package:teampilot/services/provider/codex/codex_session_config_dir.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:toml/toml.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('CodexPluginProvisioner', () {
    test('writes cache layout and plugin enable sections into config.toml', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/demo/.claude-plugin/plugin.json',
        jsonEncode({'name': 'demo', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/demo/.mcp.json',
        jsonEncode({
          'mcpServers': {
            'bundled': {'type': 'stdio', 'command': 'echo'},
          },
        }),
      );

      await const CodexPluginProvisioner().provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: '/tp',
          configDir: configDir,
          bundlePoolDir: poolDir,
          enabledPluginIds: const ['local/demo'],
          installedCatalog: const [
            Plugin(
              id: 'local/demo',
              name: 'demo',
              description: '',
              version: '1.0.0',
              directory: 'demo',
              capabilities: PluginCapabilities(),
              installedAt: 0,
              updatedAt: 0,
            ),
          ],
          layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
          tool: CliTool.codex,
        ),
      );

      final cacheRoot = CodexSessionConfigDir.localPluginCacheRoot(
        configDir,
        'demo',
        version: '1.0.0',
      );
      expect(
        (await fs.stat(p.join(cacheRoot, '.codex-plugin', 'plugin.json'))).isFile,
        isTrue,
      );
      expect(
        (await fs.stat(
          p.join(
            CodexSessionConfigDir.localPluginSourceRoot(configDir, 'demo'),
            '.codex-plugin',
            'plugin.json',
          ),
        )).isFile,
        isTrue,
      );

      final marketplaceText = await fs.readString(
        CodexSessionConfigDir.localMarketplaceManifestPath(configDir),
      );
      final marketplace = (jsonDecode(marketplaceText!) as Map).cast<String, Object?>();
      final entries = (marketplace['plugins'] as List).cast<Map>();
      expect(entries.single['name'], 'demo');
      expect(
        (entries.single['source'] as Map)['path'],
        './plugins/demo',
      );

      final raw = await fs.readString('$configDir/config.toml');
      final doc = TomlDocument.parse(raw!).toMap();
      final plugins = (doc['plugins'] as Map).cast<String, dynamic>();
      expect((plugins['demo@local'] as Map)['enabled'], isTrue);
      final marketplaces = (doc['marketplaces'] as Map).cast<String, dynamic>();
      expect((marketplaces['local'] as Map)['source_type'], 'local');
      expect((marketplaces['local'] as Map)['source'], configDir);
    });

    test('uses local cache version when manifest omits version', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/context7/.codex-plugin/plugin.json',
        jsonEncode({'name': 'context7', 'description': 'docs'}),
      );

      await const CodexPluginProvisioner().provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: '/tp',
          configDir: configDir,
          bundlePoolDir: poolDir,
          enabledPluginIds: const ['local/context7'],
          installedCatalog: const [
            Plugin(
              id: 'local/context7',
              name: 'context7',
              description: '',
              version: '0.0.0',
              directory: 'context7',
              capabilities: PluginCapabilities(),
              installedAt: 0,
              updatedAt: 0,
            ),
          ],
          layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
          tool: CliTool.codex,
        ),
      );

      final cacheRoot = CodexSessionConfigDir.localPluginCacheRoot(
        configDir,
        'context7',
      );
      expect(
        (await fs.stat(p.join(cacheRoot, '.codex-plugin', 'plugin.json'))).isFile,
        isTrue,
      );
    });

    test('reads bundled MCP names from direct .mcp.json map', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/demo/.codex-plugin/plugin.json',
        jsonEncode({'name': 'demo', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/demo/.mcp.json',
        jsonEncode({
          'context7': {'command': 'npx', 'args': ['-y', '@upstash/context7-mcp']},
        }),
      );

      await const CodexPluginProvisioner().provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: '/tp',
          configDir: configDir,
          bundlePoolDir: poolDir,
          enabledPluginIds: const ['local/demo'],
          installedCatalog: const [
            Plugin(
              id: 'local/demo',
              name: 'demo',
              description: '',
              version: '1.0.0',
              directory: 'demo',
              capabilities: PluginCapabilities(),
              installedAt: 0,
              updatedAt: 0,
            ),
          ],
          layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
          tool: CliTool.codex,
        ),
      );

      final raw = await fs.readString('$configDir/config.toml');
      final doc = TomlDocument.parse(raw!).toMap();
      final plugins = (doc['plugins'] as Map).cast<String, dynamic>();
      final nested = (plugins['demo'] as Map).cast<String, dynamic>();
      final bundled =
          (nested['mcp_servers'] as Map).cast<String, dynamic>()['context7']
              as Map;
      expect(bundled['enabled'], isTrue);
    });
  });
}
