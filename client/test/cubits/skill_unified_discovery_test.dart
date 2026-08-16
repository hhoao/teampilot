import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeRegistry implements SkillRegistrySource {
  _FakeRegistry(this.id, this.total, {this.pageSize = 2, this.quota = false});
  @override
  final String id;
  final int total;
  final int pageSize;
  final bool quota;
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
}
