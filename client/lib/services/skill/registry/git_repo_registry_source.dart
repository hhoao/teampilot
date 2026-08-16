import '../../../models/skill.dart';
import '../../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';
import 'skill_registry_source.dart';

/// Git 仓库注册源：本地目录扫描的 discoverable 技能，无分页。
class GitRepoRegistrySource implements SkillRegistrySource {
  GitRepoRegistrySource(
    this.config, {
    required Future<List<DiscoverableSkill>> Function() discoverableProvider,
    required Future<void> Function() syncNow,
  }) : _discoverableProvider = discoverableProvider,
       _syncNow = syncNow;

  final SkillRegistrySourceConfig config;
  final Future<List<DiscoverableSkill>> Function() _discoverableProvider;
  final Future<void> Function() _syncNow;

  @override
  String get id => config.id;

  @override
  String get label => config.label;

  @override
  bool get enabled => config.enabled;

  @override
  SkillRegistryKind get kind => SkillRegistryKind.gitRepo;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  SkillRepo get gitRepo => SkillRepo(
    owner: (config.gitOwner as String?) ?? '',
    name: (config.gitName as String?) ?? '',
    branch: (config.gitBranch as String?) ?? 'main',
    enabled: config.enabled,
  );

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery query) async {
    final all = await _discoverableProvider();
    final q = query.query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
              .where(
                (d) =>
                    d.name.toLowerCase().contains(q) ||
                    '${d.repoOwner}/${d.repoName}'.toLowerCase().contains(q),
              )
              .toList();
    return SkillRegistryPage(
      entries: filtered.map(_toMarketplace).toList(),
      hasNext: false,
      total: filtered.length,
    );
  }

  MarketplaceSkill _toMarketplace(DiscoverableSkill d) => MarketplaceSkill(
    key: d.key,
    name: d.name,
    description: d.description,
    repoOwner: d.repoOwner,
    repoName: d.repoName,
    repoBranch: d.repoBranch,
    directory: d.directory,
    githubUrl: d.readmeUrl ??
        'https://github.com/${d.repoOwner}/${d.repoName}',
  );

  @override
  Future<void> testConnection() => _syncNow();

  @override
  Future<void> setApiKey(String key) async {}
}
