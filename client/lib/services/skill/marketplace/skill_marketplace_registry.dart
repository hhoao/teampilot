import '../../../repositories/app_settings_repository.dart';
import '../skills_sh_service.dart';
import 'skill_marketplace_source.dart';
import 'skills_mp_marketplace_source.dart';
import 'skills_sh_marketplace_source.dart';

abstract final class SkillMarketplaceRegistry {
  static List<SkillMarketplaceSource> builtIn({
    required AppSettingsRepository settings,
    SkillsShService? skillsSh,
  }) => [
    SkillsShMarketplaceSource(skillsSh ?? SkillsShService()),
    SkillsMpMarketplaceSource(settings: settings),
  ];
}
