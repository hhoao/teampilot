import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/mcp_discovery_cubit.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/models/mcp_registry_source.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/mcp/mcp_discovery_disk_cache_service.dart';
import 'package:teampilot/services/mcp/mcp_registry_browse_service.dart';
import 'package:teampilot/services/mcp/mcp_registry_config_service.dart';
import 'package:teampilot/services/mcp/smithery_mcp_service.dart';

import '../support/post_frame_test_harness.dart';

const _listing = McpCatalogListing(
  id: 'acme/foo',
  title: 'Foo',
  description: 'd',
  source: McpCatalogSource.smithery,
  serverSpec: {'command': 'foo'},
);

class _FakeSmithery extends SmitheryMcpService {
  _FakeSmithery({this.result, this.error})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;
  final SmitherySearchResult? result;
  final Object? error;

  @override
  Future<SmitherySearchResult> search(
    String query, {
    required String baseUrl,
    String? apiToken,
    int page = 1,
    int pageSize = 20,
  }) async {
    searches++;
    if (error != null) throw error!;
    if (result != null) return result!;
    return SmitherySearchResult(
      items: const [],
      page: 1,
      totalPages: 1,
      query: query,
    );
  }
}

class _FakeRegistry extends McpRegistryBrowseService {
  _FakeRegistry({this.result, this.error})
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;
  final McpRegistryBrowseResult? result;
  final Object? error;

  @override
  Future<McpRegistryBrowseResult> search(
    String query, {
    required String baseUrl,
    String? cursor,
    int pageSize = 20,
  }) async {
    searches++;
    if (error != null) throw error!;
    if (result != null) return result!;
    return McpRegistryBrowseResult(
      items: const [],
      nextCursor: null,
      query: query,
    );
  }
}

class _FakeConfig extends McpRegistryConfigService {
  _FakeConfig(this.config);

  final McpRegistrySourcesConfig config;

  @override
  Future<McpRegistrySourcesConfig> load() async => config;
}

McpRegistrySourcesConfig _enabledSources() => const McpRegistrySourcesConfig(
  sources: [
    McpRegistrySourceConfig(
      kind: McpRegistrySourceKind.smithery,
      baseUrl: 'https://smithery.test',
    ),
    McpRegistrySourceConfig(
      kind: McpRegistrySourceKind.officialRegistry,
      baseUrl: 'https://official.test',
    ),
  ],
);

McpCatalogListing _listingWithMetrics(
  String id, {
  required int uses,
  required int updatedAtMs,
  McpCatalogSource source = McpCatalogSource.smithery,
}) => McpCatalogListing(
  id: id,
  title: id,
  description: 'd',
  source: source,
  serverSpec: const {'command': 'run'},
  metrics: CatalogMetrics(adoptionCount: uses, updatedAtMs: updatedAtMs),
);

Future<void> _seedCache({required int syncedAtMs}) async {
  final disk = McpDiscoveryDiskCacheService();
  await disk.write(
    sourceKey: mcpDiscoveryCacheSmithery,
    snapshot: McpDiscoveryDiskSnapshot(
      items: const [_listing],
      query: '',
      syncedAtMs: syncedAtMs,
    ),
  );
  await disk.write(
    sourceKey: mcpDiscoveryCacheOfficial,
    snapshot: McpDiscoveryDiskSnapshot(
      items: const [_listing],
      query: '',
      syncedAtMs: syncedAtMs,
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('manual mode with disk cache does not fetch remote', () async {
    await _seedCache(syncedAtMs: 1);
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: DiscoverySettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      ),
    );

    await cubit.initialize();

    expect(smithery.searches, 0);
    expect(registry.searches, 0);
    expect(cubit.state.smitheryItems, isNotEmpty);
    expect(cubit.state.officialItems, isNotEmpty);
  });

  test(
    'manual mode with no disk cache fetches once (initialization)',
    () async {
      final smithery = _FakeSmithery();
      final registry = _FakeRegistry();
      final cubit = McpDiscoveryCubit(
        smithery: smithery,
        registry: registry,
        discoverySettings: DiscoverySettingsCubit(
          repository: InMemoryAppSettingsRepository(),
        ),
      );

      await cubit.initialize();

      expect(smithery.searches, 1);
      expect(registry.searches, 1);
    },
  );

  test('auto mode with fresh cache does not fetch remote', () async {
    await _seedCache(syncedAtMs: DateTime.now().millisecondsSinceEpoch);
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: settings,
    );

    await cubit.initialize();

    expect(smithery.searches, 0);
    expect(registry.searches, 0);
  });

  test('auto mode with stale cache fetches remote', () async {
    await _seedCache(syncedAtMs: 1);
    final smithery = _FakeSmithery();
    final registry = _FakeRegistry();
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = McpDiscoveryCubit(
      smithery: smithery,
      registry: registry,
      discoverySettings: settings,
    );

    await cubit.initialize();

    expect(smithery.searches, 1);
    expect(registry.searches, 1);
  });

  test(
    'sort is independent of loading and defaults to adoption descending',
    () async {
      final smithery = _FakeSmithery(
        result: SmitherySearchResult(
          items: [
            _listingWithMetrics('low', uses: 2, updatedAtMs: 20),
            _listingWithMetrics('high', uses: 20, updatedAtMs: 10),
          ],
          page: 1,
          totalPages: 1,
          query: '',
        ),
      );
      final registry = _FakeRegistry(
        result: McpRegistryBrowseResult(
          items: [
            _listingWithMetrics(
              'official-low',
              uses: 1,
              updatedAtMs: 20,
              source: McpCatalogSource.officialRegistry,
            ),
            _listingWithMetrics(
              'official-high',
              uses: 10,
              updatedAtMs: 10,
              source: McpCatalogSource.officialRegistry,
            ),
          ],
          nextCursor: null,
          query: '',
        ),
      );
      final cubit = McpDiscoveryCubit(
        registryConfig: _FakeConfig(_enabledSources()),
        smithery: smithery,
        registry: registry,
      );

      await cubit.initialize();

      expect(cubit.state.discoverySort, CatalogSortKey.adoption);
      expect(cubit.state.smitheryItems.map((item) => item.id), ['high', 'low']);
      expect(cubit.state.officialItems.map((item) => item.id), [
        'official-high',
        'official-low',
      ]);

      final searches = smithery.searches + registry.searches;
      cubit.setDiscoverySort(CatalogSortKey.updated);

      expect(smithery.searches + registry.searches, searches);
      expect(cubit.state.smitheryItems.map((item) => item.id), ['low', 'high']);
      expect(cubit.state.officialItems.map((item) => item.id), [
        'official-low',
        'official-high',
      ]);
    },
  );

  test(
    'partial source failure keeps successful results and records source failure',
    () async {
      final successful = _listingWithMetrics(
        'smithery-ok',
        uses: 3,
        updatedAtMs: 1,
      );
      final cubit = McpDiscoveryCubit(
        registryConfig: _FakeConfig(_enabledSources()),
        smithery: _FakeSmithery(
          result: SmitherySearchResult(
            items: [successful],
            page: 1,
            totalPages: 1,
            query: '',
          ),
        ),
        registry: _FakeRegistry(error: Exception('official unavailable')),
      );

      await cubit.initialize();

      expect(cubit.state.smitheryItems, [successful]);
      expect(cubit.state.officialItems, isEmpty);
      expect(cubit.state.discoveryFailures, hasLength(1));
      expect(cubit.state.discoveryFailures.single.sourceId, 'official');
      expect(cubit.state.errorMessage, isNull);
    },
  );

  test('refresh failure preserves cached source items', () async {
    final cached = _listingWithMetrics('cached', uses: 4, updatedAtMs: 1);
    await McpDiscoveryDiskCacheService().write(
      sourceKey: mcpDiscoveryCacheSmithery,
      snapshot: McpDiscoveryDiskSnapshot(
        items: [cached],
        query: '',
        syncedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final cubit = McpDiscoveryCubit(
      registryConfig: _FakeConfig(_enabledSources()),
      smithery: _FakeSmithery(error: Exception('temporary failure')),
      registry: _FakeRegistry(),
    );

    await cubit.initialize();
    expect(cubit.state.smitheryItems, [cached]);

    cubit.setSource(McpDiscoverySource.smithery);
    await cubit.refreshRemote();

    expect(cubit.state.remoteItems, [cached]);
    expect(cubit.state.smitheryItems, [cached]);
    expect(cubit.state.discoveryFailures.single.sourceId, 'smithery');
  });
}
