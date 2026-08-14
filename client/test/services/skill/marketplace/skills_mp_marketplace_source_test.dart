import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_mp_marketplace_source.dart';

void main() {
  const skillsJson = {
    'success': true,
    'data': {
      'skills': [
        {
          'id': 's1',
          'name': 'seo-audit',
          'author': 'coreyhaines31',
          'description': 'Run an SEO audit',
          'contentLanguage': 'en',
          'githubUrl': 'https://github.com/coreyhaines31/marketingskills',
          'skillUrl': 'https://skillsmp.com/skill/s1',
          'stars': 186,
          'updatedAt': 1720000000,
        },
      ],
      'pagination': {'hasNext': true, 'total': 42},
    },
    'meta': {'requestId': 'r1', 'responseTimeMs': 10},
  };

  InMemoryAppSettingsRepository settings({String? key}) =>
      InMemoryAppSettingsRepository(skillsMpApiKey: key);

  late Uri lastUri;
  late Map<String, String> lastHeaders;
  MockClient client(MockClientHandler handler) {
    return MockClient((request) async {
      lastUri = request.url;
      lastHeaders = request.headers;
      return handler(request);
    });
  }

  test('sends all query params and parses result', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(),
    );
    final res = await source.search(const MarketplaceSearchQuery(
      query: 'seo',
      page: 2,
      category: 'data-ai',
      occupation: 'software-developers',
      language: 'zh',
      sortBy: 'recent',
    ));
    expect(lastUri.path, '/api/v1/skills/search');
    expect(lastUri.queryParameters['q'], 'seo');
    expect(lastUri.queryParameters['page'], '2');
    expect(lastUri.queryParameters['limit'], '20');
    expect(lastUri.queryParameters['sortBy'], 'recent');
    expect(lastUri.queryParameters['category'], 'data-ai');
    expect(lastUri.queryParameters['occupation'], 'software-developers');
    expect(lastUri.queryParameters['language'], 'zh');
    expect(res.skills, hasLength(1));
    final s = res.skills.first;
    expect(s.key, 's1');
    expect(s.name, 'seo-audit');
    expect(s.repoOwner, 'coreyhaines31');
    expect(s.repoName, 'marketingskills');
    expect(s.directory, isNull);
    expect(s.isInstalledDirectly, isFalse);
    expect(s.stars, 186);
    expect(s.updatedAt, 1720000000);
    expect(s.contentLanguage, 'en');
    expect(s.installs, isNull);
    expect(res.hasNext, isTrue);
    expect(res.total, 42);
  });

  test('omits empty filters and sends Bearer when key set', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(key: 'sk_live_abc'),
    );
    await source.search(const MarketplaceSearchQuery(query: 'seo'));
    expect(lastUri.queryParameters.containsKey('sortBy'), isFalse);
    expect(lastUri.queryParameters.containsKey('category'), isFalse);
    expect(lastHeaders['Authorization'], 'Bearer sk_live_abc');
  });

  test('no Authorization header without key', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(),
    );
    await source.search(const MarketplaceSearchQuery(query: 'seo'));
    expect(lastHeaders.containsKey('Authorization'), isFalse);
  });

  test('429 throws MarketplaceQuotaException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'DAILY_QUOTA_EXCEEDED', 'message': 'quota'},
          }),
          429,
        ),
      ),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceQuotaException>()),
    );
  });

  test('non-2xx throws MarketplaceFetchException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
          }),
          500,
        ),
      ),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceFetchException>()),
    );
  });

  test('invalid JSON throws MarketplaceFetchException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('not json', 200)),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceFetchException>()),
    );
  });

  test('capabilities enable all filters with curated choices', () {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('{}', 200)),
      settings: settings(),
    );
    final caps = source.capabilities;
    expect(caps.supportsCategory, isTrue);
    expect(caps.supportsOccupation, isTrue);
    expect(caps.supportsLanguage, isTrue);
    expect(caps.supportsSortBy, isTrue);
    expect(caps.categoryChoices['data-ai'], isNotNull);
    expect(caps.occupationChoices['software-developers'], isNotNull);
    expect(caps.languageChoices, contains('zh'));
    expect(source.id, 'skillsMp');
  });

  test('setApiKey persists via settings and trims empty', () async {
    final s = settings();
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('{}', 200)),
      settings: s,
    );
    await source.setApiKey('  sk_x  ');
    expect(await s.loadSkillsMpApiKey(), 'sk_x');
    await source.setApiKey('  ');
    expect(await s.loadSkillsMpApiKey(), isNull);
  });
}
