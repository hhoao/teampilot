import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/services/mcp/mcp_catalog_mapper.dart';

void main() {
  test(
    'Smithery useCount maps to adoption and explicit stats are normalized',
    () {
      final listing = McpCatalogMapper.fromSmitheryJson({
        'qualifiedName': '@acme/fetch',
        'displayName': 'Fetch',
        'description': 'Fetch things',
        'deploymentUrl': 'https://example.com/mcp',
        'useCount': 456,
        'rating': 4.4,
        'ratingCount': 23,
        'updatedAt': 1_750_000_000,
        'publishedAt': 1_740_000_000,
      });

      expect(listing, isNotNull);
      expect(listing!.source, McpCatalogSource.smithery);
      expect(listing.metrics.adoptionCount, 456);
      expect(listing.metrics.rating, 4.4);
      expect(listing.metrics.ratingCount, 23);
      expect(listing.metrics.updatedAtMs, 1_750_000_000_000);
      expect(listing.metrics.publishedAtMs, 1_740_000_000_000);
    },
  );

  test('MCP stars do not become a rating without an explicit rating field', () {
    final listing = McpCatalogMapper.fromSmitheryJson({
      'qualifiedName': '@acme/stars',
      'deploymentUrl': 'https://example.com/mcp',
      'stars': 100,
    });

    expect(listing, isNotNull);
    expect(listing!.metrics.rating, isNull);
    expect(listing.metrics.adoptionCount, isNull);
  });
}
