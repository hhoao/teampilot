import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/plugin.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/plugins/antigravity_plugin_projector.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('AntigravityPluginProjector', () {
    test('projects a neutral bundle to plugin.json + components', () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/pool/pkg/.plugin');
      await fs.writeString(
        '/pool/pkg/.plugin/plugin.json',
        '{"name":"demo","version":"1.0.0"}',
      );
      await fs.ensureDir('/pool/pkg/skills/demo');
      await fs.writeString(
        '/pool/pkg/skills/demo/SKILL.md',
        '---\nname: demo\ndescription: d\n---\n',
      );
      await fs.ensureDir('/pool/pkg/agents');
      await fs.writeString('/pool/pkg/agents/a.md', '# a');
      await fs.writeString(
        '/pool/pkg/.plugin/.mcp.json',
        '{"mcpServers":{"bus":{"command":"node","args":["bus.js"]}}}',
      );

      await AntigravityPluginProjector.project(
        fs: fs,
        bundleDir: '/pool/pkg',
        targetDir: '/cfg/plugins/demo',
      );

      expect(
        await fs.readString('/cfg/plugins/demo/plugin.json'),
        contains('"demo"'),
      );
      expect(
        (await fs.stat('/cfg/plugins/demo/skills/demo/SKILL.md')).isFile,
        isTrue,
      );
      expect(
        (await fs.stat('/cfg/plugins/demo/agents/a.md')).isFile,
        isTrue,
      );
      expect(
        await fs.readString('/cfg/plugins/demo/mcp_config.json'),
        contains('bus'),
      );
    });

    test('keeps the neutral manifest for member inspection', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString(
        '/pool/pkg/.plugin/plugin.json',
        jsonEncode({'name': 'pkg', 'version': '1.0.0'}),
      );

      await AntigravityPluginProjector.project(
        fs: fs,
        bundleDir: '/pool/pkg',
        targetDir: '/cfg/plugins/pkg',
      );

      final root = await fs.readString('/cfg/plugins/pkg/plugin.json');
      final neutral = await fs.readString(
        '/cfg/plugins/pkg/.plugin/plugin.json',
      );
      expect(root, contains('pkg'));
      expect(neutral, root);
    });

    test('copies rules and projects the hooks fragment', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString(
        '/pool/pkg/.plugin/plugin.json',
        jsonEncode({'name': 'pkg', 'version': '1.0.0'}),
      );
      await fs.writeString('/pool/pkg/rules/team.md', '# rule');
      await fs.writeString(
        '/pool/pkg/.plugin/hooks.json',
        jsonEncode({
          'teampilot-guard': {
            'PreToolUse': [
              {
                'matcher': 'run_command',
                'hooks': [
                  {'type': 'command', 'command': './guard.sh'},
                ],
              },
            ],
          },
        }),
      );

      await AntigravityPluginProjector.project(
        fs: fs,
        bundleDir: '/pool/pkg',
        targetDir: '/cfg/plugins/pkg',
      );

      expect(
        (await fs.stat('/cfg/plugins/pkg/rules/team.md')).isFile,
        isTrue,
      );
      final hooks =
          jsonDecode((await fs.readString('/cfg/plugins/pkg/hooks.json'))!)
              as Map<String, Object?>;
      expect(hooks.keys, contains('teampilot-guard'));
    });

    test('falls back to .claude-plugin manifest and root fragments', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString(
        '/pool/legacy/.claude-plugin/plugin.json',
        jsonEncode({'name': 'legacy'}),
      );
      await fs.writeString(
        '/pool/legacy/.mcp.json',
        jsonEncode({
          'mcpServers': {
            'bus': {'command': 'node'},
          },
        }),
      );
      await fs.writeString('/pool/legacy/hooks.json', jsonEncode({'h': {}}));

      await AntigravityPluginProjector.project(
        fs: fs,
        bundleDir: '/pool/legacy',
        targetDir: '/cfg/plugins/legacy',
      );

      expect(
        await fs.readString('/cfg/plugins/legacy/plugin.json'),
        contains('legacy'),
      );
      expect(
        await fs.readString('/cfg/plugins/legacy/mcp_config.json'),
        contains('bus'),
      );
      expect(
        await fs.readString('/cfg/plugins/legacy/hooks.json'),
        contains('"h"'),
      );
    });

    test('replaces a stale target directory', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/cfg/plugins/pkg/stale.md', 'old');
      await fs.writeString(
        '/pool/pkg/.plugin/plugin.json',
        jsonEncode({'name': 'pkg'}),
      );

      await AntigravityPluginProjector.project(
        fs: fs,
        bundleDir: '/pool/pkg',
        targetDir: '/cfg/plugins/pkg',
      );

      expect((await fs.stat('/cfg/plugins/pkg/stale.md')).exists, isFalse);
      expect(
        (await fs.stat('/cfg/plugins/pkg/plugin.json')).isFile,
        isTrue,
      );
    });

    test('rejects traversing target directory names', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/cfg/keep.txt', 'keep');

      await expectLater(
        AntigravityPluginProjector.project(
          fs: fs,
          bundleDir: '/pool/pkg',
          targetDir: '/cfg/plugins/..',
        ),
        throwsArgumentError,
      );
      expect(await fs.readString('/cfg/keep.txt'), 'keep');
    });
  });

  group('AntigravityPluginCapability', () {
    test('declares the neutral manifest layout and supported components', () {
      const cap = AntigravityPluginCapability();
      expect(cap.runtimeOwnership, PluginRuntimeOwnership.teamPilot);
      expect(cap.manifestPaths?.manifestDirName, '.plugin');
      expect(cap.memberPluginsSubpath, ['plugins']);
      expect(cap.pluginsSubdir, 'plugins');
      expect(
        cap.pluginsRepresentation,
        ResourceRepresentation.linkedDirectory,
      );
      expect(cap.consumesMarketplaces, isFalse);
      expect(cap.writesAssembledMcp, isFalse);
      expect(cap.needsSharedPluginDepsBeforeReconcile, isFalse);
      expect(cap.supported, {
        PluginComponentKind.skills,
        PluginComponentKind.agents,
        PluginComponentKind.hooks,
        PluginComponentKind.mcp,
        PluginComponentKind.rules,
      });
      expect(cap.supported, isNot(contains(PluginComponentKind.commands)));
    });

    test('provisions every enabled bundle into plugins/<directory>', () async {
      final fs = InMemoryFilesystem();
      await _writeBundle(fs, '/pool/demo', 'demo');
      await _writeBundle(fs, '/pool/other', 'other');

      await _provision(
        fs,
        enabledPluginIds: const ['demo', 'other'],
        installedCatalog: [_plugin(id: 'demo'), _plugin(id: 'other')],
      );

      expect(
        await fs.readString('/cfg/plugins/demo/plugin.json'),
        contains('demo'),
      );
      expect(
        await fs.readString('/cfg/plugins/other/plugin.json'),
        contains('other'),
      );
      expect(
        (await fs.stat('/cfg/plugins/demo/skills/demo/SKILL.md')).isFile,
        isTrue,
      );
      expect(
        (await fs.stat('/cfg/plugins/demo/.plugin/plugin.json')).isFile,
        isTrue,
      );
    });

    test('resolves the pool entry and target by Plugin.directory', () async {
      final fs = InMemoryFilesystem();
      // Id differs from the on-disk bundle directory, as with marketplace
      // plugin ids (`acme/demo`).
      await _writeBundle(fs, '/pool/demo-bundle', 'demo');

      await _provision(
        fs,
        enabledPluginIds: const ['acme/demo'],
        installedCatalog: [
          _plugin(id: 'acme/demo', name: 'demo', directory: 'demo-bundle'),
        ],
      );

      expect(
        await fs.readString('/cfg/plugins/demo-bundle/plugin.json'),
        contains('demo'),
      );
      expect((await fs.stat('/cfg/plugins/acme/demo')).exists, isFalse);
    });

    test('skips ids absent from the installed catalog', () async {
      final fs = InMemoryFilesystem();
      await _writeBundle(fs, '/pool/demo', 'demo');

      await _provision(
        fs,
        enabledPluginIds: const ['demo', 'unknown'],
        installedCatalog: [_plugin(id: 'demo')],
      );

      expect(
        await fs.readString('/cfg/plugins/demo/plugin.json'),
        contains('demo'),
      );
      expect((await fs.stat('/cfg/plugins/unknown')).exists, isFalse);
    });

    test('is a no-op for missing bundles', () async {
      final fs = InMemoryFilesystem();
      await _writeBundle(fs, '/pool/demo', 'demo');

      await _provision(
        fs,
        enabledPluginIds: const ['demo', 'missing'],
        installedCatalog: [_plugin(id: 'demo'), _plugin(id: 'missing')],
      );

      expect(
        await fs.readString('/cfg/plugins/demo/plugin.json'),
        contains('demo'),
      );
      expect((await fs.stat('/cfg/plugins/missing')).exists, isFalse);
    });

    test('rejects traversing bundle directories without deleting config', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/cfg/keep.txt', 'keep');
      await fs.writeString('/cfg/plugins/stale/plugin.json', '{}');

      await _provision(
        fs,
        enabledPluginIds: const ['..', '../escape'],
        installedCatalog: [
          _plugin(id: '..', name: '..', directory: '..'),
          _plugin(id: '../escape', name: 'escape', directory: '../escape'),
        ],
      );

      expect(await fs.readString('/cfg/keep.txt'), 'keep');
      expect((await fs.stat('/cfg/plugins/..')).exists, isFalse);
      // The unsafe entries were skipped; unrelated stale bundles are pruned
      // inside the plugins root only.
      expect((await fs.stat('/cfg/plugins/stale')).exists, isFalse);
    });

    test('prunes projected bundles no longer enabled', () async {
      final fs = InMemoryFilesystem();
      await _writeBundle(fs, '/pool/demo', 'demo');
      await fs.writeString('/cfg/plugins/removed/plugin.json', '{}');
      await fs.writeString(
        '/cfg/plugins/marketplaces/keep.json',
        '{}',
      );

      await _provision(
        fs,
        enabledPluginIds: const ['demo'],
        installedCatalog: [_plugin(id: 'demo'), _plugin(id: 'removed')],
      );

      expect(
        await fs.readString('/cfg/plugins/demo/plugin.json'),
        contains('demo'),
      );
      expect((await fs.stat('/cfg/plugins/removed')).exists, isFalse);
      expect(
        (await fs.stat('/cfg/plugins/marketplaces/keep.json')).isFile,
        isTrue,
      );
    });

    test('no enabled plugins leaves the config untouched', () async {
      final fs = InMemoryFilesystem();
      await _writeBundle(fs, '/pool/demo', 'demo');

      await _provision(
        fs,
        enabledPluginIds: const [],
        installedCatalog: [_plugin(id: 'demo')],
      );

      expect((await fs.stat('/cfg/plugins')).exists, isFalse);
    });
  });
}

Plugin _plugin({
  required String id,
  String? name,
  String? directory,
}) => Plugin(
  id: id,
  name: name ?? id,
  description: 'test plugin',
  version: '1.0.0',
  directory: directory ?? id,
  installedAt: 0,
  updatedAt: 0,
);

Future<void> _writeBundle(
  InMemoryFilesystem fs,
  String bundleDir,
  String name,
) async {
  await fs.writeString(
    '$bundleDir/.plugin/plugin.json',
    jsonEncode({'name': name, 'version': '1.0.0'}),
  );
  await fs.writeString(
    '$bundleDir/skills/$name/SKILL.md',
    '---\nname: $name\ndescription: d\n---\n',
  );
}

Future<void> _provision(
  InMemoryFilesystem fs, {
  required List<String> enabledPluginIds,
  List<Plugin> installedCatalog = const [],
}) {
  return const AntigravityPluginCapability().provision(
    PluginProvisionContext(
      fs: fs,
      teampilotRoot: '/tp',
      configDir: '/cfg',
      bundlePoolDir: '/pool',
      enabledPluginIds: enabledPluginIds,
      installedCatalog: installedCatalog,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      tool: CliTool.antigravity,
    ),
  );
}
