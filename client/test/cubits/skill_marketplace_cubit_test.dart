import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_manifest_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeSource implements SkillMarketplaceSource {
  _FakeSource(
    this.id, {
    this.quota = false,
    this.pageSize = 2,
    this.total = 3,
  });

  @override
  final String id;
  final bool quota;
  final int pageSize;
  final int total;

  @override
  String get label => id;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  final List<MarketplaceSearchQuery> queries = [];
  String? setKey;

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    queries.add(query);
    if (quota) throw MarketplaceQuotaException('quota');
    final start = (query.page - 1) * pageSize;
    final end = start + pageSize;
    final items = <MarketplaceSkill>[];
    for (var i = start; i < end && i < total; i++) {
      items.add(MarketplaceSkill(
        key: '$id-$i',
        name: '$id-$i',
        description: 'd',
        repoOwner: 'o',
        repoName: 'r',
        directory: 'dir/$i',
        githubUrl: 'https://github.com/o/r',
      ));
    }
    return MarketplaceSearchResult(
      skills: items,
      hasNext: end < total,
      total: total,
    );
  }

  @override
  Future<void> setApiKey(String key) async {
    setKey = key;
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-mp-cubit-');
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

  SkillCubit cubitWith(
    List<_FakeSource> sources, {
    List<MarketplaceSkill>? directResults,
  }) {
    final engine = SkillAcquisitionEngine(
      installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
        final installed = directResults ?? const [];
        if (installed.isNotEmpty) {
          final e = installed.first;
          return Skill(
            id: idOverride ?? e.key,
            name: e.name,
            description: e.description,
            directory: e.directory ?? '',
            installedAt: 1,
            updatedAt: 1,
          );
        }
        final skill = Skill(
          id: idOverride ?? d.expectedLocalId,
          name: d.name,
          description: d.description,
          directory: d.directory,
          installedAt: 1,
          updatedAt: 1,
        );
        await SkillManifestService().upsertSkill(skill);
        return skill;
      },
      registerDirectory: ({required String id, required String directory}) {
        throw UnimplementedError();
      },
    );
    return SkillCubit(
      SkillRepository(),
      acquisitionEngine: engine,
      marketplaces: sources,
    );
  }

  test('searchMarketplace fills the slot per source id', () async {
    final a = _FakeSource('a');
    final b = _FakeSource('b');
    final cubit = cubitWith([a, b]);
    await cubit.searchMarketplace('a', query: 'foo');
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
    expect(cubit.state.marketplace['a']?.query, 'foo');
    expect(cubit.state.marketplace.containsKey('b'), isFalse);
    expect(a.queries.single.query, 'foo');
    await cubit.searchMarketplace('b', query: 'bar');
    expect(cubit.state.marketplace['b']?.entries, hasLength(2));
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
  });

  test('short query and unknown source are ignored', () async {
    final a = _FakeSource('a');
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'x');
    expect(a.queries, isEmpty);
    await cubit.searchMarketplace('nope', query: 'longquery');
    expect(cubit.state.marketplace, isEmpty);
  });

  test('loadMoreMarketplace appends and guards hasNext', () async {
    final a = _FakeSource('a', pageSize: 2, total: 3);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q1');
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
    await cubit.loadMoreMarketplace('a');
    expect(cubit.state.marketplace['a']?.entries, hasLength(3));
    expect(cubit.state.marketplace['a']?.hasNext, isFalse);
    await cubit.loadMoreMarketplace('a');
    expect(a.queries, hasLength(2));
  });

  test('quota error maps to marketplaceQuotaErrorKey', () async {
    final a = _FakeSource('a', quota: true);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q1');
    expect(cubit.state.marketplace['a']?.error, marketplaceQuotaErrorKey);
    expect(cubit.state.marketplace['a']?.loading, isFalse);
  });

  test('setMarketplaceApiKey delegates and clears error', () async {
    final a = _FakeSource('a', quota: true);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q1');
    expect(cubit.state.marketplace['a']?.error, marketplaceQuotaErrorKey);
    await cubit.setMarketplaceApiKey('a', 'sk_x');
    expect(a.setKey, 'sk_x');
    expect(cubit.state.marketplace['a']?.error, isNull);
  });

  test('installMarketplaceEntry with directory installs directly', () async {
    final cubit = cubitWith([]);
    final entry = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      directory: 'skills/n',
      githubUrl: 'https://github.com/o/r',
    );
    await cubit.installMarketplaceEntry(entry);
    expect(cubit.state.installed, isNotEmpty);
    expect(cubit.state.noticeMessage, isNull);
    expect(cubit.state.busyIds, isEmpty);
  });

  test('installMarketplaceEntry without directory adds repo', () async {
    final cubit = cubitWith([]);
    final entry = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      githubUrl: 'https://github.com/o/r',
    );
    await cubit.installMarketplaceEntry(entry);
    final loaded = await SkillRepository().loadRepos();
    expect(loaded.any((r) => r.owner == 'o' && r.name == 'r'), isTrue);
    expect(
      cubit.state.noticeMessage,
      SkillCubit.marketplaceRepoAddedNoticeKey,
    );
  });
}
