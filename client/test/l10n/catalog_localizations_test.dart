import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/l10n/app_localizations.dart';

void main() {
  test(
    'catalog localization exposes the shared sort and metric vocabulary',
    () {
      final l10n = AppLocalizationsEn();

      expect(l10n.catalog.sortAdoption, isNotEmpty);
      expect(l10n.catalog.sortRating, isNotEmpty);
      expect(l10n.catalog.sortUpdated, isNotEmpty);
      expect(l10n.catalog.sortPublished, isNotEmpty);
      expect(l10n.catalog.sortName, isNotEmpty);
      expect(l10n.catalog.metricRating, isNotEmpty);
      expect(l10n.catalog.metricUpdated, isNotEmpty);
      expect(l10n.catalog.metricPublished, isNotEmpty);
      expect(l10n.catalog.metricMissing, isNotEmpty);
      expect(l10n.catalog.metricMissingTooltip, isNotEmpty);
    },
  );

  test(
    'each catalog has a localized adoption label in both supported locales',
    () {
      final english = AppLocalizationsEn();
      final chinese = AppLocalizationsZh();

      final englishLabels = [
        english.skills.catalogAdoption,
        english.mcp.catalogAdoption,
        english.plugins.catalogAdoption,
        english.teamsCatalogAdoption,
        english.expertsCatalogAdoption,
      ];
      final chineseLabels = [
        chinese.skills.catalogAdoption,
        chinese.mcp.catalogAdoption,
        chinese.plugins.catalogAdoption,
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
        l10n.catalog.sourceWarningEntry(
          source: 'SkillsMP',
          error: 'request timed out',
        ),
        contains('SkillsMP'),
      );
      expect(
        l10n.catalog.sourceWarningEntry(
          source: 'SkillsMP',
          error: 'request timed out',
        ),
        contains('request timed out'),
      );
      expect(
        l10n.catalog.sourceWarningAccessibilityLabel(count: 2),
        contains('2'),
      );
      expect(l10n.catalog.sortAccessibilityLabel, isNotEmpty);
      expect(l10n.catalog.refreshAccessibilityLabel, isNotEmpty);
      expect(
        l10n.catalog.missingMetricAccessibilityLabel(label: 'Rating'),
        contains('Rating'),
      );
    },
  );
}
