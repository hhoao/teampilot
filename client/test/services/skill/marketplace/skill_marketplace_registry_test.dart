import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_registry.dart';
import 'package:teampilot/services/skill/marketplace/skills_mp_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_sh_marketplace_source.dart';

void main() {
  test('builtIn returns both sources with unique ids', () {
    final sources = SkillMarketplaceRegistry.builtIn(
      settings: InMemoryAppSettingsRepository(),
    );
    expect(sources, hasLength(2));
    expect(sources.map((s) => s.id).toSet(), {'skillsSh', 'skillsMp'});
    expect(sources.first, isA<SkillsShMarketplaceSource>());
    expect(sources.last, isA<SkillsMpMarketplaceSource>());
  });
}
