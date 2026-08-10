import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/config_profile.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/cli/opencode/capabilities/plugin_provisioner.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('OpencodePluginProvisioner', () {
    test(
      'decomposes skills and agents and skips existing skill names',
      () async {
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
              'plugin-mcp': {
                'type': 'stdio',
                'command': 'node',
                'args': ['mcp.js'],
              },
            },
          }),
        );

        await fs.ensureDir('$configDir/skill/shared-skill');
        await fs.writeString(
          '$configDir/skill/shared-skill/SKILL.md',
          '---\nname: shared-skill\ndescription: from catalog\n---\n',
        );

        await _provision(fs, configDir, poolDir);

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

        final opencodeJson =
            jsonDecode((await fs.readString('$configDir/opencode.json'))!)
                as Map;
        final mcp = opencodeJson['mcp'] as Map;
        expect((mcp['plugin-mcp'] as Map)['type'], 'local');
      },
    );

    test(
      'materializes .opencode plugin bundle and registers plugin entries',
      () async {
        final fs = InMemoryFilesystem();
        const configDir = '/cfg';
        const poolDir = '/pool';

        await fs.writeString(
          '$poolDir/superpowers/.plugin/plugin.json',
          jsonEncode({'name': 'superpowers', 'version': '6.2.0'}),
        );
        await fs.writeString(
          '$poolDir/superpowers/skills/brainstorming/SKILL.md',
          '---\nname: brainstorming\ndescription: x\n---\n',
        );
        await fs.writeString(
          '$poolDir/superpowers/.opencode/plugins/superpowers.js',
          'export const SuperpowersPlugin = async () => ({});',
        );

        await _provision(fs, configDir, poolDir);

        // Skills still decomposed into opencode's `skill/` dir.
        expect(
          await fs.readString('$configDir/skill/brainstorming/SKILL.md'),
          isNotNull,
        );
        // Full bundle tree materialized so plugin-relative paths resolve.
        expect(
          await fs.readString(
            '$configDir/plugins/superpowers/.opencode/plugins/superpowers.js',
          ),
          contains('SuperpowersPlugin'),
        );
        expect(
          await fs.readString(
            '$configDir/plugins/superpowers/skills/brainstorming/SKILL.md',
          ),
          isNotNull,
        );
        // Plugin array entry registered (path relative to opencode.json).
        final opencodeJson =
            jsonDecode((await fs.readString('$configDir/opencode.json'))!)
                as Map;
        expect(
          opencodeJson['plugin'],
          ['./plugins/superpowers/.opencode/plugins/superpowers.js'],
        );
      },
    );

    test('is idempotent across repeated provisions', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/superpowers/.plugin/plugin.json',
        jsonEncode({'name': 'superpowers', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/superpowers/.opencode/plugins/superpowers.js',
        'export const SuperpowersPlugin = async () => ({});',
      );

      await _provision(fs, configDir, poolDir);
      await _provision(fs, configDir, poolDir);

      final opencodeJson =
          jsonDecode((await fs.readString('$configDir/opencode.json'))!)
              as Map;
      expect(
        opencodeJson['plugin'],
        ['./plugins/superpowers/.opencode/plugins/superpowers.js'],
      );
      expect(
        await fs.readString(
          '$configDir/plugins/superpowers/.opencode/plugins/superpowers.js',
        ),
        isNotNull,
      );
    });

    test('leaves config untouched for bundles without opencode plugin', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/plain/.plugin/plugin.json',
        jsonEncode({'name': 'plain', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/plain/skills/only-skill/SKILL.md',
        '---\nname: only-skill\ndescription: x\n---\n',
      );

      await _provision(fs, configDir, poolDir);

      expect(await fs.readString('$configDir/opencode.json'), isNull);
      expect(
        (await fs.stat('$configDir/plugins/plain')).exists,
        isFalse,
      );
    });

    test('falls back to package.json main for opencode entry', () async {
      final fs = InMemoryFilesystem();
      const configDir = '/cfg';
      const poolDir = '/pool';

      await fs.writeString(
        '$poolDir/superpowers/.plugin/plugin.json',
        jsonEncode({'name': 'superpowers', 'version': '1.0.0'}),
      );
      await fs.writeString(
        '$poolDir/superpowers/package.json',
        jsonEncode({'main': 'plugin/entry.js'}),
      );
      await fs.writeString(
        '$poolDir/superpowers/plugin/entry.js',
        'export const Entry = async () => ({});',
      );

      await _provision(fs, configDir, poolDir);

      expect(
        await fs.readString('$configDir/plugins/superpowers/plugin/entry.js'),
        contains('Entry'),
      );
      final opencodeJson =
          jsonDecode((await fs.readString('$configDir/opencode.json'))!)
              as Map;
      expect(opencodeJson['plugin'], ['./plugins/superpowers/plugin/entry.js']);
    });

    test('mergeOpencodePluginEntries appends and preserves tuples', () {
      final merged = mergeOpencodePluginEntries(
        <String, Object?>{
          'plugin': <Object?>[
            <Object?>['./teampilot-idle-bus.js', <String, Object?>{'member': 'm1'}],
            './existing.js',
          ],
        },
        const ['./plugins/a/x.js', './existing.js', './plugins/a/x.js'],
      );
      final plugin = (merged['plugin'] as List).cast<Object?>();
      expect(plugin, hasLength(3));
      expect(plugin.first, isA<List>());
      expect((plugin.first as List).first, './teampilot-idle-bus.js');
      expect(plugin, containsAll(<Object?>['./existing.js', './plugins/a/x.js']));
    });
  });
}

Future<void> _provision(
  InMemoryFilesystem fs,
  String configDir,
  String poolDir,
) {
  return const OpencodePluginProvisioner().provision(
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
}
