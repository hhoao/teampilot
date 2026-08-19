import 'dart:convert';

import '../../../../models/plugin.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_run_request.dart';
import '../../../host/host_run_result.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import '../provider/codex_session_config_dir.dart';

/// Prepares a TeamPilot-owned marketplace and lets Codex install it into the
/// session's native plugin store. TeamPilot deliberately never writes the
/// managed `$CODEX_HOME/plugins` tree.
final class CodexPluginCapability implements PluginCapability {
  const CodexPluginCapability();

  @override
  bool get writesAssembledMcp => false;

  @override
  PluginRuntimeOwnership get runtimeOwnership => PluginRuntimeOwnership.native;

  @override
  PluginManifestPaths? get manifestPaths => codexPluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const ['plugins'];

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.skills,
    PluginComponentKind.hooks,
    PluginComponentKind.apps,
    PluginComponentKind.mcp,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    final specs = await _prepareMarketplace(ctx, manifestPaths!);
    // ManifestFilesystem is used during the staging phase. The marketplace
    // files are recorded there and the native CLI is invoked after flush by
    // ConfigProfileService.provisionNativePlugins.
    final runner = ctx.hostOneShotRunner;
    if (runner == null) return;

    final executable = ctx.executable?.trim().isNotEmpty == true
        ? ctx.executable!.trim()
        : 'codex';
    final env = {'CODEX_HOME': ctx.configDir};
    Future<HostRunResult> run(List<String> args) async {
      final result = await runner.run(
        HostRunRequest(
          executable: executable,
          arguments: args,
          workingDirectory: ctx.configDir,
          environment: env,
          pathPrepend: ctx.pathPrepend,
        ),
      );
      if (!result.succeeded) {
        throw StateError(
          'Codex plugin command failed (${args.join(' ')}): '
          '${result.stderr.trim().isEmpty ? result.stdout.trim() : result.stderr.trim()}',
        );
      }
      return result;
    }

    if (specs.isNotEmpty) {
      final marketplaceRoot = _marketplaceRoot(ctx);
      await _writeMarketplaceManifest(
        fs: ctx.fs,
        marketplaceRoot: marketplaceRoot,
        pluginNames: specs.map((e) => e.name),
      );
      await run(['plugin', 'marketplace', 'add', marketplaceRoot, '--json']);
    }

    final list = await run(['plugin', 'list', '--json']);
    final installed = _parseInstalled(list.stdout);
    final desiredByName = {for (final spec in specs) spec.name: spec};

    // The native Codex store outlives the staged session manifest. Remove
    // TeamPilot-owned entries that are no longer enabled or whose source
    // version changed before adding the desired set below.
    for (final item in installed.where(
      (item) =>
          item.marketplace == CodexSessionConfigDir.teampilotMarketplaceName,
    )) {
      final desired = desiredByName[item.name];
      if (desired == null || desired.version != item.version) {
        await run([
          'plugin',
          'remove',
          '${item.name}@${CodexSessionConfigDir.teampilotMarketplaceName}',
          '--json',
        ]);
      }
    }

    if (specs.isEmpty) {
      final marketplaces = await run([
        'plugin',
        'marketplace',
        'list',
        '--json',
      ]);
      if (_parseMarketplaceNames(
        marketplaces.stdout,
      ).contains(CodexSessionConfigDir.teampilotMarketplaceName)) {
        await run([
          'plugin',
          'marketplace',
          'remove',
          CodexSessionConfigDir.teampilotMarketplaceName,
          '--json',
        ]);
      }
      return;
    }

    for (final spec in specs) {
      final legacyLocal = installed.where(
        (item) =>
            item.name == spec.name &&
            item.marketplace == CodexSessionConfigDir.localMarketplaceName,
      );
      if (legacyLocal.isNotEmpty && await _hasLegacyLocalInstall(ctx, spec)) {
        await run([
          'plugin',
          'remove',
          '${spec.name}@${CodexSessionConfigDir.localMarketplaceName}',
          '--json',
        ]);
        await _removeLegacyLocalInstall(ctx, spec);
      }
      final current = installed.where(
        (item) =>
            item.name == spec.name &&
            item.marketplace == CodexSessionConfigDir.teampilotMarketplaceName,
      );
      if (current.any((item) => item.version == spec.version)) continue;
      await run([
        'plugin',
        'add',
        '${spec.name}@${CodexSessionConfigDir.teampilotMarketplaceName}',
        '--json',
      ]);
    }
  }

  @override
  bool get consumesMarketplaces => false;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    Filesystem? homeFs,
    String? homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  static String _marketplaceRoot(PluginProvisionContext ctx) =>
      ctx.fs.pathContext.join(ctx.configDir, '.teampilot', 'codex-marketplace');

  static Future<bool> _hasLegacyLocalInstall(
    PluginProvisionContext ctx,
    _CodexNativePluginSpec spec,
  ) async {
    final source = CodexSessionConfigDir.localPluginSourceRoot(
      ctx.configDir,
      spec.name,
      pathContext: ctx.fs.pathContext,
    );
    return (await ctx.fs.stat(source)).exists;
  }

  static Future<void> _removeLegacyLocalInstall(
    PluginProvisionContext ctx,
    _CodexNativePluginSpec spec,
  ) async {
    final source = CodexSessionConfigDir.localPluginSourceRoot(
      ctx.configDir,
      spec.name,
      pathContext: ctx.fs.pathContext,
    );
    if ((await ctx.fs.stat(source)).exists) {
      await ctx.fs.removeRecursive(source);
    }
    final cache = CodexSessionConfigDir.localPluginCacheRoot(
      ctx.configDir,
      spec.name,
      version: spec.version,
      pathContext: ctx.fs.pathContext,
    );
    if ((await ctx.fs.stat(cache)).exists) {
      await ctx.fs.removeRecursive(cache);
    }
  }

  static Future<List<_CodexNativePluginSpec>> _prepareMarketplace(
    PluginProvisionContext ctx,
    PluginManifestPaths paths,
  ) async {
    final poolStat = await ctx.fs.stat(ctx.bundlePoolDir);
    if (!poolStat.isDirectory) return const <_CodexNativePluginSpec>[];

    final marketplaceRoot = _marketplaceRoot(ctx);
    if ((await ctx.fs.stat(marketplaceRoot)).exists) {
      await ctx.fs.removeRecursive(marketplaceRoot);
    }
    await ctx.fs.ensureDir(ctx.fs.pathContext.join(marketplaceRoot, 'plugins'));

    final enabledById = {
      for (final plugin in ctx.installedCatalog)
        if (ctx.enabledPluginIds.isEmpty ||
            ctx.enabledPluginIds.contains(plugin.id))
          plugin.id: plugin,
    };

    final enables = <_CodexNativePluginSpec>[];
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

      final cacheVersion = await _pluginCacheVersion(
        ctx.fs,
        root,
        paths: paths,
      );
      final sourceRoot = fsCtx.join(marketplaceRoot, 'plugins', pluginName);
      await ctx.fs.copyTree(source: root, destination: sourceRoot);
      await CliPluginLayout.projectBundleToFlavor(ctx.fs, sourceRoot, paths);

      enables.add(
        _CodexNativePluginSpec(name: pluginName, version: cacheVersion),
      );
    }

    return enables;
  }

  static Future<void> _writeMarketplaceManifest({
    required Filesystem fs,
    required String marketplaceRoot,
    required Iterable<String> pluginNames,
  }) async {
    final entries = pluginNames
        .map(_localMarketplaceEntry)
        .toList(growable: false);
    final manifestPath = fs.pathContext.join(
      marketplaceRoot,
      '.agents',
      'plugins',
      'marketplace.json',
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

  static Map<String, Object?> _localMarketplaceEntry(String pluginName) {
    return {
      'name': pluginName,
      'source': {'source': 'local', 'path': './plugins/$pluginName'},
      'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
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

  static List<_CodexNativePluginSpec> _parseInstalled(String stdout) {
    try {
      final root = (jsonDecode(stdout) as Map).cast<String, Object?>();
      final raw = root['installed'];
      if (raw is! List) return const [];
      return [
        for (final value in raw)
          if (value is Map)
            _CodexNativePluginSpec.fromJson(value.cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Set<String> _parseMarketplaceNames(String stdout) {
    try {
      final root = (jsonDecode(stdout) as Map).cast<String, Object?>();
      final raw = root['marketplaces'];
      if (raw is! List) return const {};
      return {
        for (final value in raw)
          if (value is Map)
            (((value['name'] ?? value['marketplaceName']) as String?) ?? '')
                .trim(),
      }..removeWhere((name) => name.isEmpty);
    } catch (_) {
      return const {};
    }
  }
}

final class _CodexNativePluginSpec {
  const _CodexNativePluginSpec({
    required this.name,
    required this.version,
    this.marketplace,
  });

  final String name;
  final String version;
  final String? marketplace;

  factory _CodexNativePluginSpec.fromJson(Map<String, Object?> json) {
    final id = ((json['pluginId'] ?? json['id']) as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : id.split('@').first;
    final marketplaceValue =
        (json['marketplaceName'] ?? json['marketplace']) as String?;
    final marketplace = marketplaceValue?.trim().isNotEmpty == true
        ? marketplaceValue!.trim()
        : (id.contains('@') ? id.split('@').skip(1).join('@') : null);
    return _CodexNativePluginSpec(
      name: name,
      version: (json['version'] as String?)?.trim() ?? '',
      marketplace: marketplace,
    );
  }
}
