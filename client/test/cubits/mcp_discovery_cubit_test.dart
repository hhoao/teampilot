import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/mcp_discovery_cubit.dart';
import 'package:teampilot/models/mcp_catalog_listing.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/mcp/mcp_discovery_disk_cache_service.dart';
import 'package:teampilot/services/mcp/mcp_registry_browse_service.dart';
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
  _FakeSmithery() : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;

  @override
  Future<SmitherySearchResult> search(
    String query, {
    required String baseUrl,
    String? apiToken,
    int page = 1,
    int pageSize = 20,
  }) async {
    searches++;
    return SmitherySearchResult(
      items: const [],
      page: 1,
      totalPages: 1,
      query: query,
    );
  }
}

class _FakeRegistry extends McpRegistryBrowseService {
  _FakeRegistry() : super(client: MockClient((_) async => http.Response('{}', 200)));

  int searches = 0;

  @override
  Future<McpRegistryBrowseResult> search(
    String query, {
    required String baseUrl,
    String? cursor,
    int pageSize = 20,
  }) async {
    searches++;
    return McpRegistryBrowseResult(items: const [], nextCursor: null, query: query);
  }
}

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

  test('manual mode with no disk cache fetches once (initialization)', () async {
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
  });

  test('auto mode with fresh cache does not fetch remote', () async {
    await _seedCache(
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
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
}
