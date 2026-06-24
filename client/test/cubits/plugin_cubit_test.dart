import 'dart:io';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-cubit-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('load() populates installed + marketplaces', () async {
    final repo = PluginRepository();
    final cubit = PluginCubit(
      repository: repo,
      installService: repo.install,
      repoService: PluginRepoService(),
    );
    await cubit.load();
    expect(cubit.state.status, PluginLoadStatus.ready);
    expect(cubit.state.marketplaces, isNotEmpty);
    expect(cubit.state.installed, isEmpty);
    expect(cubit.state.discoverable, isEmpty);
    expect(cubit.state.discoveryLoading, isFalse);
  });

  test('ensureDiscoveryLoaded does not re-sync when list is populated', () async {
    final repo = PluginRepository();
    final cubit = PluginCubit(
      repository: repo,
      installService: repo.install,
      repoService: PluginRepoService(),
    );
    cubit.emit(
      cubit.state.copyWith(
        discoverable: const [
          DiscoverablePlugin(
            key: 'a:b:c',
            name: 'c',
            description: '',
            version: '1',
            source: '.',
            marketplaceOwner: 'o',
            marketplaceName: 'n',
            marketplaceBranch: 'main',
          ),
        ],
      ),
    );
    await cubit.ensureDiscoveryLoaded();
    expect(cubit.state.discoveryLoading, isFalse);
  });

  test('uninstall calls team cleanup before removing plugin files', () async {
    final order = <String>[];
    final repo = PluginRepository();
    final svc = repo.install;
    final src = Directory(p.join(tmp.path, 'src'))..createSync();
    Directory(p.join(src.path, '.claude-plugin')).createSync();
    File(p.join(src.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"foo","version":"0.1.0"}');
    await svc.installFromDirectory(src);

    final cubit = PluginCubit(
      repository: repo,
      installService: repo.install,
      repoService: PluginRepoService(),
      onPluginUninstalled: (_) async {
        order.add('teams');
        final list = await repo.loadAll();
        expect(list, isNotEmpty);
      },
    );
    await cubit.load();
    await cubit.uninstall(cubit.state.installed.first);
    expect(order, ['teams']);
    expect(await repo.loadAll(), isEmpty);
  });

  test('scanUnmanaged finds plugin dir without manifest row', () async {
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins', 'installed'))
      ..createSync(recursive: true);
    final orphan = Directory(p.join(pluginsRoot.path, 'orphan'))..createSync();
    Directory(p.join(orphan.path, '.claude-plugin')).createSync();
    File(p.join(orphan.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
      '{"name":"orphan","version":"1.0.0","description":"x"}',
    );

    final repo = PluginRepository();
    final scanned = await repo.scanUnmanaged();
    expect(scanned, hasLength(1));
    expect(scanned.single.name, 'orphan');
  });
}
