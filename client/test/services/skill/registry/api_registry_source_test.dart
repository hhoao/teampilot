import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/api_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

ApiRegistrySource _source(SkillRegistryProtocol protocol, {String? token, String? browseQuery, String baseUrl = 'https://example.test'}) =>
    ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: protocol == SkillRegistryProtocol.skillsMp ? 'skillsMp' : 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 't',
        protocol: protocol,
        baseUrl: baseUrl,
        apiToken: token,
        browseQuery: browseQuery,
      ),
      client: http.Client(),
    );

void main() {
  test('skillsSh protocol: browse uses browseQuery, query uses q', () async {
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      return http.Response(
        json.encode({
          'count': 2,
          'skills': [
            {
              'id': 'vercel/ai/ai-sdk',
              'skillId': 'ai-sdk',
              'name': 'ai-sdk',
              'installs': 42,
              'source': 'vercel/ai',
            },
          ],
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: 'https://skills.sh',
        browseQuery: 'ai',
      ),
      client: client,
    );
    final browse = await src.search(const SkillRegistryQuery());
    expect(requests.single.queryParameters['q'], 'ai');
    expect(browse.entries.single.name, 'ai-sdk');
    expect(browse.entries.single.repoOwner, 'vercel');

    final q = await src.search(const SkillRegistryQuery(query: 'claude', page: 2, limit: 10));
    expect(requests.last.queryParameters['q'], 'claude');
    expect(requests.last.queryParameters['offset'], '10');
  });

  test('skillsMp protocol: browse sends q=a + sortBy=stars, quota throws', () async {
    final client = MockClient((req) async {
      if (req.url.path.contains('/quota')) {
        return http.Response('{}', 429);
      }
      return http.Response(
        json.encode({
          'data': {
            'skills': [
              {
                'id': 'openclaw-openclaw-agents-skills-x',
                'name': 'x',
                'description': 'd',
                'contentLanguage': 'en',
                'githubUrl': 'https://github.com/openclaw/openclaw/tree/main/.agents/skills/x',
                'stars': 386158,
                'updatedAt': 1750000000,
              },
            ],
            'pagination': {'hasNext': true, 'total': 7},
          },
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: 'https://skillsmp.com/api/v1',
      ),
      client: client,
    );
    final browse = await src.search(const SkillRegistryQuery(sortBy: 'stars'));
    final u = browse.entries;
    expect(u.single.repoOwner, 'openclaw');
    expect(u.single.repoName, 'openclaw');
    expect(u.single.stars, 386158);

    final quotaSrc = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: 'https://skillsmp.com/api/v1/quota',
      ),
      client: client,
    );
    expect(
      () => quotaSrc.search(const SkillRegistryQuery(query: 'x')),
      throwsA(isA<MarketplaceQuotaException>()),
    );
  });

  test('skillsMp sends Authorization header when token set', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      return http.Response(
        json.encode({'data': {'skills': [], 'pagination': {'hasNext': false}}}),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        apiToken: 'tok123',
      ),
      client: client,
    );
    await src.search(const SkillRegistryQuery(query: 'a'));
    expect(seen.single, 'Bearer tok123');
  });

  test('testConnection calls search and succeeds', () async {
    final client = MockClient((req) async {
      expect(req.url.queryParameters['q'], 'ai');
      return http.Response(
        json.encode({
          'count': 1,
          'skills': [
            {
              'id': 'vercel/ai/ai-sdk',
              'skillId': 'ai-sdk',
              'name': 'ai-sdk',
              'installs': 1,
              'source': 'vercel/ai',
            },
          ],
        }),
        200,
      );
    });
    final src = ApiRegistrySource(
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: 'https://skills.sh',
      ),
      client: client,
    );
    await src.testConnection();
  });
}
