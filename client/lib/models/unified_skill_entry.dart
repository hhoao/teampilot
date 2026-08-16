import '../services/skill/marketplace/skill_marketplace_source.dart';

class UnifiedSkillEntry {
  const UnifiedSkillEntry({
    required this.skill,
    required this.sourceId,
    this.repoKey,
  });

  final MarketplaceSkill skill;
  final String sourceId;

  /// git 源过滤用（`owner__name`）。
  final String? repoKey;

  String get dedupeKey =>
      '${skill.repoOwner}/${skill.repoName}/${skill.directory ?? ''}'
          .toLowerCase();
}
