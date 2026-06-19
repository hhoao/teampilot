import 'dart:convert';

import '../../../../models/plugin.dart';
import '../../../io/filesystem.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../../../provider/codex/codex_session_config_dir.dart';
import '../capabilities/plugin_manifest_paths.dart';
import '../capabilities/plugin_provisioner_capability.dart';
import '../mcp_writers/codex_toml_merge.dart';

/// Materializes Codex's local marketplace + plugin cache and writes
/// `[marketplaces.local]` / `[plugins.*]` into `config.toml`.
final class CodexPluginProvisioner implements PluginProvisionerCapability {
  const CodexPluginProvisioner();

  @override
  PluginManifestPaths? get manifestPaths => codexPluginManifestPaths;

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.skills,
    PluginComponentKind.hooks,
    PluginComponentKind.apps,
    PluginComponentKind.mcp,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    final paths = manifestPaths!;
    final enables = await _materializeAndCollectEnables(ctx, paths);
    if (enables.isEmpty) return;

    await _writeLocalMarketplaceManifest(
      fs: ctx.fs,
      configDir: ctx.configDir,
      pluginNames: enables.map((e) => e.name),
    );

    final configPath = ctx.fs.pathContext.join(
      ctx.configDir,
      CodexHomeProvisioner.configFileName,
    );
    final stat = await ctx.fs.stat(configPath);
    final existing = stat.isFile ? await ctx.fs.readString(configPath) ?? '' : '';
    var merged = CodexTomlMerge.mergeLocalMarketplace(existing, ctx.configDir);
    merged = CodexTomlMerge.mergePluginEnables(merged, enables);
    if (merged.trim().isEmpty) return;
    await ctx.fs.ensureDir(ctx.configDir);
    await ctx.fs.atomicWrite(configPath, merged);
  }

  static Future<List<CodexPluginEnableSpec>> _materializeAndCollectEnables(
    PluginProvisionContext ctx,
    PluginManifestPaths paths,
  ) async {
    final poolStat = await ctx.fs.stat(ctx.bundlePoolDir);
    if (!poolStat.isDirectory) return const [];

    final enabledById = {
      for (final plugin in ctx.installedCatalog)
        if (ctx.enabledPluginIds.isEmpty ||
            ctx.enabledPluginIds.contains(plugin.id))
          plugin.id: plugin,
    };

    final enables = <CodexPluginEnableSpec>[];
    final fsCtx = ctx.fs.pathContext;

    for (final entry in await ctx.fs.listDir(ctx.bundlePoolDir)) {
      if (entry.name.startsWith('.')) continue;
      final source = fsCtx.join(ctx.bundlePoolDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(ctx.fs, source)) continue;

      final root = await CliPluginLayout.resolvePluginRoot(
        ctx.fs,
        source,
        paths: paths,
      );
      if (root == null) continue;

      final manifest = await CliPluginLayout.readManifest(
        ctx.fs,
        root,
        paths: paths,
      );
      final pluginName = manifest?.name ?? entry.name;
      final catalogPlugin = _matchCatalogPlugin(
        enabledById: enabledById,
        bundleDirName: entry.name,
        manifestName: pluginName,
      );
      if (catalogPlugin == null && ctx.enabledPluginIds.isNotEmpty) continue;

      final cacheVersion = await _pluginCacheVersion(ctx.fs, root, paths: paths);
      final sourceRoot = CodexSessionConfigDir.localPluginSourceRoot(
        ctx.configDir,
        pluginName,
      );
      final cacheRoot = CodexSessionConfigDir.localPluginCacheRoot(
        ctx.configDir,
        pluginName,
        version: cacheVersion,
      );

      for (final dir in [sourceRoot, cacheRoot]) {
        if ((await ctx.fs.stat(dir)).exists) {
          await ctx.fs.removeRecursive(dir);
        }
      }
      await ctx.fs.copyTree(source: root, destination: sourceRoot);
      await CliPluginLayout.projectBundleToFlavor(ctx.fs, sourceRoot, paths);
      await ctx.fs.copyTree(source: sourceRoot, destination: cacheRoot);

      enables.add(
        CodexPluginEnableSpec(
          name: pluginName,
          bundledMcpServerNames: await _readBundledMcpServerNames(
            ctx.fs,
            sourceRoot,
          ),
        ),
      );
    }

    return enables;
  }

  static Future<void> _writeLocalMarketplaceManifest({
    required Filesystem fs,
    required String configDir,
    required Iterable<String> pluginNames,
  }) async {
    final entries = pluginNames
        .map(_localMarketplaceEntry)
        .toList(growable: false);
    final manifestPath = CodexSessionConfigDir.localMarketplaceManifestPath(
      configDir,
    );
    await fs.ensureDir(fs.pathContext.dirname(manifestPath));
    await fs.atomicWrite(
      manifestPath,
      const JsonEncoder.withIndent('  ').convert({
        'name': CodexSessionConfigDir.localMarketplaceName,
        'plugins': entries,
      }),
    );
  }

  static Map<String, Object?> _localMarketplaceEntry(String pluginName) {
    return {
      'name': pluginName,
      'source': {
        'source': 'local',
        'path': './plugins/$pluginName',
      },
      'policy': {
        'installation': 'AVAILABLE',
        'authentication': 'ON_INSTALL',
      },
      'category': 'Productivity',
    };
  }

  static Future<String> _pluginCacheVersion(
    Filesystem fs,
    String pluginRoot, {
    required PluginManifestPaths paths,
  }) async {
    final ctx = fs.pathContext;
    for (final rel in paths.manifestCandidates()) {
      final text = await fs.readString(ctx.join(pluginRoot, rel));
      if (text == null || text.trim().isEmpty) continue;
      try {
        final json = (jsonDecode(text) as Map).cast<String, Object?>();
        final version = (json['version'] as String?)?.trim();
        if (version != null && version.isNotEmpty) return version;
      } catch (_) {
        continue;
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

  static Future<List<String>> _readBundledMcpServerNames(
    Filesystem fs,
    String pluginRoot,
  ) async {
    final mcpPath = fs.pathContext.join(pluginRoot, '.mcp.json');
    if (!(await fs.stat(mcpPath)).isFile) return const [];

    final text = await fs.readString(mcpPath);
    if (text == null || text.trim().isEmpty) return const [];

    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final wrapped =
          (root['mcpServers'] as Map?)?.cast<String, Object?>() ??
          (root['mcp_servers'] as Map?)?.cast<String, Object?>();
      if (wrapped != null && wrapped.isNotEmpty) {
        return wrapped.keys.toList()..sort();
      }

      const reservedKeys = {'mcpServers', 'mcp_servers'};
      final direct = root.entries
          .where((entry) => !reservedKeys.contains(entry.key))
          .where((entry) => entry.value is Map)
          .map((entry) => entry.key)
          .toList()
        ..sort();
      return direct;
    } catch (_) {
      return const [];
    }
  }
}
