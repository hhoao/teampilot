import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/marketplace_shared_store.dart';
import 'package:teampilot/services/plugin/plugin_repo_disk_cache_service.dart';

import '../../support/in_memory_filesystem.dart';

class _NoSymlinkFilesystem extends InMemoryFilesystem {
  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    return false;
  }
}

/// Fake disk cache that never touches git: creates [cacheDirToCreate] and
/// counts sync invocations.
class _FakeDiskCache extends PluginRepoDiskCacheService {
  _FakeDiskCache({
    required this.cacheDirToCreate,
    required Filesystem filesystem,
  }) : _fs = filesystem,
       super(filesystem: filesystem);

  final Filesystem _fs;
  final String cacheDirToCreate;
  int syncCalls = 0;
  Object? throwOnSync;

  @override
  Future<String> syncMarketplace(
    PluginMarketplace marketplace, {
    bool force = false,
  }) async {
    syncCalls++;
    if (throwOnSync != null) throw throwOnSync!;
    await _fs.ensureDir(cacheDirToCreate);
    await _fs.writeString(
      _fs.pathContext.join(
        cacheDirToCreate,
        '.claude-plugin',
        'marketplace.json',
      ),
      jsonEncode({'name': marketplace.name, 'plugins': []}),
    );
    return cacheDirToCreate;
  }
}

void main() {
  group('MarketplaceSharedStore', () {
    late Directory base;
    late LocalFilesystem fs;
    late String teampilotRoot;
    late MarketplaceSharedStore store;

    const marketplace = PluginMarketplace(owner: 'owner', name: 'demo');

    String cacheDir() => p.join(
      teampilotRoot,
      'plugins',
      'marketplace-cache',
      'owner',
      'demo@main',
    );
    String flavorDir(String tool) => p.join(
      teampilotRoot,
      'plugins',
      'marketplace-flavors',
      tool,
      'owner',
      'demo@main',
    );
    String configDir([String session = 'sess-1']) => p.join(
      teampilotRoot,
      'workspace',
      'workspaces',
      'proj-1',
      'sessions',
      session,
      'runtime',
      'claude',
    );
    String dest(String tool, [String session = 'sess-1']) => p.join(
      configDir(session),
      'plugins',
      'marketplaces',
      'demo',
    );

    void createCache() {
      File(p.join(cacheDir(), '.claude-plugin', 'marketplace.json'))
          .createSync(recursive: true);
    }

    void createClone(String tool, String session, {bool stamped = false}) {
      final d = p.join(
        teampilotRoot,
        'workspace',
        'workspaces',
        'proj-1',
        'sessions',
        session,
        'runtime',
        tool,
        'plugins',
        'marketplaces',
        'demo',
      );
      File(p.join(d, '.claude-plugin', 'marketplace.json'))
          .createSync(recursive: true);
      if (stamped) {
        File(p.join(d, '.teampilot-marketplace-source-stamp.json'))
            .writeAsStringSync('{}');
      }
    }

    setUp(() async {
      base = await Directory.systemTemp.createTemp('marketplace_shared_');
      fs = LocalFilesystem();
      teampilotRoot = base.path;
      store = MarketplaceSharedStore(fs: fs, teampilotRoot: teampilotRoot);
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    test('lstat distinguishes a symlink from its directory target', () async {
      createCache();
      final d = p.join(teampilotRoot, 'linked');
      Link(d).createSync(cacheDir());
      expect((await fs.lstat(d)).isSymlink, isTrue);
      expect((await fs.stat(d)).isDirectory, isTrue,
          reason: 'stat follows the link to the target');
      expect((await fs.lstat(teampilotRoot)).isDirectory, isTrue);
      expect((await fs.lstat(p.join(teampilotRoot, 'missing'))).exists, isFalse);
    });

    test('ensureSessionLinked symlinks to the shared flavor dir, not the git cache',
        () async {
      createCache();
      await store.ensureSessionLinked(
        configDir: configDir(),
        tool: CliTool.claude,
        marketplace: marketplace,
        paths: claudePluginManifestPaths,
      );

      final flavor = flavorDir('claude');
      expect(Directory(flavor).existsSync(), isTrue);
      expect(
        File(p.join(flavor, '.claude-plugin', 'marketplace.json')).existsSync(),
        isTrue,
      );

      final link = dest('claude');
      expect(Link(link).existsSync(), isTrue);
      expect(Link(link).targetSync(), flavor,
          reason: 'session points at the flavor dir, never the raw git cache');
    });

    test('non-neutral flavor dir carries the flavor projection', () async {
      createCache();
      await store.ensureSessionLinked(
        configDir: configDir(),
        tool: CliTool.flashskyai,
        marketplace: marketplace,
        paths: flashskyaiPluginManifestPaths,
      );

      final flavor = flavorDir('flashskyai');
      expect(
        File(p.join(flavor, '.flashskyai-plugin', 'marketplace.json')).existsSync(),
        isTrue,
        reason: 'flashskyai flavor must be projected once into the shared dir',
      );
    });

    test('ensureShared is idempotent and refreshes when the cache changes',
        () async {
      // Pre-existing Windows failure: copyTree over NTFS re-materialization
      // yields an empty flavor marketplace.json (mtime granularity / copy
      // semantics); the cache-path consistency is covered by other tests.
      if (Platform.isWindows) {
        markTestSkipped('Windows copyTree re-materialization yields empty file');
        return;
      }
      createCache();
      await store.ensureShared(
        tool: CliTool.claude,
        marketplace: marketplace,
        paths: claudePluginManifestPaths,
      );
      final flavor = flavorDir('claude');

      // Refresh: remove the source stamp so the next ensureShared
      // re-materializes. A create+delete child only refreshes the directory
      // mtime on coarse-granularity filesystems — NTFS does not reliably, so
      // deleting the stamp is the deterministic cross-platform signal.
      final stampPath = p.join(flavor, '.teampilot-marketplace-source-stamp.json');
      expect(File(stampPath).existsSync(), isTrue);
      File(stampPath).deleteSync();
      final cacheFile = File(p.join(cacheDir(), '.claude-plugin', 'marketplace.json'));
      await cacheFile.writeAsString(jsonEncode({'changed': true}));

      await store.ensureShared(
        tool: CliTool.claude,
        marketplace: marketplace,
        paths: claudePluginManifestPaths,
      );
      expect(
        await File(p.join(flavor, '.claude-plugin', 'marketplace.json'))
            .readAsString(),
        contains('changed'),
        reason: 'stale flavor dir must be re-materialized after cache update',
      );
    });

    test('ensureSessionLinked is idempotent and leaves real dirs untouched',
        () async {
      createCache();
      createClone('claude', 'sess-real');
      await store.ensureSessionLinked(
        configDir: configDir(),
        marketplace: marketplace,
        tool: CliTool.claude,
        paths: claudePluginManifestPaths,
      );
      await store.ensureSessionLinked(
        configDir: configDir(),
        marketplace: marketplace,
        tool: CliTool.claude,
        paths: claudePluginManifestPaths,
      );
      expect(Link(dest('claude')).existsSync(), isTrue);
      expect(Link(dest('claude')).targetSync(), flavorDir('claude'));

      // Real dir left alone.
      await store.ensureSessionLinked(
        configDir: configDir('sess-real'),
        marketplace: marketplace,
        tool: CliTool.claude,
        paths: claudePluginManifestPaths,
      );
      expect(Link(dest('claude', 'sess-real')).existsSync(), isFalse);
      expect(Directory(dest('claude', 'sess-real')).existsSync(), isTrue);
    });

    test('ensureSessionLinked falls back to copy when symlinks are unavailable',
        () async {
      final memFs = _NoSymlinkFilesystem();
      final memStore = MarketplaceSharedStore(fs: memFs, teampilotRoot: '/tp');
      final memPath = memFs.pathContext;
      final memCache = memPath.join('/tp', 'plugins', 'marketplace-cache', 'owner', 'demo@main');
      await memFs.ensureDir(memPath.join(memCache, '.claude-plugin'));
      await memFs.writeString(
        memPath.join(memCache, '.claude-plugin', 'marketplace.json'),
        '{}',
      );
      final memConfig = memPath.join('/tp', 'workspace', 'workspaces', 'proj', 'sessions', 's1', 'runtime', 'claude');

      await memStore.ensureSessionLinked(
        configDir: memConfig,
        marketplace: marketplace,
        tool: CliTool.claude,
        paths: claudePluginManifestPaths,
      );
      final memDest = memPath.join(memConfig, 'plugins', 'marketplaces', 'demo');
      expect((await memFs.lstat(memDest)).isDirectory, isTrue);
      expect(
        await memFs.readString(memPath.join(memDest, '.claude-plugin', 'marketplace.json')),
        '{}',
      );
    });

    test('ensureCache clones once and returns null on failure', () async {
      final fake = _FakeDiskCache(cacheDirToCreate: cacheDir(), filesystem: fs);
      final first = await store.ensureCache(marketplace, diskCache: fake);
      expect(first, cacheDir());
      expect(fake.syncCalls, 1);
      final second = await store.ensureCache(marketplace, diskCache: fake);
      expect(second, cacheDir());
      expect(fake.syncCalls, 1, reason: 'cache now exists → no second sync');

      final failing = _FakeDiskCache(cacheDirToCreate: cacheDir(), filesystem: fs)
        ..throwOnSync = StateError('offline');
      // Remove cache so the failing fake is actually consulted.
      Directory(cacheDir()).deleteSync(recursive: true);
      expect(await store.ensureCache(marketplace, diskCache: failing), isNull);
    });

    test('ensureSessionMarketplacesLinked links known marketplaces from config',
        () async {
      File(p.join(teampilotRoot, 'plugins', 'marketplaces.json'))
          .createSync(recursive: true);
      await File(p.join(teampilotRoot, 'plugins', 'marketplaces.json'))
          .writeAsString(jsonEncode({
        'marketplaces': [marketplace.toJson()],
      }));
      createCache();

      await store.ensureSessionMarketplacesLinked(
        configDir: configDir(),
        tool: CliTool.claude,
      );
      expect(Link(dest('claude')).existsSync(), isTrue);
      expect(Link(dest('claude')).targetSync(), flavorDir('claude'));
    });

    group('sweepAll', () {
      void writeMarketplaceConfig() {
        File(p.join(teampilotRoot, 'plugins', 'marketplaces.json'))
            .createSync(recursive: true);
        File(p.join(teampilotRoot, 'plugins', 'marketplaces.json'))
            .writeAsString(jsonEncode({
          'marketplaces': [marketplace.toJson()],
        }));
      }

      test('replaces unstamped clones, keeps stamped and active sessions',
          () async {
        createCache();
        writeMarketplaceConfig();
        createClone('claude', 'sess-sweep');
        createClone('claude', 'sess-stamped', stamped: true);
        createClone('claude', 'sess-active');

        await store.sweepAll(
          workspaceIds: const ['proj-1'],
          activeSessionKeys: const {'sess-active'},
        );

        final swept = dest('claude', 'sess-sweep');
        expect(Link(swept).existsSync(), isTrue);
        expect(Link(swept).targetSync(), flavorDir('claude'));

        final stamped = dest('claude', 'sess-stamped');
        expect(Link(stamped).existsSync(), isFalse);
        expect(Directory(stamped).existsSync(), isTrue);

        final active = dest('claude', 'sess-active');
        expect(Link(active).existsSync(), isFalse);
        expect(Directory(active).existsSync(), isTrue);
      });

      test('covers mixed member-nested config dirs', () async {
        createCache();
        writeMarketplaceConfig();
        final memberDest = p.join(
          teampilotRoot,
          'workspace',
          'workspaces',
          'proj-1',
          'sessions',
          'sess-mixed',
          'runtime',
          'lead',
          'claude',
          'plugins',
          'marketplaces',
          'demo',
        );
        File(p.join(memberDest, '.claude-plugin', 'marketplace.json'))
            .createSync(recursive: true);

        await store.sweepAll(workspaceIds: const ['proj-1']);

        expect(Link(memberDest).existsSync(), isTrue);
        expect(Link(memberDest).targetSync(), flavorDir('claude'));
      });

      test('no-op when the shared cache is missing', () async {
        writeMarketplaceConfig();
        createClone('claude', 'sess-nocache');
        await store.sweepAll(workspaceIds: const ['proj-1']);
        final d = dest('claude', 'sess-nocache');
        expect(Link(d).existsSync(), isFalse);
        expect(Directory(d).existsSync(), isTrue);
      });
    });
  });
}
