import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

const _cfg = SkillRegistrySourceConfig(
  id: 'git-vercel-ai',
  kind: SkillRegistryKind.gitRepo,
  label: 'vercel/ai',
  gitOwner: 'vercel',
  gitName: 'ai',
  gitBranch: 'main',
);

DiscoverableSkill _skill(String name) => DiscoverableSkill(
  key: 'vercel/ai/$name',
  name: name,
  description: 'desc of $name',
  directory: 'skills/$name',
  repoOwner: 'vercel',
  repoName: 'ai',
  repoBranch: 'main',
);

void main() {
  test('search browses all entries when query empty', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('foo'), _skill('bar')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery());
    expect(page.entries.length, 2);
    expect(page.entries.first.name, 'foo');
    expect(page.entries.first.repoOwner, 'vercel');
    expect(page.entries.first.directory, 'skills/foo');
    expect(page.entries.first.isInstalledDirectly, isTrue);
  });

  test('search filters by query name and source', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('foobar'), _skill('baz')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery(query: 'foo'));
    expect(page.entries.single.name, 'foobar');
    final bySource = await src.search(
      const SkillRegistryQuery(query: 'vercel'),
    );
    expect(bySource.entries.length, 2);
  });

  test('search reports hasNext=false and total', () async {
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => [_skill('a')],
      syncNow: () async {},
    );
    final page = await src.search(const SkillRegistryQuery());
    expect(page.hasNext, isFalse);
    expect(page.total, 1);
  });

  test('testConnection invokes syncNow', () async {
    var synced = 0;
    final src = GitRepoRegistrySource(
      _cfg,
      discoverableProvider: () async => const [],
      syncNow: () async => synced++,
    );
    await src.testConnection();
    expect(synced, 1);
  });
}
