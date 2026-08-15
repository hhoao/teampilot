import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/plugin/plugin_repo_disk_cache_service.dart';
import 'package:teampilot/services/plugin/plugin_repo_git_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/utils/async_keyed_coalescer.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('plugin-cache-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('parses marketplace.json into DiscoverablePlugin list', () {
    final dir = Directory(p.join(tmp.path, 'mkt'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(
      p.join(dir.path, '.claude-plugin', 'marketplace.json'),
    ).writeAsStringSync('''
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
    File(
      p.join(dir.path, '.claude-plugin', 'marketplace.json'),
    ).writeAsStringSync('''
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
    expect(
      d.installedPluginId,
      'anthropics/claude-plugins-official/agent-sdk-dev',
    );
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
        const PluginMarketplace(owner: 'a', name: 'b', branch: 'main'),
      ),
      'a/b@main',
    );
  });

  group('coalesced syncMarketplace', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test('parallel calls on separate instances sync once', () async {
      final git = _CountingPluginGit();
      final coalescer = AsyncKeyedCoalescer();
      const market = PluginMarketplace(owner: 'acme', name: 'mkt');
      final a = PluginRepoDiskCacheService(
        gitService: git,
        coalescer: coalescer,
      );
      final b = PluginRepoDiskCacheService(
        gitService: git,
        coalescer: coalescer,
      );

      await Future.wait([
        a.syncMarketplace(market),
        b.syncMarketplace(market),
      ]);

      expect(git.syncCheckouts, 1);
    });
  });

  group('maxStaleness TTL', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test('fresh cache skips remote SHA check', () async {
      final git = _CountingPluginGit();
      const market = PluginMarketplace(owner: 'acme', name: 'mkt');
      final svc = PluginRepoDiskCacheService(gitService: git);

      await svc.syncMarketplace(market);

      final result = await svc.syncMarketplace(
        market,
        maxStaleness: const Duration(hours: 24),
      );

      expect(git.syncCheckouts, 1);
      expect(git.resolveShaCalls, 0);
      expect(result, isNotEmpty);
    });

    test('stale cache still checks remote SHA', () async {
      final git = _CountingPluginGit();
      const market = PluginMarketplace(owner: 'acme', name: 'mkt');
      final svc = PluginRepoDiskCacheService(gitService: git);
      final dir = await svc.syncMarketplace(market);
      final metaPath = AppStorage.fs.pathContext.join(
        dir,
        '.teampilot-plugin-cache-meta.json',
      );
      await AppStorage.fs.writeString(
        metaPath,
        jsonEncode({
          'configuredBranch': 'main',
          'resolvedBranch': 'main',
          'commitSha': 'abc123',
          'syncedAtMs': 1,
        }),
      );

      await svc.syncMarketplace(
        market,
        maxStaleness: const Duration(hours: 24),
      );

      expect(git.resolveShaCalls, 1);
      expect(git.syncCheckouts, 1);
    });
  });
}

class _CountingPluginGit extends PluginRepoGitService {
  int syncCheckouts = 0;
  int resolveShaCalls = 0;

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  syncCheckout(
    PluginMarketplace marketplace,
    Filesystem fs,
    String workDirPath,
  ) async {
    syncCheckouts++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await fs.ensureDir(workDirPath);
    await fs.ensureDir(fs.pathContext.join(workDirPath, '.claude-plugin'));
    await fs.writeString(
      fs.pathContext.join(workDirPath, '.claude-plugin', 'marketplace.json'),
      '{"name":"m","plugins":[]}',
    );
    return (
      entries: const <String, Uint8List>{},
      branch: marketplace.branch,
      commitSha: 'abc123',
    );
  }

  @override
  Future<({String sha, String branch})?> resolveRemoteShaWithFallback(
    String owner,
    String name,
    String configuredBranch,
  ) async {
    resolveShaCalls++;
    return null;
  }
}
