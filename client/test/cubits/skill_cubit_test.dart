import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_fetch_service.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-cubit-');
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
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SkillCubit cubitWith(SkillAcquisitionEngine engine) => SkillCubit(
    SkillRepository(),
    registryConfigService: SkillRegistryConfigService(
      teampilotRoot: AppStorage.paths.basePath,
    ),
    initialSources: const [],
    rebuildSources: (c) => const [],
    acquisitionEngine: engine,
  );

  test(
    'installTeamDependency uses scriptUrl sugar through acquisition engine',
    () async {
      const expectedId = 'script:custom/gstack';
      var engineCalls = 0;
      final engine = SkillAcquisitionEngine(
        runner: (_) async {
          engineCalls++;
          return const CliInstallerCommandResult(exitCode: 0);
        },
        installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
          final id = idOverride ?? d.expectedLocalId;
          final directory = d.directory.isEmpty ? 'gstack' : d.directory;
          return Skill(
            id: id,
            name: d.name,
            description: '',
            directory: directory,
            installedAt: 1,
            updatedAt: 1,
          );
        },
        listSkillDirsWithSkillMd: () async {
          if (engineCalls == 0) return {};
          return {'gstack'};
        },
        isLocalAcquireSupported: () => true,
        registerDirectory:
            ({required String id, required String directory}) async {
              return Skill(
                id: id,
                name: directory,
                description: '',
                directory: directory,
                installedAt: 1,
                updatedAt: 1,
              );
            },
      );

      final cubit = cubitWith(engine);

      final id = await cubit.installTeamDependency(
        const SkillDependencyRef(
          name: 'gstack',
          id: expectedId,
          scriptUrl: 'https://example.com/install-gstack.sh',
          repoOwner: '',
          repoName: '',
          repoBranch: 'main',
          directory: 'gstack',
        ),
      );

      expect(id, expectedId);
      expect(engineCalls, 1);
      expect(cubit.state.busyIds, isEmpty);
    },
  );

  test(
    'installTeamDependency returns expectedLocalId when already installed',
    () async {
      const expectedId = 'obra/superpowers:brainstorming';
      var engineCalls = 0;
      final engine = SkillAcquisitionEngine(
        installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
          engineCalls++;
          throw StateError('should not install');
        },
        runner: (_) async {
          engineCalls++;
          return const CliInstallerCommandResult(exitCode: 1);
        },
        isLocalAcquireSupported: () => true,
      );

      final cubit = cubitWith(engine);
      cubit.emit(
        cubit.state.copyWith(
          installed: const [
            Skill(
              id: expectedId,
              name: 'Brainstorming',
              description: '',
              directory: 'brainstorming',
              installedAt: 1,
              updatedAt: 1,
            ),
          ],
        ),
      );

      final id = await cubit.installTeamDependency(
        const SkillDependencyRef(
          repoOwner: 'obra',
          repoName: 'superpowers',
          repoBranch: 'main',
          directory: 'skills/brainstorming',
          name: 'Brainstorming',
        ),
      );

      expect(id, expectedId);
      expect(engineCalls, 0);
      expect(cubit.state.busyIds, isEmpty);
    },
  );

  test('manual mode syncs repos without disk cache once', () async {
    final fetch = _FakeSkillFetch();
    final cubit = cubitWithRepos(SkillRepository(fetch: fetch));

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('manual mode with disk cache does not hit network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    expect(fetch.downloads, 1);
    final cubit = cubitWithRepos(
      SkillRepository(fetch: fetch, repoCache: cache),
    );

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(fetch.shaChecks, 0);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('manual mode with force always checks remote', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final cubit = cubitWithRepos(
      SkillRepository(fetch: fetch, repoCache: cache),
    );

    await cubit.ensureDiscoveryLoaded(force: true);

    expect(fetch.shaChecks, 0);
    expect(fetch.downloads, 2);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with fresh cache skips network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.load();
    await settings.setAutoRefreshEnabled(true);
    final cubit = cubitWithRepos(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 0);
    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with stale cache checks remote', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final fs = AppStorage.fs;
    final metaPath = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(_discoveryRepo),
      'meta.json',
    );
    final stale = SkillRepoCacheMeta(
      configuredBranch: 'main',
      resolvedBranch: 'main',
      commitSha: 'abc123',
      syncedAtMs: 1,
    );
    await fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(stale.toJson()),
    );
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = cubitWithRepos(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 1);
  });

  test(
    'unified search keeps successful entries and records sanitized failures',
    () async {
      final healthy = _DiscoverySource(
        id: 'healthy',
        label: 'Healthy source',
        entries: [
          _marketplaceSkill(
            key: 'healthy-skill',
            name: 'Healthy skill',
            adoptionCount: 20,
          ),
        ],
      );
      final broken = _DiscoverySource(
        id: 'broken',
        label: 'Broken source',
        error: StateError(
          'Bearer secret-token response body: private response payload',
        ),
      );
      final cubit = cubitWithDiscoverySources([healthy, broken]);

      await cubit.unifiedBrowse();

      expect(cubit.state.discoveryEntries, hasLength(1));
      expect(cubit.state.discoveryEntries.single.skill.key, 'healthy-skill');
      expect(cubit.state.discoveryError, isNull);
      expect(cubit.state.discoveryFailures, hasLength(1));
      expect(cubit.state.discoveryFailures.single.sourceId, 'broken');
      expect(cubit.state.discoveryFailures.single.sourceLabel, 'Broken source');
      expect(
        cubit.state.discoveryFailures.single.message,
        contains('[REDACTED]'),
      );
      expect(
        cubit.state.discoveryFailures.single.message,
        isNot(contains('private response payload')),
      );
    },
  );

  test(
    'refresh keeps the previous results visible while a source is pending',
    () async {
      final source = _DiscoverySource(
        id: 'source',
        label: 'Source',
        entries: [
          _marketplaceSkill(
            key: 'cached-skill',
            name: 'Cached skill',
            adoptionCount: 1,
          ),
        ],
      );
      final cubit = cubitWithDiscoverySources([source]);
      await cubit.unifiedBrowse();

      final pending = Completer<SkillRegistryPage>();
      source.nextResult = pending.future;
      final refresh = cubit.unifiedBrowse();
      await _waitForCondition(() => cubit.state.discoveryLoading);

      expect(cubit.state.discoveryEntries.single.skill.key, 'cached-skill');

      pending.completeError(StateError('offline'));
      await refresh;

      expect(cubit.state.discoveryEntries.single.skill.key, 'cached-skill');
      expect(cubit.state.discoveryFailures.single.message, contains('offline'));
    },
  );

  test('discovery sort is local and defaults to adoption descending', () async {
    final source = _DiscoverySource(
      id: 'source',
      label: 'Source',
      entries: [
        _marketplaceSkill(key: 'missing', name: 'Zed', updatedAtMs: 300),
        _marketplaceSkill(
          key: 'low',
          name: 'Low',
          adoptionCount: 2,
          updatedAtMs: 100,
        ),
        _marketplaceSkill(
          key: 'high',
          name: 'High',
          adoptionCount: 10,
          updatedAtMs: 200,
        ),
        _marketplaceSkill(
          key: 'tie-new',
          name: 'Tie new',
          adoptionCount: 10,
          updatedAtMs: 300,
        ),
      ],
    );
    final cubit = cubitWithDiscoverySources([source]);
    await cubit.unifiedBrowse();
    final searchCount = source.searchCount;

    expect(cubit.state.discoverySort, CatalogSortKey.adoption);
    expect(cubit.state.discoveryEntries.map((entry) => entry.skill.key), [
      'tie-new',
      'high',
      'low',
      'missing',
    ]);

    cubit.setDiscoverySort(CatalogSortKey.name);

    expect(source.searchCount, searchCount);
    expect(cubit.state.discoveryEntries.map((entry) => entry.skill.key), [
      'high',
      'low',
      'tie-new',
      'missing',
    ]);
  });
}

Future<void> _waitForCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SkillCubit cubitWithDiscoverySources(List<SkillRegistrySource> sources) {
  return SkillCubit(
    SkillRepository(),
    registryConfigService: SkillRegistryConfigService(
      teampilotRoot: AppStorage.paths.basePath,
    ),
    initialSources: sources,
    rebuildSources: (c) => sources,
  );
}

MarketplaceSkill _marketplaceSkill({
  required String key,
  required String name,
  int? adoptionCount,
  int? updatedAtMs,
}) {
  return MarketplaceSkill(
    key: key,
    name: name,
    description: 'description',
    repoOwner: 'owner',
    repoName: 'repo',
    directory: key,
    githubUrl: 'https://github.com/owner/repo',
    metrics: CatalogMetrics(
      adoptionCount: adoptionCount,
      updatedAtMs: updatedAtMs,
    ),
  );
}

class _DiscoverySource implements SkillRegistrySource {
  _DiscoverySource({
    required this.id,
    required this.label,
    this.entries = const [],
    this.error,
  });

  @override
  final String id;
  @override
  final String label;
  final List<MarketplaceSkill> entries;
  final Object? error;
  Future<SkillRegistryPage>? nextResult;
  int searchCount = 0;

  @override
  bool get enabled => true;

  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery query) async {
    searchCount++;
    final pending = nextResult;
    nextResult = null;
    if (pending != null) return pending;
    if (error != null) throw error!;
    return SkillRegistryPage(entries: entries, total: entries.length);
  }

  @override
  Future<void> setApiKey(String key) async {}

  @override
  Future<void> testConnection() async {}
}

const _discoveryRepo = SkillRepo(owner: 'acme', name: 'skills', branch: 'main');

SkillCubit cubitWithRepos(
  SkillRepository repo, {
  DiscoverySettingsCubit? discoverySettings,
}) {
  final gitSource = GitRepoRegistrySource(
    SkillRegistrySourceConfig(
      id: 'git-acme-skills',
      kind: SkillRegistryKind.gitRepo,
      label: 'acme/skills',
      gitOwner: 'acme',
      gitName: 'skills',
      gitBranch: 'main',
    ),
    discoverableProvider: () => repo.readCachedDiscoverable(_discoveryRepo),
    syncNow: () async {},
  );
  return SkillCubit(
    repo,
    registryConfigService: SkillRegistryConfigService(
      teampilotRoot: AppStorage.paths.basePath,
    ),
    initialSources: [gitSource],
    rebuildSources: (c) => [gitSource],
    discoverySettings: discoverySettings,
  );
}

class _FakeSkillFetch extends SkillFetchService {
  int downloads = 0;
  int shaChecks = 0;

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    shaChecks++;
    return null;
  }

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  downloadRepoEntries(
    SkillRepo repo, {
    Filesystem? fs,
    String? persistentGitPath,
  }) async {
    downloads++;
    return (
      entries: {
        'demo/SKILL.md': Uint8List.fromList(
          utf8.encode('---\nname: demo\ndescription: d\n---\n'),
        ),
      },
      branch: repo.branch,
      commitSha: 'abc123',
    );
  }
}
