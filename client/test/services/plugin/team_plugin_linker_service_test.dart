import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/plugin/team_plugin_linker_service.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-link-');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('syncForTeam links CLI bundles under team plugin dir on Unix', () async {
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins', 'installed'))
      ..createSync(recursive: true);
    final pluginDir = Directory(p.join(pluginsRoot.path, 'acme__market__p1'))
      ..createSync();
    Directory(p.join(pluginDir.path, '.claude-plugin')).createSync();
    File(
      p.join(pluginDir.path, '.claude-plugin', 'plugin.json'),
    ).writeAsStringSync('{"name":"p1","version":"1.0.0"}');

    final svc = TeamPluginLinkerService(appPluginsRoot: pluginsRoot.path);
    final result = await svc.syncForTeam(
      teamId: 't1',
      pluginIds: ['acme/market/p1'],
      installed: const [
        Plugin(
          id: 'acme/market/p1',
          name: 'p1',
          description: '',
          version: '1.0.0',
          directory: 'acme__market__p1',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    expect(result.errors, isEmpty);
    expect(result.linked, ['p1']);
    final teamBundle = Directory(
      p.join(tmp.path, 'config-profiles', 'teams', 't1', 'flashskyai', 'plugins', 'p1'),
    );
    expect(teamBundle.existsSync(), isTrue);
    if (Platform.isLinux || Platform.isMacOS) {
      expect(Link(teamBundle.path).existsSync(), isTrue);
    }
    expect(
      File(p.join(teamBundle.path, '.claude-plugin', 'plugin.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(teamBundle.path, '.flashskyai-plugin', 'plugin.json'))
          .existsSync(),
      isTrue,
    );
  });

  test('syncForTeam removes stale links not in pluginIds', () async {
    final teamPluginsDir = Directory(
      p.join(tmp.path, 'config-profiles', 'teams', 't1', 'flashskyai', 'plugins'),
    )..createSync(recursive: true);
    Directory(p.join(teamPluginsDir.path, 'old-plugin')).createSync();

    final svc = TeamPluginLinkerService(
      appPluginsRoot: p.join(tmp.path, 'plugins', 'installed'),
    );
    final result = await svc.syncForTeam(
      teamId: 't1',
      pluginIds: const [],
      installed: const [],
    );
    expect(result.linked, isEmpty);
    expect(
      Directory(p.join(teamPluginsDir.path, 'old-plugin')).existsSync(),
      isFalse,
    );
  });

  test('syncForTeam reports skippedMissingIds when plugin source is missing',
      () async {
    final svc = TeamPluginLinkerService(
      appPluginsRoot: p.join(tmp.path, 'plugins', 'installed'),
    );
    final result = await svc.syncForTeam(
      teamId: 't1',
      pluginIds: ['gone/market/p'],
      installed: const [],
    );
    expect(result.skippedMissingIds, ['gone/market/p']);
  });

  test('syncForTeam resolves plugin-name collision with owner__name fallback',
      () async {
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins', 'installed'))
      ..createSync(recursive: true);
    void writeBundle(Directory dir, String name) {
      Directory(p.join(dir.path, '.claude-plugin')).createSync();
      File(p.join(dir.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
        '{"name":"$name","version":"1.0.0"}',
      );
    }

    final dirA = Directory(p.join(pluginsRoot.path, 'acmeA__market__shared'))
      ..createSync();
    writeBundle(dirA, 'shared');
    final dirB = Directory(p.join(pluginsRoot.path, 'acmeB__market__shared'))
      ..createSync();
    writeBundle(dirB, 'shared');

    final svc = TeamPluginLinkerService(appPluginsRoot: pluginsRoot.path);
    final result = await svc.syncForTeam(
      teamId: 't1',
      pluginIds: ['acmeA/market/shared', 'acmeB/market/shared'],
      installed: [
        const Plugin(
          id: 'acmeA/market/shared',
          name: 'shared',
          description: '',
          version: '1.0.0',
          directory: 'acmeA__market__shared',
          marketplaceOwner: 'acmeA',
          marketplaceName: 'market',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
        const Plugin(
          id: 'acmeB/market/shared',
          name: 'shared',
          description: '',
          version: '1.0.0',
          directory: 'acmeB__market__shared',
          marketplaceOwner: 'acmeB',
          marketplaceName: 'market',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    expect(result.conflictResolutions, hasLength(1));
    expect(result.linked, contains('shared'));
    expect(result.linked, contains('acmeB__shared'));
  });
}
