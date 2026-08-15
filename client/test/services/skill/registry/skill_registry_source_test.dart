import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

class _Fake implements SkillRegistrySource {
  _Fake(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();
  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async =>
      SkillRegistryPage(entries: const [], hasNext: false, total: 0);
  @override
  Future<void> testConnection() async {}
  @override
  Future<void> setApiKey(String key) async {}
}

void main() {
  test('query defaults: empty query is browse, page starts at 1, limit 20', () {
    const q = SkillRegistryQuery();
    expect(q.query, '');
    expect(q.page, 1);
    expect(q.limit, 20);
    expect(q.category, isNull);
    expect(q.sortBy, isNull);
  });

  test('skill registry source contract', () async {
    final src = _Fake('x');
    final page = await src.search(const SkillRegistryQuery(query: 'ai'));
    expect(page.entries, isEmpty);
    expect(page.hasNext, isFalse);
    expect(src.capabilities.hasAnyFilter, isFalse);
    await src.testConnection();
    await src.setApiKey('k');
  });

  test('marketplace skill flags', () {
    const direct = MarketplaceSkill(
      key: 'k', name: 'n', description: 'd', repoOwner: 'o', repoName: 'r',
      directory: 'dir/skill', githubUrl: 'https://github.com/o/r',
    );
    expect(direct.isInstalledDirectly, isTrue);
    const undirected = MarketplaceSkill(
      key: 'k2', name: 'n', description: 'd', repoOwner: 'o', repoName: 'r',
      directory: null, githubUrl: 'https://github.com/o/r',
    );
    expect(undirected.isInstalledDirectly, isFalse);
  });
}
