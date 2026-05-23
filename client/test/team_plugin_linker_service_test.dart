import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/runtime_storage_context.dart';
import 'package:teampilot/services/team_plugin_linker_service.dart';

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

  test('syncForTeam creates links under team plugin dir for each enabled plugin',
      () async {
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins'))..createSync();
    final pluginDir = Directory(p.join(pluginsRoot.path, 'acme__market__p1'))
      ..createSync();
    File(p.join(pluginDir.path, 'plugin.json')).writeAsStringSync('{}');

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
    expect(result.linked, ['acme__market__p1']);
  });

  test('syncForTeam removes stale links not in pluginIds', () async {
    final teamPluginsDir = Directory(
      p.join(tmp.path, 'config-profiles', 'teams', 't1', 'flashskyai', 'plugins'),
    )..createSync(recursive: true);
    Directory(p.join(teamPluginsDir.path, 'old-plugin')).createSync();

    final svc = TeamPluginLinkerService(appPluginsRoot: p.join(tmp.path, 'plugins'));
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
    final svc = TeamPluginLinkerService(appPluginsRoot: p.join(tmp.path, 'plugins'));
    final result = await svc.syncForTeam(
      teamId: 't1',
      pluginIds: ['gone/market/p'],
      installed: const [],
    );
    expect(result.skippedMissingIds, ['gone/market/p']);
  });
}
