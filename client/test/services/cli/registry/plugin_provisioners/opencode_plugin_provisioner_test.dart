import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/cli/registry/plugin_provisioners/opencode_plugin_provisioner.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('OpencodePluginProvisioner', () {
    test('decomposes skills and agents and skips existing skill names', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/bundle/.plugin/plugin.json',
        jsonEncode({'name': 'bundle', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/bundle/skills/shared-skill/SKILL.md',
        '---\nname: shared-skill\ndescription: from plugin\n---\n',
      );
      await fs.writeString(
        '$poolDir/bundle/skills/fresh-skill/SKILL.md',
        '---\nname: fresh-skill\ndescription: new\n---\n',
      );
      await fs.writeString(
        '$poolDir/bundle/agents/reviewer.md',
        '# Reviewer agent',
      );
      await fs.writeString(
        '$poolDir/bundle/.mcp.json',
        jsonEncode({
          'mcpServers': {
            'plugin-mcp': {'type': 'stdio', 'command': 'node', 'args': ['mcp.js']},
          },
        }),
      );

      await fs.ensureDir('$configDir/skill/shared-skill');
      await fs.writeString(
        '$configDir/skill/shared-skill/SKILL.md',
        '---\nname: shared-skill\ndescription: from catalog\n---\n',
      );

      await const OpencodePluginProvisioner().provision(
        PluginProvisionContext(
          fs: fs,
          teampilotRoot: '/tp',
          configDir: configDir,
          bundlePoolDir: poolDir,
          enabledPluginIds: const [],
          installedCatalog: const [],
          layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
          tool: CliTool.opencode,
        ),
      );

      expect(
        await fs.readString('$configDir/skill/shared-skill/SKILL.md'),
        contains('from catalog'),
        reason: 'catalog skill must not be overwritten by plugin dedupe',
      );
      expect(
        await fs.readString('$configDir/skill/fresh-skill/SKILL.md'),
        contains('fresh-skill'),
      );
      expect(
        await fs.readString('$configDir/agent/reviewer.md'),
        '# Reviewer agent',
      );

      final opencodeJson = jsonDecode(
        (await fs.readString('$configDir/opencode.json'))!,
      ) as Map;
      final mcp = opencodeJson['mcp'] as Map;
      expect((mcp['plugin-mcp'] as Map)['type'], 'local');
    });
  });
}
