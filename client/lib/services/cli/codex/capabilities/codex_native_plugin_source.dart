import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../../models/plugin.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../provider/codex_session_config_dir.dart';

/// The small source layer TeamPilot exposes to Codex's native installer.
///
/// Plugin payloads already exist in the reconciled session pool. The
/// marketplace only needs links to those immutable bundles plus a manifest;
/// copying the payload here defeats the pool's purpose and makes every launch
/// pay the full plugin I/O cost again.
final class CodexNativePluginSource {
  const CodexNativePluginSource._();

  static const sourceStampName = '.teampilot-source.json';

  static Future<CodexNativePluginSourceResult> prepare({
    required Filesystem fs,
    required String marketplaceRoot,
    required String bundlePoolDir,
    required List<String> enabledPluginIds,
    required List<Plugin> installedCatalog,
    required PluginManifestPaths paths,
  }) async {
    final poolStat = await fs.stat(bundlePoolDir);
    if (!poolStat.isDirectory) {
      return const CodexNativePluginSourceResult(
        plugins: [],
        sourceChanged: false,
      );
    }

    final enabledById = {
      for (final plugin in installedCatalog)
        if (enabledPluginIds.isEmpty || enabledPluginIds.contains(plugin.id))
          plugin.id: plugin,
    };
    final ctx = fs.pathContext;
    final plugins = <CodexNativePluginSpec>[];

    for (final entry in await fs.listDir(bundlePoolDir)) {
      if (entry.name.startsWith('.')) continue;
      final source = ctx.join(bundlePoolDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(fs, source)) continue;

      final root = await CliPluginLayout.resolvePluginRoot(
        fs,
        source,
        paths: paths,
      );
      if (root == null) continue;

      final manifest = await CliPluginLayout.readManifest(
        fs,
        root,
        paths: paths,
      );
      final pluginName = manifest?.name ?? entry.name;
      final catalogPlugin = _matchCatalogPlugin(
        enabledById: enabledById,
        bundleDirName: entry.name,
        manifestName: pluginName,
      );
      if (catalogPlugin == null && enabledPluginIds.isNotEmpty) continue;

      plugins.add(
        CodexNativePluginSpec(
          name: pluginName,
          version: await _pluginVersion(fs, root, paths: paths),
          source: root,
        ),
      );
    }

    plugins.sort((a, b) => a.name.compareTo(b.name));
    final fingerprint = jsonEncode([
      for (final plugin in plugins)
        {
          'name': plugin.name,
          'version': plugin.version,
          'source': plugin.source,
        },
    ]);
    final stampPath = ctx.join(marketplaceRoot, sourceStampName);

    if (await _isCurrent(
      fs: fs,
      marketplaceRoot: marketplaceRoot,
      stampPath: stampPath,
      fingerprint: fingerprint,
      plugins: plugins,
    )) {
      return CodexNativePluginSourceResult(
        plugins: plugins,
        sourceChanged: false,
        fingerprint: fingerprint,
      );
    }

    if ((await fs.stat(marketplaceRoot)).exists) {
      await fs.removeRecursive(marketplaceRoot);
    }
    await fs.ensureDir(ctx.join(marketplaceRoot, 'plugins'));

    for (final plugin in plugins) {
      final destination = ctx.join(marketplaceRoot, 'plugins', plugin.name);
      var linked = false;
      try {
        linked = await fs.createSymlink(
          target: plugin.source,
          linkPath: destination,
        );
      } on Object {
        linked = false;
      }
      if (!linked) {
        await fs.copyTree(source: plugin.source, destination: destination);
      }
    }

    await _writeMarketplaceManifest(
      fs: fs,
      marketplaceRoot: marketplaceRoot,
      pluginNames: plugins.map((plugin) => plugin.name),
    );
    await fs.atomicWrite(
      stampPath,
      const JsonEncoder.withIndent('  ').convert({
        'fingerprint': fingerprint,
        'plugins': [
          for (final plugin in plugins)
            {'name': plugin.name, 'version': plugin.version},
        ],
      }),
    );

    return CodexNativePluginSourceResult(
      plugins: plugins,
      sourceChanged: true,
      fingerprint: fingerprint,
    );
  }

  static Future<bool> _isCurrent({
    required Filesystem fs,
    required String marketplaceRoot,
    required String stampPath,
    required String fingerprint,
    required List<CodexNativePluginSpec> plugins,
  }) async {
    final stamp = await fs.readString(stampPath);
    if (stamp == null || stamp.trim().isEmpty) return false;

    try {
      final root = (jsonDecode(stamp) as Map).cast<String, Object?>();
      if (root['fingerprint'] != fingerprint) return false;
    } on Object {
      return false;
    }

    final ctx = fs.pathContext;
    final manifestPath = CodexSessionConfigDir.localMarketplaceManifestPath(
      marketplaceRoot,
      pathContext: ctx,
    );
    if (!(await fs.stat(manifestPath)).isFile) return false;
    for (final plugin in plugins) {
      final path = ctx.join(marketplaceRoot, 'plugins', plugin.name);
      final target = await fs.readSymlinkTarget(path);
      if (target != null) {
        if (_normalize(ctx, target) != _normalize(ctx, plugin.source)) {
          return false;
        }
      } else {
        // A copied fallback has no cheap way to prove that the source payload
        // did not change in place. Rebuild it on the next prepare instead of
        // serving stale plugin files when a version is reused.
        return false;
      }
    }
    return true;
  }

  static String _normalize(p.Context ctx, String path) =>
      ctx.normalize(ctx.absolute(path));

  static Future<void> _writeMarketplaceManifest({
    required Filesystem fs,
    required String marketplaceRoot,
    required Iterable<String> pluginNames,
  }) async {
    final entries = pluginNames
        .map(
          (name) => {
            'name': name,
            'source': {'source': 'local', 'path': './plugins/$name'},
            'policy': {
              'installation': 'AVAILABLE',
              'authentication': 'ON_INSTALL',
            },
            'category': 'Productivity',
          },
        )
        .toList(growable: false);
    final manifestPath = CodexSessionConfigDir.localMarketplaceManifestPath(
      marketplaceRoot,
      pathContext: fs.pathContext,
    );
    await fs.ensureDir(fs.pathContext.dirname(manifestPath));
    await fs.atomicWrite(
      manifestPath,
      const JsonEncoder.withIndent('  ').convert({
        'name': CodexSessionConfigDir.teampilotMarketplaceName,
        'plugins': entries,
      }),
    );
  }

  static Future<String> _pluginVersion(
    Filesystem fs,
    String pluginRoot, {
    required PluginManifestPaths paths,
  }) async {
    for (final rel in paths.manifestCandidates()) {
      final text = await fs.readString(fs.pathContext.join(pluginRoot, rel));
      if (text == null || text.trim().isEmpty) continue;
      try {
        final json = (jsonDecode(text) as Map).cast<String, Object?>();
        final version = (json['version'] as String?)?.trim();
        if (version != null && version.isNotEmpty) return version;
      } on Object {
        // Try the next supported manifest flavor.
      }
    }
    return 'local';
  }

  static Plugin? _matchCatalogPlugin({
    required Map<String, Plugin> enabledById,
    required String bundleDirName,
    required String manifestName,
  }) {
    for (final plugin in enabledById.values) {
      if (plugin.name == manifestName) return plugin;
    }
    for (final plugin in enabledById.values) {
      if (plugin.directory == bundleDirName) return plugin;
    }
    return null;
  }
}

final class CodexNativePluginSourceResult {
  const CodexNativePluginSourceResult({
    required this.plugins,
    required this.sourceChanged,
    this.fingerprint = '',
  });

  final List<CodexNativePluginSpec> plugins;
  final bool sourceChanged;
  final String fingerprint;
}

final class CodexNativePluginSpec {
  const CodexNativePluginSpec({
    required this.name,
    required this.version,
    this.marketplace,
    this.source = '',
  });

  final String name;
  final String version;
  final String? marketplace;
  final String source;

  factory CodexNativePluginSpec.fromJson(Map<String, Object?> json) {
    final id = ((json['pluginId'] ?? json['id']) as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : id.split('@').first;
    final marketplaceValue =
        (json['marketplaceName'] ?? json['marketplace']) as String?;
    final marketplace = marketplaceValue?.trim().isNotEmpty == true
        ? marketplaceValue!.trim()
        : (id.contains('@') ? id.split('@').skip(1).join('@') : null);
    return CodexNativePluginSpec(
      name: name,
      version: (json['version'] as String?)?.trim() ?? '',
      marketplace: marketplace,
    );
  }
}
