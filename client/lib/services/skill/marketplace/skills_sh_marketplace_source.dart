import '../skills_sh_service.dart';
import 'skill_marketplace_source.dart';

class SkillsShMarketplaceSource implements SkillMarketplaceSource {
  SkillsShMarketplaceSource(this._service);

  final SkillsShService _service;

  @override
  String get id => 'skillsSh';

  @override
  String get label => 'skills.sh';

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    final res = await _service.search(
      query.query,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    );
    return MarketplaceSearchResult(
      skills: res.skills
          .map(
            (e) => MarketplaceSkill(
              key: e.key,
              name: e.name,
              description: '',
              repoOwner: e.repoOwner,
              repoName: e.repoName,
              repoBranch: e.repoBranch,
              directory: e.directory,
              githubUrl: e.readmeUrl ??
                  'https://github.com/${e.repoOwner}/${e.repoName}',
              installs: e.installs,
            ),
          )
          .toList(),
      hasNext: (query.page * query.limit) < res.totalCount,
      total: res.totalCount,
    );
  }

  @override
  Future<void> setApiKey(String key) async {}
}
