import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/cli/registry/plugin_provisioners/cursor_plugin_provisioner.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('CursorPluginProvisioner', () {
    test('materializes bundles under plugins/local and registers registry', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';
      const teampilotRoot = '/tp';

      await fs.writeString(
        '$poolDir/demo/.cursor-plugin/plugin.json',
        jsonEncode({'name': 'demo', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/demo/.mcp.json',
        jsonEncode({
          'mcpServers': {
            'bundled': {
              'type': 'stdio',
              'command': 'echo',
              'args': ['hi'],
            },
          },
        }),
      );

      await const CursorPluginProvisioner().provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: teampilotRoot,
          configDir: configDir,
          bundlePoolDir: poolDir,
          enabledPluginIds: const [],
          installedCatalog: const [],
          layout: RuntimeLayout(teampilotRoot: teampilotRoot, fs: fs),
          tool: CliTool.cursor,
        ),
      );

      final manifest = await fs.readString(
        '$configDir/plugins/local/demo/.cursor-plugin/plugin.json',
      );
      expect(manifest, isNotNull);
      expect((jsonDecode(manifest!) as Map)['name'], 'demo');

      final installed = await fs.readString(
        '$configDir/plugins/installed_plugins.json',
      );
      expect(installed, isNotNull);
      final installedRoot = jsonDecode(installed!) as Map;
      expect(installedRoot['version'], 2);
      final plugins = installedRoot['plugins'] as Map;
      expect(plugins.keys, contains('demo@local'));

      final settings = jsonDecode(
        (await fs.readString('$configDir/settings.json'))!,
      ) as Map;
      final enabled = settings['enabledPlugins'] as Map;
      expect(enabled['demo@local'], isTrue);

      final mcp = jsonDecode(
        (await fs.readString('$configDir/mcp.json'))!,
      ) as Map;
      final bundled = (mcp['mcpServers'] as Map)['bundled'] as Map;
      expect(bundled['command'], 'echo');
    });
  });
}
