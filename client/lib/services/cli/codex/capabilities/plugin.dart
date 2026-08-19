import 'dart:convert';

import '../../../io/filesystem.dart';
import '../../../host/host_run_request.dart';
import '../../../host/host_run_result.dart';
import '../../../../utils/logging/logger.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';
import '../../registry/capabilities/skill_capability.dart';
import 'codex_native_plugin_source.dart';
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
    final marketplaceRoot = _marketplaceRoot(ctx);
    final sourceStarted = Stopwatch()..start();
    final source = await CodexNativePluginSource.prepare(
      fs: ctx.fs,
      marketplaceRoot: marketplaceRoot,
      bundlePoolDir: ctx.bundlePoolDir,
      enabledPluginIds: ctx.enabledPluginIds,
      installedCatalog: ctx.installedCatalog,
      paths: manifestPaths!,
    );
    final specs = source.plugins;
    appLogger.d(
      '[session-launch] native-plugin-source done '
      'cli=${ctx.tool.value} plugins=${specs.length} '
      'changed=${source.sourceChanged} '
      'ms=${sourceStarted.elapsedMilliseconds}',
    );
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
      final marketplaces = await run([
        'plugin',
        'marketplace',
        'list',
        '--json',
      ]);
      final marketplaceRegistered = _parseMarketplaceNames(
        marketplaces.stdout,
      ).contains(CodexSessionConfigDir.teampilotMarketplaceName);
      if (!marketplaceRegistered) {
        await run(['plugin', 'marketplace', 'add', marketplaceRoot, '--json']);
      }
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
    CodexNativePluginSpec spec,
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
    CodexNativePluginSpec spec,
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

  static List<CodexNativePluginSpec> _parseInstalled(String stdout) {
    try {
      final root = (jsonDecode(stdout) as Map).cast<String, Object?>();
      final raw = root['installed'];
      if (raw is! List) return const [];
      return [
        for (final value in raw)
          if (value is Map)
            CodexNativePluginSpec.fromJson(value.cast<String, Object?>()),
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
