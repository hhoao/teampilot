import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  test('maps and round-trips discoverable plugin catalog metrics', () {
    final plugin = DiscoverablePlugin.fromJson(const {
      'key': 'acme:market:reviewer',
      'name': 'reviewer',
      'description': 'Reviews code',
      'version': '1.0.0',
      'marketplaceOwner': 'acme',
      'marketplaceName': 'market',
      'marketplaceBranch': 'main',
      'source': './plugins/reviewer',
      'metrics': {
        'adoptionCount': 987,
        'rating': 4.25,
        'ratingCount': 24,
        'updatedAtMs': 1700000000001,
        'publishedAtMs': 1690000000000,
      },
    });

    expect(plugin.metrics.adoptionCount, 987);
    expect(plugin.metrics.rating, 4.25);
    expect(plugin.metrics.ratingCount, 24);
    expect(plugin.metrics.updatedAtMs, 1700000000001);
    expect(plugin.metrics.publishedAtMs, 1690000000000);
    expect(
      DiscoverablePlugin.fromJson(plugin.toJson()).metrics.updatedAtMs,
      1700000000001,
    );
  });

  test('omitted plugin metrics do not become a local install count', () {
    final plugin = DiscoverablePlugin.fromJson(const {
      'key': 'acme:market:reviewer',
      'name': 'reviewer',
      'description': 'Reviews code',
      'version': '1.0.0',
      'marketplaceOwner': 'acme',
      'marketplaceName': 'market',
      'marketplaceBranch': 'main',
      'source': './plugins/reviewer',
    });

    expect(plugin.metrics, isA<CatalogMetrics>());
    expect(plugin.metrics.adoptionCount, isNull);
    expect(plugin.metrics.rating, isNull);
    expect(plugin.metrics.ratingCount, isNull);
    expect(plugin.metrics.updatedAtMs, isNull);
    expect(plugin.metrics.publishedAtMs, isNull);
    expect(plugin.toJson().containsKey('metrics'), isFalse);
  });

  test('plugin marketplace cache preserves metrics when rewritten', () async {
    final tmp = Directory.systemTemp.createTempSync('plugin-metrics-cache-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
    addTearDown(() => tmp.deleteSync(recursive: true));

    final service = PluginRepoService();
    await service.saveMarketplaces([
      const PluginMarketplace(
        owner: 'acme',
        name: 'market',
        metrics: CatalogMetrics(adoptionCount: 12, rating: 4.0),
      ),
    ]);

    final loaded = await service.loadMarketplaces();
    expect(loaded.single.metrics.adoptionCount, 12);
    expect(loaded.single.metrics.rating, 4.0);

    final raw = File(
      p.join(tmp.path, 'plugins', 'marketplaces.json'),
    ).readAsStringSync();
    expect(raw, contains('"metrics"'));
  });
}
