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

  test('parses object source entries without failing the whole manifest', () {
    final dir = Directory(p.join(tmp.path, 'official-like'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'marketplace.json')).writeAsStringSync('''
{
  "plugins": [
    {
      "name": "local-one",
      "description": "bundled",
      "source": "./plugins/local-one"
    },
    {
      "name": "external-one",
      "description": "remote",
      "homepage": "https://example.com/plugin",
      "source": {
        "source": "git-subdir",
        "url": "https://github.com/other/vendor.git",
        "path": "plugins/x",
        "ref": "main"
      }
    }
  ]
}
''');

    final svc = PluginRepoDiskCacheService();
    final list = svc.parseMarketplaceManifest(
      directory: dir.path,
      marketplace: const PluginMarketplace(
        owner: 'anthropics',
        name: 'claude-plugins-official',
      ),
    );
    expect(list, hasLength(2));
    expect(list.first.localInstall, isTrue);
    expect(list.first.source, './plugins/local-one');
    expect(list.last.localInstall, isFalse);
    expect(list.last.externalSource, isNotNull);
    expect(list.last.canInstall, isTrue);
    expect(list.last.readmeUrl, 'https://example.com/plugin');
  });

  test('discoverable matches installed plugin id format', () {
    const d = DiscoverablePlugin(
      key: 'anthropics:claude-plugins-official:agent-sdk-dev',
      name: 'agent-sdk-dev',
      description: '',
      version: '1.0.0',
      marketplaceOwner: 'anthropics',
      marketplaceName: 'claude-plugins-official',
      marketplaceBranch: 'main',
      source: './plugins/agent-sdk-dev',
    );
    expect(d.installedPluginId, 'anthropics/claude-plugins-official/agent-sdk-dev');
    expect(
      d.isInstalledAmong(const [
        Plugin(
          id: 'anthropics/claude-plugins-official/agent-sdk-dev',
          name: 'agent-sdk-dev',
          description: '',
          version: '1.0.0',
          directory: 'anthropics__claude-plugins-official__agent-sdk-dev',
          marketplaceOwner: 'anthropics',
          marketplaceName: 'claude-plugins-official',
          installedAt: 0,
          updatedAt: 0,
        ),
      ]),
      isTrue,
    );
    expect(d.isInstalledAmong(const []), isFalse);
  });

  test('repoKey is stable for owner/name/branch', () {
    expect(
      PluginRepoDiskCacheService.repoKey(
        const PluginMarketplace(owner: 'a', name: 'b', branch: 'main')),
      'a/b@main',
    );
  });
}
