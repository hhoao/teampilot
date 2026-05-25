@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_install_service.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/plugin/team_plugin_linker_service.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-integ-');
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
    AppPathsBootstrapper.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('full lifecycle: install -> enable for team -> sync -> uninstall',
      () async {
    // 1. Create a source plugin directory
    final src = Directory(p.join(tmp.path, 'pluginsrc'))..createSync();
    Directory(p.join(src.path, '.claude-plugin')).createSync();
    File(p.join(src.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
      '{"name":"lifecycle-test","version":"1.0.0","description":"integration test plugin"}',
    );

    // 2. Install the plugin
    final installSvc = PluginInstallService();
    final plugin = await installSvc.installFromDirectory(src);
    expect(plugin.name, 'lifecycle-test');

    // 3. Verify plugin persisted to plugins.json
    final repo = PluginRepository();
    var installed = await repo.loadAll();
    expect(installed.any((p) => p.id == plugin.id), isTrue);

    // 4. Create a team with this plugin enabled
    final teamRepo = TeamRepository(rootDir: p.join(tmp.path, 'teams'));
    final team = TeamConfig(
      id: 'integ-team',
      name: 'Integration Team',
      pluginIds: [plugin.id],
    );
    await teamRepo.saveTeams([team]);

    // 5. Sync plugins via linker
    final linker = TeamPluginLinkerService(
      appPluginsRoot: p.join(tmp.path, 'plugins', 'installed'),
    );
    final result = await linker.syncForTeam(
      teamId: 'integ-team',
      pluginIds: team.pluginIds,
      installed: installed,
    );
    expect(result.errors, isEmpty);
    expect(result.linked, hasLength(1));
    final teamPluginDir = Directory(
      p.join(
        tmp.path,
        'config-profiles',
        'teams',
        'integ-team',
        'flashskyai',
        'plugins',
        'lifecycle-test',
      ),
    );
    expect(await teamPluginDir.exists(), isTrue);

    // 6. Remove plugin from team, sync again
    await linker.syncForTeam(
      teamId: 'integ-team',
      pluginIds: const [],
      installed: installed,
    );
    expect(await teamPluginDir.exists(), isFalse);

    // 7. Uninstall plugin
    await installSvc.uninstall(plugin);
    installed = await repo.loadAll();
    expect(installed.any((p) => p.id == plugin.id), isFalse);
  });
}
