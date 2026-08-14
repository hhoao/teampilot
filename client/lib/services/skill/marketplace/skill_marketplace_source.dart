const marketplaceQuotaErrorKey = 'marketplace_quota_error';

class MarketplaceSkill {
  const MarketplaceSkill({
    required this.key,
    required this.name,
    required this.description,
    required this.repoOwner,
    required this.repoName,
    this.repoBranch = 'main',
    this.directory,
    required this.githubUrl,
    this.installs,
    this.stars,
    this.updatedAt,
    this.contentLanguage,
  });

  final String key;
  final String name;
  final String description;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  /// SKILL.md 所在 repo 内子目录。null 表示无法直接定位（如 SkillsMP），
  /// 安装需降级为把整个 repo 加入仓库源。
  final String? directory;
  final String githubUrl;

  /// skills.sh 源的安装次数。
  final int? installs;

  /// SkillsMP 源的 GitHub stars 与最近更新时间（Unix 秒）。
  final int? stars;
  final int? updatedAt;
  final String? contentLanguage;

  bool get isInstalledDirectly =>
      directory != null && directory!.trim().isNotEmpty;
}

class MarketplaceCapabilities {
  const MarketplaceCapabilities({
    this.supportsCategory = false,
    this.supportsOccupation = false,
    this.supportsLanguage = false,
    this.supportsSortBy = false,
    this.categoryChoices = const {},
    this.occupationChoices = const {},
    this.languageChoices = const [],
  });

  final bool supportsCategory;
  final bool supportsOccupation;
  final bool supportsLanguage;
  final bool supportsSortBy;

  /// slug -> 展示标签。slug 直接作为 API 参数值。
  final Map<String, String> categoryChoices;
  final Map<String, String> occupationChoices;
  final List<String> languageChoices;

  bool get hasAnyFilter =>
      supportsCategory ||
      supportsOccupation ||
      supportsLanguage ||
      supportsSortBy;
}

class MarketplaceSearchQuery {
  const MarketplaceSearchQuery({
    required this.query,
    this.page = 1,
    this.limit = 20,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  final String query;
  final int page;
  final int limit;
  final String? category;
  final String? occupation;
  final String? language;

  /// 'stars' | 'recent'（SkillsMP 专有）。
  final String? sortBy;
}

class MarketplaceSearchResult {
  const MarketplaceSearchResult({
    required this.skills,
    this.hasNext = false,
    this.total = 0,
  });

  final List<MarketplaceSkill> skills;
  final bool hasNext;
  final int total;
}

class MarketplaceFetchException implements Exception {
  MarketplaceFetchException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'MarketplaceFetchException: $message ($cause)'
      : 'MarketplaceFetchException: $message';
}

class MarketplaceQuotaException extends MarketplaceFetchException {
  MarketplaceQuotaException(super.message);
}

abstract class SkillMarketplaceSource {
  String get id;
  String get label;
  MarketplaceCapabilities get capabilities;

  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query);

  Future<void> setApiKey(String key) async {}
}
