import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';

void main() {
  test('MarketplaceSkill defaults repoBranch to main', () {
    const skill = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      githubUrl: 'https://github.com/o/r',
    );
    expect(skill.repoBranch, 'main');
    expect(skill.isInstalledDirectly, isFalse);
  });

  test('isInstalledDirectly true when directory present', () {
    const skill = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      directory: 'skills/x',
      githubUrl: 'https://github.com/o/r',
    );
    expect(skill.isInstalledDirectly, isTrue);
  });

  test('MarketplaceCapabilities.hasAnyFilter', () {
    const none = MarketplaceCapabilities();
    expect(none.hasAnyFilter, isFalse);
    const all = MarketplaceCapabilities(
      supportsCategory: true,
      supportsOccupation: true,
      supportsLanguage: true,
      supportsSortBy: true,
      categoryChoices: {'data-ai': 'Data & AI'},
      occupationChoices: {'software-developers': 'Software Developers'},
      languageChoices: ['zh', 'en'],
    );
    expect(all.hasAnyFilter, isTrue);
  });

  test('quota error key is stable', () {
    expect(marketplaceQuotaErrorKey, 'marketplace_quota_error');
  });

  test('MarketplaceQuotaException is a MarketplaceFetchException', () {
    final e = MarketplaceQuotaException('quota');
    expect(e, isA<MarketplaceFetchException>());
    expect(e.message, 'quota');
  });
}
