import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeRegistry implements SkillRegistrySource {
  _FakeRegistry(
    this.id,
    this.total, {
    this.pageSize = 2,
    this.quota = false,
  });

  @override
  final String id;
  final int total;
  final int pageSize;
  final bool quota;

  /// When true, the next `search` call throws and the flag resets.
  bool failNext = false;
  final List<SkillRegistryQuery> queries = [];

  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async {
    queries.add(q);
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    if (quota) throw MarketplaceQuotaException('quota');
    final start = (q.page - 1) * pageSize;
    final end = start + pageSize;
    final items = <MarketplaceSkill>[
      for (var i = start; i < end && i < total; i++)
        MarketplaceSkill(
          key: '$id-$i',
          name: '$id-$i',
          description: 'd',
          repoOwner: id,
          repoName: 'r',
          directory: 'dir/$i',
          githubUrl: 'https://github.com/$id/r',
        ),
    ];
    return SkillRegistryPage(
      entries: items,
      hasNext: end < total,
      total: total,
    );
  }

  @override
  Future<void> testConnection() async {}

  @override
  Future<void> setApiKey(String key) async {}
}

/// Counts repo-cache syncs without touching the network (the cubit's git
/// background sync goes through `SkillRepository.syncRepoCache` →
/// `SkillRepoDiskCacheService.ensureSynced`, not the source's `syncNow`).
class _CountingRepoCache extends SkillRepoDiskCacheService {
  int syncCalls = 0;

  @override
  Future<SkillRepoSyncResult> ensureSynced(
    SkillRepo repo, {
    bool force = false,
    List<String> requiredRelativePaths = const [],
  }) async {
    syncCalls++;
    return const SkillRepoSyncResult(skills: [], updated: false, repoKey: '');
  }
}

Future<void> _waitFor(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SkillCubit _cubit(
  List<SkillRegistrySource> sources,
  SkillRegistryConfigService cfg,
  SkillRepository repo,
) => SkillCubit(
  repo,
  registryConfigService: cfg,
  initialSources: sources,
  rebuildSources: (c) => sources,
);

void main() {
  late Directory tmp;
  late SkillRegistryConfigService cfg;
  late SkillRepository repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-unified-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    cfg = SkillRegistryConfigService(teampilotRoot: paths.basePath);
    repo = SkillRepository();
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('unifiedBrowse merges page 1 from all sources', () async {
    final a = _FakeRegistry('a', 3);
    final b = _FakeRegistry('b', 3);
    final cubit = _cubit([a, b], cfg, repo);
    await cubit.unifiedBrowse();
    final s = cubit.state;
    expect(s.discoveryEntries.length, 4); // 2 per source (pageSize 2)
    expect(s.discoveryEntries.map((e) => e.sourceId).toSet(), {'a', 'b'});
    expect(s.discoveryHasNext['a'], isTrue);
    expect(s.discoveryBrowsing, isTrue);
  });

  test('unifiedLoadMore appends next pages and advances cursors', () async {
    final a = _FakeRegistry('a', 3);
    final b = _FakeRegistry('b', 3);
    final cubit = _cubit([a, b], cfg, repo);
    await cubit.unifiedBrowse();
    await cubit.unifiedLoadMore();
    final s = cubit.state;
    expect(s.discoveryEntries.length, 6); // a-0..2 + b-0..2
    expect(s.discoveryPages['a'], 2);
    expect(
      s.discoveryEntries
          .where((e) => e.sourceId == 'a')
          .map((e) => e.skill.key),
      contains('a-2'),
    );
    expect(s.discoveryHasNext['a'], isFalse);
  });

  test('unifiedSearch with short query falls back to browse', () async {
    final a = _FakeRegistry('a', 3, pageSize: 3);
    final cubit = _cubit([a], cfg, repo);
    await cubit.unifiedSearch('x');
    expect(cubit.state.discoveryEntries.length, 3);
    expect(a.queries.last.query, '');
  });

  test('quota error surfaces discoveryError key', () async {
    final a = _FakeRegistry('a', 3, quota: true);
    final cubit = _cubit([a], cfg, repo);
    await cubit.unifiedBrowse();
    expect(cubit.state.discoveryError, marketplaceQuotaErrorKey);
    expect(cubit.state.discoveryEntries, isEmpty);
  });

  test('unifiedLoadMore skips exhausted sources and pages the rest', () async {
    final a = _FakeRegistry('a', 3, pageSize: 3);
    final b = _FakeRegistry('b', 5, pageSize: 3);
    final cubit = _cubit([a, b], cfg, repo);
    await cubit.unifiedBrowse();
    expect(a.queries, hasLength(1));
    expect(b.queries, hasLength(1));
    expect(cubit.state.discoveryHasNext['a'], isFalse);
    expect(cubit.state.discoveryHasNext['b'], isTrue);

    await cubit.unifiedLoadMore();
    expect(a.queries, hasLength(1)); // exhausted: never re-queried
    expect(b.queries, hasLength(2));
    expect(cubit.state.discoveryEntries, hasLength(8)); // 3 + 3 + 2
    expect(cubit.state.discoveryPages['a'], 1); // not corrupted
    expect(cubit.state.discoveryPages['b'], 2);
    expect(cubit.state.discoveryHasNext['b'], isFalse);
    expect(cubit.state.discoveryError, isNull);
  });

  test('unifiedLoadMore error keeps source retryable and surfaces error',
      () async {
    final a = _FakeRegistry('a', 5, pageSize: 3);
    final cubit = _cubit([a], cfg, repo);
    await cubit.unifiedBrowse(); // page 1 -> hasNext true

    a.failNext = true;
    await cubit.unifiedLoadMore(); // page 2 fails
    expect(cubit.state.discoveryError, contains('boom'));
    expect(cubit.state.discoveryPages['a'], 1); // page not advanced
    expect(cubit.state.discoveryHasNext['a'], isTrue); // preserved

    await cubit.unifiedLoadMore(); // retry same page succeeds
    expect(cubit.state.discoveryPages['a'], 2);
    expect(cubit.state.discoveryEntries, hasLength(5));
    expect(cubit.state.discoveryError, isNull);
    expect(a.queries, hasLength(3)); // page 1, failed page 2, retried page 2
  });

  test('toggleRegistrySource on git triggers the background git sync once',
      () async {
    final cache = _CountingRepoCache();
    final repo = SkillRepository(repoCache: cache);
    var syncNowCalls = 0;
    GitRepoRegistrySource buildSource(SkillRegistrySourceConfig c) =>
        GitRepoRegistrySource(
          c,
          discoverableProvider: () async => const [],
          syncNow: () async => syncNowCalls++,
        );
    final cubit = SkillCubit(
      repo,
      registryConfigService: cfg,
      initialSources: const [],
      rebuildSources: (config) => [
        for (final c in config.sources)
          if (c.kind == SkillRegistryKind.gitRepo) buildSource(c),
      ],
    );

    await cubit.addRegistrySource(
      const SkillRegistrySourceConfig(
        id: 'git-o-r',
        kind: SkillRegistryKind.gitRepo,
        label: 'o/r',
        enabled: false,
        gitOwner: 'o',
        gitName: 'r',
        gitBranch: 'main',
      ),
    );
    expect(cache.syncCalls, 0); // disabled add does not sync

    await cubit.toggleRegistrySource('git-o-r', true);
    await _waitFor(() => cache.syncCalls == 1);
    expect(cache.syncCalls, 1);
    expect(cubit.state.registriesConfig.byId('git-o-r')!.enabled, isTrue);
    expect(syncNowCalls, 0); // background sync goes through the repo cache

    // The probe is built from the candidate config: its git syncNow goes
    // through the repo cache (counted here), not the source closure.
    final err = await cubit.testRegistryConnection(
      cubit.state.registriesConfig.byId('git-o-r')!,
    );
    expect(err, isNull);
    expect(cache.syncCalls, 2); // toggle sync (1) + probe sync (2)
  });

  test('unifiedSetApiKey persists trimmed key via config service', () async {
    final a = _FakeRegistry('a', 3);
    final cubit = _cubit([a], cfg, repo);
    await cubit.addRegistrySource(
      const SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
      ),
    );

    await cubit.unifiedSetApiKey('a', '  sk_x  ');
    expect(cubit.state.registriesConfig.byId('a')!.apiToken, 'sk_x');
    final persisted = await cfg.load();
    expect(persisted.byId('a')!.apiToken, 'sk_x');

    await cubit.unifiedSetApiKey('a', '  ');
    expect(cubit.state.registriesConfig.byId('a')!.apiToken, isNull);
    expect((await cfg.load()).byId('a')!.apiToken, isNull);

    await cubit.unifiedSetApiKey('missing', 'k'); // unknown source: no-op
    expect(cubit.state.registriesConfig.byId('missing'), isNull);
  });

  test('testRegistryConnection probes the candidate, not persisted state', () async {
    final a = _FakeRegistry('a', 3);
    final cubit = _cubit([a], cfg, repo);

    // Unknown id -> short error string, no errorMessage emitted.
    final missing = await cubit.testRegistryConnection(
      const SkillRegistrySourceConfig(
        id: 'nope',
        kind: SkillRegistryKind.api,
        label: 'nope',
      ),
    );
    expect(missing, isNotNull);
    expect(cubit.state.errorMessage, isNull);

    // A real API probe against an unreachable base URL surfaces the error
    // string back to the dialog instead of emitting errorMessage (avoids
    // double toasts with the management-page listener).
    final err = await cubit.testRegistryConnection(
      const SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
        baseUrl: 'http://127.0.0.1:1',
      ),
    );
    expect(err, isNotNull);
    expect(cubit.state.errorMessage, isNull);
  });
}
