import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/models/skill.dart';

void main() {
  test('DiscoverableSkill round-trips complete catalog metrics', () {
    const skill = DiscoverableSkill(
      key: 'acme/skills:review',
      name: 'Review',
      description: 'Review code',
      directory: 'review',
      repoOwner: 'acme',
      repoName: 'skills',
      repoBranch: 'main',
      metrics: CatalogMetrics(
        adoptionCount: 123,
        rating: 4.5,
        ratingCount: 27,
        updatedAtMs: 1_750_000_000_000,
        publishedAtMs: 1_740_000_000_000,
      ),
    );

    final json = skill.toJson();
    final restored = DiscoverableSkill.fromJson(json);

    expect(json['metrics'], {
      'adoptionCount': 123,
      'rating': 4.5,
      'ratingCount': 27,
      'updatedAtMs': 1_750_000_000_000,
      'publishedAtMs': 1_740_000_000_000,
    });
    expect(restored.metrics.adoptionCount, 123);
    expect(restored.metrics.rating, 4.5);
    expect(restored.metrics.ratingCount, 27);
    expect(restored.metrics.updatedAtMs, 1_750_000_000_000);
    expect(restored.metrics.publishedAtMs, 1_740_000_000_000);
  });

  test('omitted skill metrics deserialize as nullable empty metrics', () {
    const skill = DiscoverableSkill(
      key: 'k',
      name: 'n',
      description: '',
      directory: 'n',
      repoOwner: 'o',
      repoName: 'r',
      repoBranch: 'main',
    );

    final json = skill.toJson();
    final restored = DiscoverableSkill.fromJson(json);

    expect(json.containsKey('metrics'), isFalse);
    expect(restored.metrics.adoptionCount, isNull);
    expect(restored.metrics.rating, isNull);
    expect(restored.metrics.ratingCount, isNull);
    expect(restored.metrics.updatedAtMs, isNull);
    expect(restored.metrics.publishedAtMs, isNull);
  });

  test('McpCatalogListing round-trips metrics and omits empty metrics', () {
    const listing = McpCatalogListing(
      id: 'fetch',
      title: 'Fetch',
      description: 'Fetch things',
      source: McpCatalogSource.smithery,
      serverSpec: {'type': 'http', 'url': 'https://example.com/mcp'},
      metrics: CatalogMetrics(
        adoptionCount: 88,
        rating: 4.2,
        ratingCount: 19,
        updatedAtMs: 1_750_000_000_000,
        publishedAtMs: 1_740_000_000_000,
      ),
    );

    final json = listing.toJson();
    final restored = McpCatalogListing.fromJson(json);
    final empty = const McpCatalogListing(
      id: 'empty',
      title: 'Empty',
      description: '',
      source: McpCatalogSource.builtin,
      serverSpec: {},
    );

    expect(json['metrics'], {
      'adoptionCount': 88,
      'rating': 4.2,
      'ratingCount': 19,
      'updatedAtMs': 1_750_000_000_000,
      'publishedAtMs': 1_740_000_000_000,
    });
    expect(restored.metrics.adoptionCount, 88);
    expect(restored.metrics.rating, 4.2);
    expect(restored.metrics.ratingCount, 19);
    expect(restored.metrics.updatedAtMs, 1_750_000_000_000);
    expect(restored.metrics.publishedAtMs, 1_740_000_000_000);
    expect(empty.toJson().containsKey('metrics'), isFalse);
  });

  test('old MCP useCount is accepted as adoption when metrics are absent', () {
    final restored = McpCatalogListing.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'description': '',
      'source': 'smithery',
      'serverSpec': const {},
      'useCount': 7,
    });

    expect(restored.metrics.adoptionCount, 7);
  });
}
