import '../../../models/catalog/catalog_types.dart';

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
    int? installs,
    int? stars,
    int? updatedAt,
    this.contentLanguage,
    CatalogMetrics metrics = const CatalogMetrics(),
  }) : _metrics = metrics,
       _legacyInstalls = installs,
       _legacyStars = stars,
       _legacyUpdatedAt = updatedAt;

  final String key;
  final String name;
  final String description;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  /// SKILL.md 所在 repo 内子目录。null 表示无法直接定位（如 SkillsMP），
  /// 安装需降级为把整个 repo 加入注册中心 git 源。
  final String? directory;
  final String githubUrl;

  final CatalogMetrics _metrics;

  final int? _legacyInstalls;
  final int? _legacyStars;
  final int? _legacyUpdatedAt;

  CatalogMetrics get metrics => CatalogMetrics(
    adoptionCount: _metrics.adoptionCount ?? _legacyInstalls,
    rating: _metrics.rating,
    ratingCount: _metrics.ratingCount,
    updatedAtMs:
        _metrics.updatedAtMs ??
        (_legacyUpdatedAt == null ? null : _legacyUpdatedAt * 1000),
    publishedAtMs: _metrics.publishedAtMs,
  );

  /// skills.sh 源的安装次数。
  int? get installs => _legacyInstalls ?? metrics.adoptionCount;

  /// SkillsMP 源的 GitHub stars 与最近更新时间（Unix 秒）。
  int? get stars => _legacyStars;
  int? get updatedAt =>
      _legacyUpdatedAt ??
      (metrics.updatedAtMs == null ? null : metrics.updatedAtMs! ~/ 1000);
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
