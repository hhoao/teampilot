import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin_repo_disk_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('plugin-cache-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('parses marketplace.json into DiscoverablePlugin list', () {
    final dir = Directory(p.join(tmp.path, 'mkt'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'marketplace.json')).writeAsStringSync('''
{
  "name": "acme-market",
  "plugins": [
    {
      "name": "p1",
      "description": "first",
      "version": "1.0.0",
      "source": "./plugins/p1",
      "category": "dev"
    },
    {
      "name": "p2",
      "description": "second",
      "version": "0.1.0",
      "source": ".",
      "keywords": ["k1"]
    }
  ]
}
''');

    final svc = PluginRepoDiskCacheService();
    final list = svc.parseMarketplaceManifest(
      directory: dir.path,
      marketplace: const PluginMarketplace(owner: 'acme', name: 'mkt'),
    );
    expect(list, hasLength(2));
    expect(list.first.name, 'p1');
    expect(list.first.categories, contains('dev'));
    expect(list.last.keywords, contains('k1'));
  });

  test('repoKey is stable for owner/name/branch', () {
    expect(
      PluginRepoDiskCacheService.repoKey(
        const PluginMarketplace(owner: 'a', name: 'b', branch: 'main')),
      'a/b@main',
    );
  });
}
