import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_repo_disk_cache_service.dart';
import 'package:teampilot/services/plugin/plugin_repo_git_service.dart';
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

  DiscoverablePlugin discoverable(String name, {int? adoption, int? updated}) =>
      DiscoverablePlugin(
        key: 'owner/marketplace/$name',
        name: name,
        description: 'description',
        version: '1.0.0',
        source: 'plugins/$name',
        marketplaceOwner: 'owner',
        marketplaceName: 'marketplace',
        marketplaceBranch: 'main',
        metrics: CatalogMetrics(adoptionCount: adoption, updatedAtMs: updated),
      );

  test(
    'defaults discovery to adoption descending with missing values last',
    () {
      final cubit = PluginCubit.test(
        PluginState(
          discoverable: [
            discoverable('missing'),
            discoverable('low', adoption: 2),
            discoverable('high', adoption: 9),
          ],
        ),
      );

      expect(cubit.state.discoverable.map((plugin) => plugin.name), [
        'high',
        'low',
        'missing',
      ]);
    },
  );

  test('setDiscoverySort reorders only the plugin discovery directory', () {
    final cubit = PluginCubit.test(
      PluginState(
        discoverable: [
          discoverable('old', adoption: 9, updated: 1),
          discoverable('new', adoption: 1, updated: 2),
        ],
      ),
    );

    cubit.setDiscoverySort(CatalogSortKey.updated);

    expect(cubit.state.discoverySort, CatalogSortKey.updated);
    expect(cubit.state.discoverable.map((plugin) => plugin.name), [
      'new',
      'old',
    ]);
  });

  test('discovery failures are immutable and preserve successful results', () {
    final failure = const CatalogSourceFailure(
      sourceId: 'owner/failed@main',
      sourceLabel: 'owner/failed',
      message: 'network unavailable',
    );
    final cubit = PluginCubit.test(
      PluginState(
        discoverable: [discoverable('available', adoption: 3)],
        discoveryFailures: [failure],
      ),
    );

    expect(cubit.state.discoverable.single.name, 'available');
    expect(cubit.state.discoveryFailures, [failure]);
    expect(
      () => cubit.state.discoveryFailures.add(failure),
      throwsUnsupportedError,
    );
  });

  test(
    'refresh keeps successful entries and cached entries from failed sources',
    () async {
      final successful = PluginMarketplace(owner: 'owner', name: 'success');
      final failed = PluginMarketplace(owner: 'owner', name: 'failed');
      final cachedFromFailedSource = discoverable(
        'cached',
        adoption: 1,
      ).copyWith(marketplaceName: failed.name);
      final cache = _PartialPluginCache(
        successful: successful,
        failed: failed,
        result: discoverable(
          'fresh',
          adoption: 10,
        ).copyWith(marketplaceName: successful.name),
        cachedFromFailedSource: cachedFromFailedSource,
      );
      final cubit = PluginCubit.test(
        PluginState(
          marketplaces: [successful, failed],
          discoverable: [cachedFromFailedSource],
        ),
        diskCache: cache,
      );

      await cubit.refreshDiscoverable(force: true);

      expect(cubit.state.discoverable.map((item) => item.name), [
        'fresh',
        'cached',
      ]);
      expect(cubit.state.discoveryFailures.single.sourceLabel, failed.fullName);
      expect(cubit.state.errorMessage, isNull);
      expect(
        cubit.state.discoveryFailures.single.message,
        contains('REDACTED'),
      );
    },
  );

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

  test(
    'ensureDiscoveryLoaded does not re-sync when list is populated',
    () async {
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
    },
  );

  test('uninstall calls team cleanup before removing plugin files', () async {
    final order = <String>[];
    final repo = PluginRepository();
    final svc = repo.install;
    final src = Directory(p.join(tmp.path, 'src'))..createSync();
    Directory(p.join(src.path, '.claude-plugin')).createSync();
    File(
      p.join(src.path, '.claude-plugin', 'plugin.json'),
    ).writeAsStringSync('{"name":"foo","version":"0.1.0"}');
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
    File(
      p.join(orphan.path, '.claude-plugin', 'plugin.json'),
    ).writeAsStringSync(
      '{"name":"orphan","version":"1.0.0","description":"x"}',
    );

    final repo = PluginRepository();
    final scanned = await repo.scanUnmanaged();
    expect(scanned, hasLength(1));
    expect(scanned.single.name, 'orphan');
  });

  test('manual mode syncs marketplaces without disk cache once', () async {
    final git = _FakePluginGit();
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: PluginRepoDiskCacheService(gitService: git),
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;
    expect(enabledCount, greaterThan(0));

    await cubit.ensureDiscoveryLoaded();

    expect(git.syncCheckouts, enabledCount);
    expect(git.resolveShaCalls, 0);
  });

  test('manual mode with disk cache does not hit network', () async {
    final git = _FakePluginGit();
    final diskCache = PluginRepoDiskCacheService(gitService: git);
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;

    await cubit.ensureDiscoveryLoaded();
    expect(git.syncCheckouts, enabledCount);

    final cubit2 = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
    );
    await cubit2.load();

    await cubit2.ensureDiscoveryLoaded();

    expect(git.syncCheckouts, enabledCount);
    expect(git.resolveShaCalls, 0);
    expect(cubit2.state.discoverable, isNotEmpty);
  });

  test('auto mode with stale cache checks remote SHA', () async {
    final git = _FakePluginGit();
    final diskCache = PluginRepoDiskCacheService(gitService: git);
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
      discoverySettings: settings,
    );
    await cubit.load();
    final enabledCount = cubit.state.marketplaces
        .where((m) => m.enabled)
        .length;

    await cubit.ensureDiscoveryLoaded();
    expect(git.syncCheckouts, enabledCount);

    // 把缓存 meta 改成过期，再走自动刷新 → 应检查远端 SHA（remote null → 保留缓存）
    final market = cubit.state.marketplaces.firstWhere((m) => m.enabled);
    final metaPath = AppStorage.fs.pathContext.join(
      AppStorage.paths.pluginMarketplaceCacheDir,
      PluginRepoDiskCacheService.repoKey(market),
      '.teampilot-plugin-cache-meta.json',
    );
    await AppStorage.fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert({
        'configuredBranch': 'main',
        'resolvedBranch': 'main',
        'commitSha': 'abc123',
        'syncedAtMs': 1,
      }),
    );

    final cubit2 = PluginCubit(
      repository: PluginRepository(),
      installService: PluginRepository().install,
      repoService: PluginRepoService(),
      diskCache: diskCache,
      discoverySettings: settings,
    );
    await cubit2.load();

    await cubit2.ensureDiscoveryLoaded();

    expect(git.resolveShaCalls, 1);
  });
}

class _FakePluginGit extends PluginRepoGitService {
  int syncCheckouts = 0;
  int resolveShaCalls = 0;

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  syncCheckout(
    PluginMarketplace marketplace,
    Filesystem fs,
    String workDirPath,
  ) async {
    syncCheckouts++;
    await fs.ensureDir(workDirPath);
    await fs.ensureDir(fs.pathContext.join(workDirPath, '.claude-plugin'));
    await fs.writeString(
      fs.pathContext.join(workDirPath, '.claude-plugin', 'marketplace.json'),
      '{"name":"m","plugins":[{"name":"p1","description":"d","version":"1.0.0","source":"./plugins/p1"}]}',
    );
    return (
      entries: const <String, Uint8List>{},
      branch: marketplace.branch,
      commitSha: 'abc123',
    );
  }

  @override
  Future<({String sha, String branch})?> resolveRemoteShaWithFallback(
    String owner,
    String name,
    String configuredBranch,
  ) async {
    resolveShaCalls++;
    return null;
  }
}

class _PartialPluginCache extends PluginRepoDiskCacheService {
  _PartialPluginCache({
    required this.successful,
    required this.failed,
    required this.result,
    required this.cachedFromFailedSource,
  });

  final PluginMarketplace successful;
  final PluginMarketplace failed;
  final DiscoverablePlugin result;
  final DiscoverablePlugin cachedFromFailedSource;

  @override
  Future<String> syncMarketplace(
    PluginMarketplace marketplace, {
    bool force = false,
    Duration? maxStaleness,
  }) async {
    if (marketplace.fullName == failed.fullName) {
      throw StateError('Bearer sk-secret-12345678 response body: private');
    }
    return '/tmp/${marketplace.fullName}';
  }

  @override
  Future<List<DiscoverablePlugin>> discoverablePluginsCached(
    PluginMarketplace marketplace,
  ) async {
    if (marketplace.fullName == successful.fullName) {
      return [result];
    }
    if (marketplace.fullName == failed.fullName) {
      return [cachedFromFailedSource];
    }
    return const [];
  }
}
