import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_bundle_pool_service.dart';

import '../../support/in_memory_filesystem.dart';

Plugin _plugin(
  String id,
  String name, {
  String? directory,
  String version = '1.0.0',
  String? marketplaceOwner,
  String? marketplaceName,
}) => Plugin(
  id: id,
  name: name,
  description: '',
  version: version,
  directory: directory ?? name,
  marketplaceOwner: marketplaceOwner,
  marketplaceName: marketplaceName,
  capabilities: const PluginCapabilities(),
  installedAt: 0,
  updatedAt: 0,
);

/// Installed root layout mirroring `AppPaths.pluginsDirForTeampilotRoot`.
String _installedRoot(String base) => p.join(base, 'plugins', 'installed');

Future<void> _writeNeutralBundle(
  String root,
  String name, {
  String version = '1.0.0',
}) async {
  Directory(p.join(root, name, '.plugin')).createSync(recursive: true);
  File(
    p.join(root, name, '.plugin', 'plugin.json'),
  ).writeAsStringSync(
    '{"name":"$name","version":"$version","description":""}',
  );
}

class _NoSymlinkFilesystem extends InMemoryFilesystem {
  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    return false;
  }
}

void main() {
  late Directory base;
  late LocalFilesystem fs;
  late String sourceRoot;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('plugin_pool_');
    fs = LocalFilesystem();
    sourceRoot = _installedRoot(base.path);
    Directory(sourceRoot).createSync(recursive: true);
  });

  tearDown(() async {
    if (await base.exists()) {
      await base.delete(recursive: true);
    }
  });

  PluginBundlePoolService service() => PluginBundlePoolService(
    fs: fs,
    sourceRoot: sourceRoot,
  );

  test('links the enabled bundle into the pool and projects the CLI flavor',
      () async {
    await _writeNeutralBundle(sourceRoot, 'demo-bundle');
    final poolDir = p.join(base.path, 'session', 'plugins');
    final installed = p.join(sourceRoot, 'demo-bundle');

    final result = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );

    expect(result.linked, ['demo-bundle']);
    expect(result.errors, isEmpty);
    expect(result.skippedMissingIds, isEmpty);
    final dest = p.join(poolDir, 'demo-bundle');
    expect(Directory(dest).existsSync(), isTrue);
    // Session pool keeps a symlink; missing Claude flavor is seeded into the
    // shared installed root once (not a per-session full copyTree).
    if (Platform.isLinux || Platform.isMacOS) {
      expect(Link(dest).existsSync(), isTrue);
      expect(Link(dest).targetSync(), installed);
    }
    expect(File(p.join(dest, '.plugin', 'plugin.json')).existsSync(), isTrue);
    expect(
      File(p.join(dest, '.claude-plugin', 'plugin.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(installed, '.claude-plugin', 'plugin.json')).existsSync(),
      isTrue,
      reason: 'flavor projection seeds the shared installed bundle',
    );
    expect(result.memberProvisionStampJson, isNotNull);
  });

  test(
    'keeps a symlink for Claude when installed already has the flavor',
    () async {
      await _writeNeutralBundle(sourceRoot, 'demo-bundle');
      Directory(p.join(sourceRoot, 'demo-bundle', '.claude-plugin'))
          .createSync(recursive: true);
      File(
        p.join(sourceRoot, 'demo-bundle', '.claude-plugin', 'plugin.json'),
      ).writeAsStringSync(
        '{"name":"demo","version":"1.0.0","description":""}',
      );
      final poolDir = p.join(base.path, 'session', 'plugins');
      final installed = p.join(sourceRoot, 'demo-bundle');

      final result = await service().reconcile(
        poolDir: poolDir,
        enabledPluginIds: ['acme/demo'],
        installedCatalog: [
          _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
        ],
        paths: claudePluginManifestPaths,
      );

      expect(result.linked, ['demo-bundle']);
      final dest = p.join(poolDir, 'demo-bundle');
      if (Platform.isLinux || Platform.isMacOS) {
        expect(Link(dest).existsSync(), isTrue);
        expect(Link(dest).targetSync(), installed);
      }
    },
  );

  test(
    'keeps a symlink for neutral paths that do not need flavor projection',
    () async {
      await _writeNeutralBundle(sourceRoot, 'demo-bundle');
      final poolDir = p.join(base.path, 'session', 'plugins');
      final installed = p.join(sourceRoot, 'demo-bundle');

      final result = await service().reconcile(
        poolDir: poolDir,
        enabledPluginIds: ['acme/demo'],
        installedCatalog: [
          _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
        ],
        paths: neutralPluginManifestPaths,
      );

      expect(result.linked, ['demo-bundle']);
      expect(result.errors, isEmpty);
      final dest = p.join(poolDir, 'demo-bundle');
      if (Platform.isLinux || Platform.isMacOS) {
        expect(Link(dest).existsSync(), isTrue);
        expect(Link(dest).targetSync(), installed);
      }
      expect(
        File(p.join(dest, '.plugin', 'plugin.json')).existsSync(),
        isTrue,
      );
    },
  );
  test('removes stale bundles but keeps writer-managed entries', () async {
    await _writeNeutralBundle(sourceRoot, 'demo-bundle');
    final poolDir = p.join(base.path, 'session', 'plugins');
    Directory(p.join(poolDir, 'stale-bundle')).createSync(recursive: true);
    Directory(p.join(poolDir, 'marketplaces')).createSync(recursive: true);
    File(p.join(poolDir, 'known_marketplaces.json')).writeAsStringSync('{}');

    await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );

    expect(Directory(p.join(poolDir, 'stale-bundle')).existsSync(), isFalse);
    expect(Directory(p.join(poolDir, 'demo-bundle')).existsSync(), isTrue);
    expect(
      Directory(p.join(poolDir, 'marketplaces')).existsSync(),
      isTrue,
      reason: 'writer-managed marketplaces/ must survive reconcile',
    );
    expect(
      File(p.join(poolDir, 'known_marketplaces.json')).existsSync(),
      isTrue,
      reason: 'writer-managed known_marketplaces.json must survive reconcile',
    );
  });

  test('is idempotent once the pool matches the enabled bundles', () async {
    await _writeNeutralBundle(sourceRoot, 'demo-bundle');
    final poolDir = p.join(base.path, 'session', 'plugins');
    final catalog = [
      _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
    ];

    final first = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: catalog,
      paths: claudePluginManifestPaths,
    );
    final second = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: catalog,
      paths: claudePluginManifestPaths,
    );

    expect(first.linked, ['demo-bundle']);
    expect(second.linked, isEmpty, reason: 'second reconcile is a no-op');
    expect(second.memberProvisionStampJson, isNotNull);
    expect(Directory(p.join(poolDir, 'demo-bundle')).existsSync(), isTrue);
  });

  test('re-links when the installed bundle version changes', () async {
    await _writeNeutralBundle(sourceRoot, 'demo-bundle', version: '1.0.0');
    final poolDir = p.join(base.path, 'session', 'plugins');

    await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );

    // Simulate a re-install: bump the version.
    await _writeNeutralBundle(sourceRoot, 'demo-bundle', version: '2.0.0');

    final result = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle', version: '2.0.0'),
      ],
      paths: claudePluginManifestPaths,
    );

    expect(result.linked, ['demo-bundle'], reason: 'version change re-links');
    final destManifest = File(
      p.join(poolDir, 'demo-bundle', '.plugin', 'plugin.json'),
    ).readAsStringSync();
    expect(destManifest, contains('2.0.0'));
  });

  test('skips not-installed ids without touching the pool', () async {
    final poolDir = p.join(base.path, 'session', 'plugins');

    final result = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['missing/plugin/x'],
      installedCatalog: const [],
      paths: claudePluginManifestPaths,
    );

    expect(result.skippedMissingIds, ['missing/plugin/x']);
    expect(result.linked, isEmpty);
    // No bundle entries materialized (only the member provision stamp file).
    expect((await fs.listDir(poolDir)).where((e) => e.isDirectory), isEmpty);
  });

  test('clears all bundle entries when nothing is enabled', () async {
    await _writeNeutralBundle(sourceRoot, 'demo-bundle');
    final poolDir = p.join(base.path, 'session', 'plugins');
    await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );
    expect(Directory(p.join(poolDir, 'demo-bundle')).existsSync(), isTrue);

    final result = await service().reconcile(
      poolDir: poolDir,
      enabledPluginIds: const [],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );

    expect(result.linked, isEmpty);
    expect(Directory(p.join(poolDir, 'demo-bundle')).existsSync(), isFalse);
  });

  test('falls back to copy when symlinks are unavailable', () async {
    final memory = _NoSymlinkFilesystem();
    final memSourceRoot = '/plugins/installed';
    await memory.ensureDir('$memSourceRoot/demo-bundle/.plugin');
    await memory.writeString(
      '$memSourceRoot/demo-bundle/.plugin/plugin.json',
      '{"name":"demo","version":"1.0.0","description":""}',
    );

    final memPool = '/session/plugins';
    final result = await PluginBundlePoolService(
      fs: memory,
      sourceRoot: memSourceRoot,
    ).reconcile(
      poolDir: memPool,
      enabledPluginIds: ['acme/demo'],
      installedCatalog: [
        _plugin('acme/demo', 'demo', directory: 'demo-bundle'),
      ],
      paths: claudePluginManifestPaths,
    );

    expect(result.errors, isEmpty);
    expect(result.linked, ['demo-bundle']);
    expect(
      await memory.readString(
        '$memPool/demo-bundle/.claude-plugin/plugin.json',
      ),
      isNotNull,
    );
  });
}
