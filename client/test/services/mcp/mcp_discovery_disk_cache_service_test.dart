import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/services/mcp/mcp_discovery_disk_cache_service.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('write and read round-trips empty-query browse cache', () async {
    const listing = McpCatalogListing(
      id: 'fetch',
      title: 'Fetch',
      description: 'HTTP fetch MCP',
      source: McpCatalogSource.smithery,
      serverSpec: {'type': 'http', 'url': 'https://example.com/mcp'},
      tags: ['smithery'],
    );
    final svc = McpDiscoveryDiskCacheService();
    await svc.write(
      sourceKey: mcpDiscoveryCacheSmithery,
      snapshot: McpDiscoveryDiskSnapshot(
        items: const [listing],
        query: '',
        syncedAtMs: 1_700_000_000_000,
        smitheryPage: 1,
        smitheryTotalPages: 3,
      ),
    );

    final cached = await svc.read(mcpDiscoveryCacheSmithery);
    expect(cached, isNotNull);
    expect(cached!.query, '');
    expect(cached.items, hasLength(1));
    expect(cached.items.first.id, 'fetch');
    expect(cached.smitheryTotalPages, 3);
  });

  test('write skips non-empty query snapshots', () async {
    final svc = McpDiscoveryDiskCacheService();
    await svc.write(
      sourceKey: mcpDiscoveryCacheOfficial,
      snapshot: McpDiscoveryDiskSnapshot(
        items: const [
          McpCatalogListing(
            id: 'github',
            title: 'GitHub',
            description: '',
            source: McpCatalogSource.officialRegistry,
            serverSpec: {'type': 'http', 'url': 'https://example.com'},
          ),
        ],
        query: 'github',
        syncedAtMs: 1,
      ),
    );

    expect(await svc.read(mcpDiscoveryCacheOfficial), isNull);
  });

  test('delete removes cached source directory', () async {
    final svc = McpDiscoveryDiskCacheService();
    await svc.write(
      sourceKey: mcpDiscoveryCacheOfficial,
      snapshot: const McpDiscoveryDiskSnapshot(
        items: [],
        query: '',
        syncedAtMs: 1,
      ),
    );
    expect(await svc.read(mcpDiscoveryCacheOfficial), isNotNull);

    await svc.delete(mcpDiscoveryCacheOfficial);
    expect(await svc.read(mcpDiscoveryCacheOfficial), isNull);
  });
}
