import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/plugin/cli_plugin_registry_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory base;
  late RuntimeLayout layout;
  late CliPluginRegistryService registry;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cli_plugin_registry_');
    final paths = AppPaths(base.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: base.path,
      cwd: base.path,
    );
    final fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    registry = CliPluginRegistryService(
      fs: fs,
      teampilotRoot: base.path,
      layout: layout,
    );
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
  });

  Future<void> seedMemberPlugin({
    required String teamId,
    required String sessionId,
    required String tool,
    required String pluginName,
  }) async {
    final teamPlugins = Directory(layout.identityPluginsDir(teamId))
      ..createSync(recursive: true);
    final bundle = Directory(p.join(teamPlugins.path, pluginName))
      ..createSync();
    Directory(p.join(bundle.path, '.claude-plugin')).createSync();
    await File(
      p.join(bundle.path, '.claude-plugin', 'plugin.json'),
    ).writeAsString(
      jsonEncode({'name': pluginName, 'version': '2.0.0'}),
    );
    await layout.provisionSessionPluginsFromIdentity(
      'workspace-1',
      sessionId,
      teamId,
      tool,
    );
  }

  test('writes enabledPlugins and installed_plugins.json for flashskyai', () async {
    await seedMemberPlugin(
      teamId: 't1',
      sessionId: 's1',
      tool: CliTool.flashskyai.value,
      pluginName: 'demo',
    );

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's1',
      tool: CliTool.flashskyai,
      team: const TeamProfile(
        id: 't1',
        name: 'Team',
        pluginIds: ['local/demo'],
      ),
      installedCatalog: const [
        Plugin(
          id: 'local/demo',
          name: 'demo',
          description: '',
          version: '2.0.0',
          directory: 'demo',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    final configDir = layout.sessionRuntimeToolDir('workspace-1', 's1', 'flashskyai');
    final settings = jsonDecode(
      await File(p.join(configDir, 'settings.json')).readAsString(),
    ) as Map<String, Object?>;
    final enabled = settings['enabledPlugins'] as Map;
    expect(enabled['demo@local'], isTrue);

    final installed = jsonDecode(
      await File(p.join(configDir, 'plugins', 'installed_plugins.json'))
          .readAsString(),
    ) as Map<String, Object?>;
    expect(installed['version'], 2);
    final plugins = installed['plugins'] as Map;
    final entry = (plugins['demo@local'] as List).first as Map;
    expect(entry['installPath'], isNotEmpty);
    expect(entry['version'], '2.0.0');
  });

  test('claude session uses claude flavor without flashskyai manifest in registry scan',
      () async {
    await seedMemberPlugin(
      teamId: 't1',
      sessionId: 's2',
      tool: CliTool.claude.value,
      pluginName: 'demo',
    );

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's2',
      tool: CliTool.claude,
    );

    final configDir = layout.sessionRuntimeToolDir('workspace-1', 's2', 'claude');
    final settings = jsonDecode(
      await File(p.join(configDir, 'settings.json')).readAsString(),
    ) as Map<String, Object?>;
    expect((settings['enabledPlugins'] as Map).containsKey('demo@local'), isTrue);
  });

  test('materializes remote marketplace under plugins/marketplaces for flashskyai', () async {
    const marketplaceName = 'claude-plugins-official';
    final cacheDir = Directory(
      p.join(
        base.path,
        'plugins',
        'marketplace-cache',
        'anthropics',
        '$marketplaceName@main',
      ),
    )..createSync(recursive: true);
    Directory(p.join(cacheDir.path, '.claude-plugin')).createSync();
    await File(
      p.join(cacheDir.path, '.claude-plugin', 'marketplace.json'),
    ).writeAsString(
      jsonEncode({
        'name': marketplaceName,
        'owner': {'name': 'Anthropic'},
        'plugins': [
          {'name': 'context7', 'version': '1.0.0', 'source': './plugins/context7'},
        ],
      }),
    );

    await seedMemberPlugin(
      teamId: 't1',
      sessionId: 's3',
      tool: CliTool.flashskyai.value,
      pluginName: 'context7',
    );

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's3',
      tool: CliTool.flashskyai,
      team: const TeamProfile(
        id: 't1',
        name: 'Team',
        pluginIds: ['anthropics/claude-plugins-official/context7'],
      ),
      installedCatalog: const [
        Plugin(
          id: 'anthropics/claude-plugins-official/context7',
          name: 'context7',
          description: '',
          version: '1.0.0',
          directory: 'context7',
          marketplaceOwner: 'anthropics',
          marketplaceName: marketplaceName,
          marketplaceBranch: 'main',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    final configDir = layout.sessionRuntimeToolDir('workspace-1', 's3', 'flashskyai');
    final known = jsonDecode(
      await File(p.join(configDir, 'plugins', 'known_marketplaces.json'))
          .readAsString(),
    ) as Map<String, Object?>;
    final entry = known[marketplaceName] as Map;
    final installLocation = entry['installLocation'] as String;
    expect(installLocation, contains('plugins${Platform.pathSeparator}marketplaces'));
    expect(
      File(
        p.join(installLocation, '.flashskyai-plugin', 'marketplace.json'),
      ).existsSync(),
      isTrue,
    );
    if (Platform.isLinux || Platform.isMacOS) {
      expect(Link(installLocation).existsSync(), isFalse);
    }
    expect((entry['source'] as Map)['source'], 'directory');
  });

  test('maps manifest name to marketplace catalog name for enabledPlugins', () async {
    const marketplaceName = 'claude-plugins-official';
    final cacheDir = Directory(
      p.join(
        base.path,
        'plugins',
        'marketplace-cache',
        'anthropics',
        '$marketplaceName@main',
      ),
    )..createSync(recursive: true);
    Directory(p.join(cacheDir.path, '.claude-plugin')).createSync();
    await File(
      p.join(cacheDir.path, '.claude-plugin', 'marketplace.json'),
    ).writeAsString(
      jsonEncode({
        'name': marketplaceName,
        'owner': {'name': 'Anthropic'},
        'plugins': [
          {
            'name': '42crunch-api-security-testing',
            'version': '1.0.0',
            'source': {
              'source': 'git-subdir',
              'path': 'plugins/api-security-testing',
            },
          },
        ],
      }),
    );

    final teamPlugins = Directory(layout.identityPluginsDir('t1'))
      ..createSync(recursive: true);
    final bundle = Directory(p.join(teamPlugins.path, 'api-security-testing'))
      ..createSync();
    Directory(p.join(bundle.path, '.claude-plugin')).createSync();
    await File(
      p.join(bundle.path, '.claude-plugin', 'plugin.json'),
    ).writeAsString(
      jsonEncode({'name': 'api-security-testing', 'version': '1.0.0'}),
    );

    await layout.provisionSessionPluginsFromIdentity('workspace-1', 's4', 't1', 'flashskyai');

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's4',
      tool: CliTool.flashskyai,
      team: const TeamProfile(
        id: 't1',
        name: 'Team',
        pluginIds: ['anthropics/claude-plugins-official/api-security-testing'],
      ),
      installedCatalog: const [
        Plugin(
          id: 'anthropics/claude-plugins-official/api-security-testing',
          name: 'api-security-testing',
          description: '',
          version: '1.0.0',
          directory: 'anthropics__claude-plugins-official__api-security-testing',
          marketplaceOwner: 'anthropics',
          marketplaceName: marketplaceName,
          marketplaceBranch: 'main',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    final configDir = layout.sessionRuntimeToolDir('workspace-1', 's4', 'flashskyai');
    final settings = jsonDecode(
      await File(p.join(configDir, 'settings.json')).readAsString(),
    ) as Map<String, Object?>;
    expect(
      (settings['enabledPlugins'] as Map)['42crunch-api-security-testing@$marketplaceName'],
      isTrue,
    );
  });

  test('writeForSession skips registry rewrite when inputs unchanged', () async {
    await seedMemberPlugin(
      teamId: 't1',
      sessionId: 's5',
      tool: CliTool.flashskyai.value,
      pluginName: 'demo',
    );

    const team = TeamProfile(
      id: 't1',
      name: 'Team',
      pluginIds: ['local/demo'],
    );
    const catalog = [
      Plugin(
        id: 'local/demo',
        name: 'demo',
        description: '',
        version: '2.0.0',
        directory: 'demo',
        capabilities: PluginCapabilities(),
        installedAt: 0,
        updatedAt: 0,
      ),
    ];

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's5',
      tool: CliTool.flashskyai,
      team: team,
      installedCatalog: catalog,
    );

    final stampBefore = await File(
      p.join(
        layout.sessionRuntimeToolDir('workspace-1', 's5', 'flashskyai'),
        'plugins',
        '.teampilot-registry-stamp.json',
      ),
    ).readAsString();

    await registry.writeForSession(
      workspaceId: 'workspace-1',
      teamId: 't1',
      sessionId: 's5',
      tool: CliTool.flashskyai,
      team: team,
      installedCatalog: catalog,
    );

    final stampAfter = await File(
      p.join(
        layout.sessionRuntimeToolDir('workspace-1', 's5', 'flashskyai'),
        'plugins',
        '.teampilot-registry-stamp.json',
      ),
    ).readAsString();
    expect(stampAfter, stampBefore);
  });
}
