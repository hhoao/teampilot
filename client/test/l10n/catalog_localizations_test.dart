import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/l10n/app_localizations_zh.dart';

void main() {
  test(
    'catalog localization exposes the shared sort and metric vocabulary',
    () {
      final l10n = AppLocalizationsEn();

      expect(l10n.catalogSortAdoption, isNotEmpty);
      expect(l10n.catalogSortRating, isNotEmpty);
      expect(l10n.catalogSortUpdated, isNotEmpty);
      expect(l10n.catalogSortPublished, isNotEmpty);
      expect(l10n.catalogSortName, isNotEmpty);
      expect(l10n.catalogMetricRating, isNotEmpty);
      expect(l10n.catalogMetricUpdated, isNotEmpty);
      expect(l10n.catalogMetricPublished, isNotEmpty);
      expect(l10n.catalogMetricMissing, isNotEmpty);
      expect(l10n.catalogMetricMissingTooltip, isNotEmpty);
    },
  );

  test(
    'each catalog has a localized adoption label in both supported locales',
    () {
      final english = AppLocalizationsEn();
      final chinese = AppLocalizationsZh();

      final englishLabels = [
        english.skillsCatalogAdoption,
        english.mcpCatalogAdoption,
        english.pluginsCatalogAdoption,
        english.teamsCatalogAdoption,
        english.expertsCatalogAdoption,
      ];
      final chineseLabels = [
        chinese.skillsCatalogAdoption,
        chinese.mcpCatalogAdoption,
        chinese.pluginsCatalogAdoption,
        chinese.teamsCatalogAdoption,
        chinese.expertsCatalogAdoption,
      ];

      expect(englishLabels, everyElement(isNotEmpty));
      expect(chineseLabels, everyElement(isNotEmpty));
    },
  );

  test(
    'source warning and accessibility messages preserve their placeholders',
    () {
      final l10n = AppLocalizationsEn();

      expect(
        l10n.catalogSourceWarningEntry('SkillsMP', 'request timed out'),
        contains('SkillsMP'),
      );
      expect(
        l10n.catalogSourceWarningEntry('SkillsMP', 'request timed out'),
        contains('request timed out'),
      );
      expect(l10n.catalogSourceWarningAccessibilityLabel(2), contains('2'));
      expect(l10n.catalogSortAccessibilityLabel, isNotEmpty);
      expect(l10n.catalogRefreshAccessibilityLabel, isNotEmpty);
      expect(
        l10n.catalogMissingMetricAccessibilityLabel('Rating'),
        contains('Rating'),
      );
    },
  );
}
