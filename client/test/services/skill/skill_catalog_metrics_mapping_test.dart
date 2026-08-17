import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/api_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';

void main() {
  test('MarketplaceSkill normalizes legacy source statistics into metrics', () {
    const skill = MarketplaceSkill(
      key: 'legacy',
      name: 'Legacy',
      description: '',
      repoOwner: 'acme',
      repoName: 'skills',
      githubUrl: 'https://github.com/acme/skills',
      installs: 9,
      updatedAt: 1_750_000_000,
    );

    expect(skill.metrics.adoptionCount, 9);
    expect(skill.metrics.rating, isNull);
    expect(skill.metrics.updatedAtMs, 1_750_000_000_000);
  });

  test(
    'skills.sh maps installs and converts second timestamps to milliseconds',
    () async {
      final source = ApiRegistrySource(
        SkillRegistrySourceConfig(
          id: 'skills-sh',
          kind: SkillRegistryKind.api,
          label: 'skills.sh',
          protocol: SkillRegistryProtocol.skillsSh,
          baseUrl: 'https://skills.sh',
        ),
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'count': 1,
              'skills': [
                {
                  'id': 'acme/skills/review',
                  'skillId': 'review',
                  'name': 'Review',
                  'installs': 321,
                  'updatedAt': 1_750_000_000,
                  'publishedAt': 1_740_000_000,
                  'source': 'acme/skills',
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await source.search(const SkillRegistryQuery());

      expect(result.entries.single.metrics.adoptionCount, 321);
      expect(result.entries.single.metrics.updatedAtMs, 1_750_000_000_000);
      expect(result.entries.single.metrics.publishedAtMs, 1_740_000_000_000);
    },
  );

  test(
    'SkillsMP maps explicit rating fields and never stars as rating',
    () async {
      final source = ApiRegistrySource(
        SkillRegistrySourceConfig(
          id: 'skills-mp',
          kind: SkillRegistryKind.api,
          label: 'SkillsMP',
          protocol: SkillRegistryProtocol.skillsMp,
          baseUrl: 'https://skillsmp.com/api/v1',
        ),
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'data': {
                'skills': [
                  {
                    'id': 'acme-review',
                    'name': 'Review',
                    'description': 'Review code',
                    'githubUrl':
                        'https://github.com/acme/skills/tree/main/review',
                    'stars': 999999,
                    'rating': 4.6,
                    'ratingCount': 41,
                    'updatedAt': 1_750_000_000,
                    'publishedAt': 1_740_000_000,
                  },
                ],
                'pagination': {'hasNext': false, 'total': 1},
              },
            }),
            200,
          );
        }),
      );

      final metrics = (await source.search(
        const SkillRegistryQuery(),
      )).entries.single.metrics;

      expect(metrics.adoptionCount, isNull);
      expect(metrics.rating, 4.6);
      expect(metrics.ratingCount, 41);
      expect(metrics.updatedAtMs, 1_750_000_000_000);
      expect(metrics.publishedAtMs, 1_740_000_000_000);
    },
  );
}
