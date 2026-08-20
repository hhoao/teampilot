import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';
import 'package:teampilot/services/cli/cursor/capabilities/plugin.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('CursorPluginCapability', () {
    test(
      'materializes bundles under plugins/local and registers registry',
      () async {
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

        await const CursorPluginCapability().provision(
          PluginProvisionContext(
            fs: fs,
            teampilotRoot: teampilotRoot,
            configDir: configDir,
            bundlePoolDir: poolDir,
            enabledPluginIds: const [],
            installedCatalog: const [],
            layout: RuntimeLayout(teampilotRoot: teampilotRoot, fs: fs),
            tool: CliTool.cursor,
            assembledMcpServers: const [
              StdioMcpServer(name: 'assembled', command: 'assembled-command'),
            ],
            mcpConfigFileName: 'mcp.base.json',
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

        final settings =
            jsonDecode((await fs.readString('$configDir/settings.json'))!)
                as Map;
        final enabled = settings['enabledPlugins'] as Map;
        expect(enabled['demo@local'], isTrue);

        final mcp =
            jsonDecode((await fs.readString('$configDir/mcp.base.json'))!)
                as Map;
        final servers = (mcp['mcpServers'] as Map).cast<String, Object?>();
        expect((servers['assembled'] as Map)['command'], 'assembled-command');
        expect(servers.containsKey('bundled'), isFalse);
      },
    );

    test(
      'projects a contained local tree without linking the pool root',
      () async {
        final fs = InMemoryFilesystem();
        const configDir = '/cfg';
        const poolDir = '/pool';
        const teampilotRoot = '/tp';
        await fs.writeString(
          '$poolDir/demo/.cursor-plugin/plugin.json',
          jsonEncode({'name': 'demo', 'version': '1.0.0'}),
        );
        await fs.writeString(
          '$poolDir/demo/skills/heavy/SKILL.md',
          '# heavy skill body',
        );
        await fs.writeString('$poolDir/demo/.git/objects/pack', 'git-pack');
        await fs.writeString(
          '$poolDir/demo/node_modules/leftpad/index.js',
          'module.exports=1',
        );

        await const CursorPluginCapability().provision(
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

        const dest = '$configDir/plugins/local/demo';
        expect((await fs.stat(dest)).isDirectory, isTrue);
        expect((await fs.stat(dest)).isSymlink, isFalse);
        expect(await fs.readSymlinkTarget(dest), isNull);
        expect(
          await fs.readSymlinkTarget('$dest/skills'),
          '$poolDir/demo/skills',
        );
        expect(fs.files.containsKey('$dest/skills/heavy/SKILL.md'), isFalse);
        expect(
          await fs.readString('$dest/skills/heavy/SKILL.md'),
          '# heavy skill body',
        );
        expect((await fs.stat('$dest/.git')).exists, isFalse);
        expect((await fs.stat('$dest/node_modules')).exists, isFalse);
      },
    );
  });
}
