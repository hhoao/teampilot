import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';

void main() {
  group('SkillRegistrySourceConfig', () {
    test('defaultBaseUrl per protocol', () {
      expect(
        SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsSh),
        'https://skills.sh',
      );
      expect(
        SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsMp),
        'https://skillsmp.com/api/v1',
      );
    });

    test('json round-trip keeps apiToken and omits empty token', () {
      final c = SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        apiToken: 'tok',
      );
      final json = c.toJson();
      expect(json['apiToken'], 'tok');
      final restored = SkillRegistrySourceConfig.fromJson(json);
      expect(restored.apiToken, 'tok');
      expect(restored.hasApiToken, isTrue);

      final without = SkillRegistrySourceConfig.fromJson({'id': 'skillsMp'});
      expect(without.hasApiToken, isFalse);
      expect(without.apiToken, isNull);
    });

    test('copyWith clearApiToken', () {
      final c = SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
        protocol: SkillRegistryProtocol.skillsSh,
        apiToken: 'x',
      );
      expect(c.copyWith(clearApiToken: true).apiToken, isNull);
      expect(c.copyWith(enabled: false).enabled, isFalse);
    });

    test('copyWith clearBaseUrl / clearBrowseQuery null each while keeping others', () {
      final c = SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: 'https://example.com',
        apiToken: 'tok',
        browseQuery: 'ai',
      );

      final clearedUrl = c.copyWith(clearBaseUrl: true);
      expect(clearedUrl.baseUrl, isNull);
      expect(clearedUrl.apiToken, 'tok');
      expect(clearedUrl.browseQuery, 'ai');

      final clearedQuery = c.copyWith(clearBrowseQuery: true);
      expect(clearedQuery.baseUrl, 'https://example.com');
      expect(clearedQuery.apiToken, 'tok');
      expect(clearedQuery.browseQuery, isNull);

      final clearedToken = c.copyWith(clearApiToken: true);
      expect(clearedToken.baseUrl, 'https://example.com');
      expect(clearedToken.apiToken, isNull);
      expect(clearedToken.browseQuery, 'ai');

      final clearedAll = c.copyWith(
        clearBaseUrl: true,
        clearApiToken: true,
        clearBrowseQuery: true,
      );
      expect(clearedAll.baseUrl, isNull);
      expect(clearedAll.apiToken, isNull);
      expect(clearedAll.browseQuery, isNull);
      expect(clearedAll.label, 'a');
    });

    test('copyWith set then clear round trips to null', () {
      final c = SkillRegistrySourceConfig(
        id: 'a',
        kind: SkillRegistryKind.api,
        label: 'a',
        protocol: SkillRegistryProtocol.skillsMp,
      );
      final withToken = c.copyWith(apiToken: 'tok');
      expect(withToken.hasApiToken, isTrue);
      expect(withToken.copyWith(clearApiToken: true).apiToken, isNull);
      expect(withToken.copyWith(clearApiToken: true).hasApiToken, isFalse);
      expect(
        withToken.copyWith(clearApiToken: true).copyWith(apiToken: 'tok2').apiToken,
        'tok2',
      );
    });
  });

  group('SkillRegistriesConfig', () {
    test('defaults contains both API sources and default git repos', () {
      final d = SkillRegistriesConfig.defaults();
      expect(d.byId('skillsSh'), isNotNull);
      expect(d.byId('skillsMp'), isNotNull);
      final git = d.sources.where((s) => s.kind == SkillRegistryKind.gitRepo);
      expect(git.length, 4);
    });

    test('fromJson fills missing kinds with defaults', () {
      final cfg = SkillRegistriesConfig.fromJson({'sources': [
        {'id': 'skillsSh', 'kind': 'api', 'label': 'skills.sh'},
      ]});
      expect(cfg.byId('skillsSh'), isNotNull);
      expect(cfg.byId('skillsMp'), isNotNull);
      expect(cfg.sources.length, greaterThanOrEqualTo(2));
    });

    test('toJson/fromJson round-trip', () {
      final d = SkillRegistriesConfig.defaults();
      final restored = SkillRegistriesConfig.fromJson(d.toJson());
      expect(restored.sources.length, d.sources.length);
      expect(restored.byId('skillsSh')!.baseUrl, d.byId('skillsSh')!.baseUrl);
    });
  });
}
