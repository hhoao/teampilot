import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_sh_marketplace_source.dart';
import 'package:teampilot/services/skill/skills_sh_service.dart';

void main() {
  MockClient clientWith(MockClientHandler handler) => MockClient(handler);

  SkillsShMarketplaceSource sourceWith(MockClientHandler handler) =>
      SkillsShMarketplaceSource(
        SkillsShService(client: clientWith(handler)),
      );

  test('maps entries to unified model with directory', () async {
    final source = sourceWith(
      (_) async => http.Response(
        jsonEncode({
          'skills': [
            {
              'id': 'sh1',
              'name': 'frontend-design',
              'skillId': 'skills/frontend-design',
              'source': 'anthropics/skills',
              'installs': 775800,
            },
          ],
          'count': 1200,
          'query': 'design',
        }),
        200,
      ),
    );
    final res = await source.search(
      const MarketplaceSearchQuery(query: 'design', page: 1, limit: 20),
    );
    expect(source.id, 'skillsSh');
    expect(source.capabilities.hasAnyFilter, isFalse);
    final s = res.skills.single;
    expect(s.key, 'sh1');
    expect(s.name, 'frontend-design');
    expect(s.directory, 'skills/frontend-design');
    expect(s.isInstalledDirectly, isTrue);
    expect(s.repoOwner, 'anthropics');
    expect(s.repoName, 'skills');
    expect(s.repoBranch, 'main');
    expect(s.installs, 775800);
    expect(s.stars, isNull);
    expect(res.total, 1200);
    expect(res.hasNext, isTrue);
  });

  test('hasNext false when page is beyond totalCount', () async {
    final source = sourceWith(
      (_) async => http.Response(
        jsonEncode({
          'skills': [
            {
              'id': 'sh1',
              'name': 'x',
              'skillId': 'x',
              'source': 'a/b',
              'installs': 0,
            },
          ],
          'count': 1,
          'query': 'x',
        }),
        200,
      ),
    );
    final res = await source.search(
      const MarketplaceSearchQuery(query: 'x', page: 1, limit: 20),
    );
    expect(res.hasNext, isFalse);
  });

  test('offset maps from page', () async {
    late Uri requested;
    final source = sourceWith((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'skills': <Object>[],
          'count': 0,
          'query': 'q',
        }),
        200,
      );
    });
    await source.search(
      const MarketplaceSearchQuery(query: 'q', page: 3, limit: 20),
    );
    expect(requested.queryParameters['offset'], '40');
    expect(requested.queryParameters['limit'], '20');
  });

  test('setApiKey is a no-op', () async {
    final source = sourceWith(
      (_) async => http.Response('{}', 200),
    );
    await source.setApiKey('anything');
  });
}
