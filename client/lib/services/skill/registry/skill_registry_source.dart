import '../../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';

class SkillRegistryQuery {
  const SkillRegistryQuery({
    this.query = '',
    this.page = 1,
    this.limit = 20,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  /// 空字符串 = browse（源自身决定浏览策略）。
  final String query;
  final int page;
  final int limit;
  final String? category;
  final String? occupation;
  final String? language;
  final String? sortBy;
}

class SkillRegistryPage {
  const SkillRegistryPage({
    required this.entries,
    this.hasNext = false,
    this.total = 0,
  });

  final List<MarketplaceSkill> entries;
  final bool hasNext;
  final int total;
}

abstract class SkillRegistrySource {
  String get id;
  String get label;
  bool get enabled;
  SkillRegistryKind get kind;
  MarketplaceCapabilities get capabilities;

  Future<SkillRegistryPage> search(SkillRegistryQuery query);

  Future<void> testConnection();

  Future<void> setApiKey(String key) async {}
}
